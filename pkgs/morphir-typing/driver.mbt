///|
/// What `infer` does with the file.
pub(all) enum Mode {
  /// Writes the solved types into the file.
  Fill
  /// Checks the file and returns it unchanged.
  Check
} derive(Eq, Debug)

///|
pub extend Mode with Eq::{equal, not_equal}

///|
pub extend Mode with @debug.Debug::{to_repr}

///|
/// A type variable that inference may solve to any type. It carries the unknown marker.
pub fn unknown_type(name : @ir.Name) -> @ir.Type {
  Variable(
    {
      source: None,
      constraints: Map([]),
      extensions: Map([(INFERENCE_KEY, Text(UNKNOWN))]),
    },
    name,
  )
}

///|
/// Infers the types of every value declaration of `file`. `deps` gives the specification of each package that
/// the file uses, as well as the dependencies that the file holds.
///
/// - `Fill` returns the file with an `inferred_type` on every `Value` and `Pattern` of the bodies that it
///   infers. Signature types that carry the unknown marker are replaced by their solutions.
/// - `Check` returns the file unchanged.
///
/// In both modes an existing `inferred_type` that disagrees with inference is `annotation_mismatch`. The problems
/// of every binding group are collected, and `InferenceFailed` holds them in the order of their logical paths.
/// A `Specs` file has no bodies: `Fill` returns it, and `Check` only checks that its references resolve.
pub fn infer(
  file : @ir.IRFile,
  deps : Map[@ir.PackageName, @ir.PackageSpecification],
  mode : Mode,
) -> @ir.IRFile raise InferenceFailed {
  if file.distribution is Specs(name, _, spec) {
    if mode is Check {
      fail_on(Env::from(deps, file).check_specification(name, spec))
    }
    return file
  }
  let driver = Driver::new(Env::from(deps, file), file)
  driver.report_cyclic_aliases()
  driver.declare_signatures()
  for group in driver.groups() {
    driver.solve(group)
  }
  let defs = driver.output()
  fail_on(driver.problems)
  match mode {
    Check => file
    Fill => rebuild_file(file, defs)
  }
}

///|
/// Raises `InferenceFailed` when there is a problem. The problems are sorted by logical path, and problems at
/// one path keep their order.
fn fail_on(problems : Array[InferenceProblem]) -> Unit raise InferenceFailed {
  if problems.is_empty() {
    return
  }
  let indexed = problems.mapi((i, p) => (i, p))
  indexed.sort_by((x, y) => {
    let c = lexical_compare(x.1.node, y.1.node)
    if c != 0 {
      c
    } else {
      x.0.compare(y.0)
    }
  })
  raise InferenceFailed(indexed.map(x => x.1))
}

///|
/// Compares two strings character by character. `String::compare` orders by length first.
fn lexical_compare(a : String, b : String) -> Int {
  let n = min_int(a.length(), b.length())
  for i = 0; i < n; i = i + 1 {
    let c = a.code_unit_at(i).compare(b.code_unit_at(i))
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}

///|
/// One value declaration of the file.
priv struct Decl {
  /// The canonical FQName.
  key : String
  /// The logical path of the declaration.
  root : String
  def : @ir.ValueDefinition
  /// A declared signature has no variable with the unknown marker. It is used through its scheme everywhere.
  declared : Bool
}

///|
/// The state of one call to `infer`.
priv struct Driver {
  env : Env
  decls : Array[Decl]
  /// The index of each declaration in `decls`, by canonical FQName.
  index : Map[String, Int]
  problems : Array[InferenceProblem]
  /// The solved state of each declaration whose binding group succeeded, by index.
  solved : Map[Int, Infer]
}

///|
fn Driver::new(env : Env, file : @ir.IRFile) -> Driver {
  let decls = collect_declarations(file)
  let index : Map[String, Int] = Map([])
  for i, d in decls {
    index[d.key] = i
  }
  { env, decls, index, problems: [], solved: Map([]), }
}

///|
/// Reports each cyclic alias as `unsupported` at its type path, `type:<package>:<module>#<name>`.
fn Driver::report_cyclic_aliases(self : Driver) -> Unit {
  for key, _ in self.env.cyclic_aliases {
    self.problems.push({
      code: "unsupported",
      node: "type:" + key,
      message: "the type alias `\{key}` refers to itself, so inference cannot expand it",
      expected: None,
      found: None,
      source: None,
    })
  }
}

///|
/// Puts the scheme of every declared signature into the environment before any group is solved. A declared
/// value is then polymorphic in its own body, which allows polymorphic recursion.
fn Driver::declare_signatures(self : Driver) -> Unit {
  for d in self.decls {
    if d.declared {
      let (inputs, output, _) = definition_parts(d.def)
      if output is Some(output) {
        self.env.values[d.key] = poly_of_signature(inputs, output)
      }
    }
  }
}

///|
/// Solves one binding group at level 1. Undeclared values are monomorphic in `current` while the group is
/// solved. The first failure stops the group: its other declarations are skipped, and its undeclared values get
/// an unconstrained scheme so that dependants do not report again.
///
/// The rigid variables of each signature belong to their declaration, so the class of each one is known in the
/// whole group: a body can meet the rigid of another declaration through the monomorphic type of that
/// declaration.
fn Driver::solve(self : Driver, group : Array[Int]) -> Unit {
  let infer = Infer::new(self.env, 1)
  let signatures = group.map(i => infer.signature(self.decls[i]))
  group.each(i => infer.declare_rigids(self.decls[i]))
  for k, i in group {
    let d = self.decls[i]
    if !d.declared {
      infer.current[d.key] = curry(signatures[k].0, signatures[k].1)
    }
  }
  let mut failed = false
  for k, i in group {
    let d = self.decls[i]
    infer.enter(d)
    infer.top_level(d, signatures[k]) catch {
      err => {
        self.problems.push(problem_of(d, err, infer.solver))
        failed = true
        break
      }
    }
  }
  for i in group {
    let d = self.decls[i]
    guard !d.declared else { continue }
    self.env.values[d.key] = if failed {
      { gens: [[]], body: Gen(0), }
    } else {
      infer.enter(d)
      infer.solver.generalize_with(
        infer.current[d.key],
        0,
        rigid_names(d.def).map(name => rigid_key(d.key, name)),
      )
    }
  }
  infer.solver.rigid_classes.clear()
  if !failed {
    group.each(i => self.solved[i] = infer)
  }
}

///|
/// The signature of a declaration: its input types and its output type. Marked variables are metas, shared by
/// name within the declaration, and other variables are rigid and belong to the declaration. A missing output
/// is a fresh meta.
fn Infer::signature(self : Infer, d : Decl) -> (Array[Ty], Ty) {
  let (inputs, output, _) = definition_parts(d.def)
  let types = inputs.map(input => input.1)
  if output is Some(t) {
    types.push(t)
  }
  let metas = self.marked_metas(types)
  let ins = inputs.map(input => {
    self.declared(input.1, metas, d.key, (_, _) => ())
  })
  let out = match output {
    Some(t) => self.declared(t, metas, d.key, (_, _) => ())
    None => self.fresh()
  }
  (ins, out)
}

///|
/// Adds the rigid variables of the signature of `d` to `rigid_classes`, keyed by owner.
fn Infer::declare_rigids(self : Infer, d : Decl) -> Unit {
  for rigid in signature_rigids(d.def) {
    self.solver.rigid_classes[rigid_key(d.key, rigid.0)] = rigid.1
  }
}

///|
/// Starts work on the declaration `d`: it owns the rigid variables that are declared from now on, and its
/// signature rigids are in `rigid_classes`.
fn Infer::enter(self : Infer, d : Decl) -> Unit {
  self.owner.val = d.key
  self.declare_rigids(d)
}

///|
/// Infers the body of a top-level declaration against its signature. The body is at `path_body(d.root)`. A
/// `typeclass` in the signature that is not one of the four classes is `unsupported` at `d.root`.
fn Infer::top_level(
  self : Infer,
  d : Decl,
  signature : (Array[Ty], Ty),
) -> Unit raise Located {
  let (inputs, output, body) = definition_parts(d.def)
  let types = inputs.map(input => input.1)
  if output is Some(t) {
    types.push(t)
  }
  if unknown_class(types) is Some(class) {
    raise ClassAt(d.root, class)
  }
  let (ins, out) = signature
  self.signatures[d.root] = [..ins, out]
  guard body is Some(body) else { return }
  self.scoped(() => {
    for i, input in inputs {
      self.bind(input.0, ins[i])
    }
    let bt = self.value(body, path_body(d.root))
    self.unify(path_body(d.root), out, bt)
  })
}

///|
/// The variables of a signature that do not carry the unknown marker, by canonical name, with their classes, in
/// first-seen order.
fn signature_rigids(
  def : @ir.ValueDefinition,
) -> Array[(String, Array[String])] {
  let (inputs, output, _) = definition_parts(def)
  let types = inputs.map(input => input.1)
  if output is Some(t) {
    types.push(t)
  }
  let out : Array[(String, Array[String])] = []
  for t in types {
    to_ty(t, (name, attrs) => {
      if !is_unknown(attrs) && !out.iter().any(r => r.0 == name) {
        out.push((name, classes_of(name, attrs)))
      }
      UnitTy
    })
    |> ignore
  }
  out
}

///|
fn rigid_names(def : @ir.ValueDefinition) -> Array[String] {
  signature_rigids(def).map(r => r.0)
}

///|
/// Whether a signature type has a variable with the unknown marker.
fn has_marker(t : @ir.Type) -> Bool {
  let mut found = false
  to_ty(t, (_, attrs) => {
    if is_unknown(attrs) {
      found = true
    }
    UnitTy
  })
  |> ignore
  found
}

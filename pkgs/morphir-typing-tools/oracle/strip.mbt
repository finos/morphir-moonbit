// Helpers for the oracle tests. They walk declarations with the logical path steps of
// `pkgs/morphir-typing/paths.mbt`, so that a path here names the same node as a path in an inference problem.

///|
/// Rebuilds a declaration. `node` sees each `Value` and `Pattern` before its children, with its path and
/// whether it is a `Literal` value. `signature` sees each definition, with its path, before its body.
priv struct Walker {
  node : (@ir.ValueAttributes, String, Bool) -> @ir.ValueAttributes
  signature : (@ir.ValueDefinition, String) -> @ir.ValueDefinition
}

///|
fn step(path : String, child : String) -> String {
  path + "/" + child
}

///|
/// A definition at `path`. Inference walks only expression bodies and external fallbacks, so this does too.
fn Walker::definition(
  self : Walker,
  def : @ir.ValueDefinition,
  path : String,
) -> @ir.ValueDefinition {
  match (self.signature)(def, path) {
    ExpressionBody(inputs, output, body) =>
      ExpressionBody(inputs, output, self.value(body, step(path, "body")))
    ExternalBody(inputs, output, bindings, Some(fallback)) =>
      ExternalBody(
        inputs,
        output,
        bindings,
        Some(self.value(fallback, step(path, "body"))),
      )
    other => other
  }
}

///|
fn Walker::leaf(
  self : Walker,
  a : @ir.ValueAttributes,
  path : String,
) -> @ir.ValueAttributes {
  (self.node)(a, path, false)
}

///|
fn Walker::value(self : Walker, v : @ir.Value, path : String) -> @ir.Value {
  match v {
    Literal(a, lit) => Literal((self.node)(a, path, true), lit)
    Constructor(a, name) => Constructor(self.leaf(a, path), name)
    Variable(a, name) => Variable(self.leaf(a, path), name)
    Reference(a, name) => Reference(self.leaf(a, path), name)
    FieldFunction(a, name) => FieldFunction(self.leaf(a, path), name)
    Unit(a) => Unit(self.leaf(a, path))
    Hole(a, reason, t) => Hole(self.leaf(a, path), reason, t)
    Tuple(a, items) => {
      let a = self.leaf(a, path)
      Tuple(a, items.mapi((i, x) => self.value(x, step(path, "items/\{i}"))))
    }
    List(a, items) => {
      let a = self.leaf(a, path)
      List(a, items.mapi((i, x) => self.value(x, step(path, "items/\{i}"))))
    }
    Record(a, fields) => {
      let a = self.leaf(a, path)
      Record(a, self.fields(fields, path))
    }
    Field(a, record, name) => {
      let a = self.leaf(a, path)
      Field(a, self.value(record, step(path, "record")), name)
    }
    UpdateRecord(a, record, fields) => {
      let a = self.leaf(a, path)
      let record = self.value(record, step(path, "record"))
      UpdateRecord(a, record, self.fields(fields, path))
    }
    _ => self.compound(v, path)
  }
}

///|
fn Walker::fields(
  self : Walker,
  fields : Map[@ir.Name, @ir.Value],
  path : String,
) -> Map[@ir.Name, @ir.Value] {
  let out : Map[@ir.Name, @ir.Value] = Map([])
  for name, field in fields {
    out[name] = self.value(field, step(path, "fields/" + name.to_canonical()))
  }
  out
}

///|
/// The values with a scope or with several kinds of child.
fn Walker::compound(self : Walker, v : @ir.Value, path : String) -> @ir.Value {
  match v {
    Apply(a, f, x) => {
      let a = self.leaf(a, path)
      let f = self.value(f, step(path, "function"))
      Apply(a, f, self.value(x, step(path, "argument")))
    }
    Lambda(a, p, body) => {
      let a = self.leaf(a, path)
      let p = self.pattern(p, step(path, "pattern"))
      Lambda(a, p, self.value(body, step(path, "body")))
    }
    LetDefinition(a, name, def, rest) => {
      let a = self.leaf(a, path)
      let def = self.definition(def, step(path, "definition"))
      LetDefinition(a, name, def, self.value(rest, step(path, "in")))
    }
    LetRecursion(a, defs, rest) => {
      let a = self.leaf(a, path)
      let out : Map[@ir.Name, @ir.ValueDefinition] = Map([])
      for name, def in defs {
        out[name] = self.definition(
          def,
          step(path, "definitions/" + name.to_canonical()),
        )
      }
      LetRecursion(a, out, self.value(rest, step(path, "in")))
    }
    Destructure(a, p, value, rest) => {
      let a = self.leaf(a, path)
      let p = self.pattern(p, step(path, "pattern"))
      let value = self.value(value, step(path, "value"))
      Destructure(a, p, value, self.value(rest, step(path, "in")))
    }
    IfThenElse(a, c, t, e) => {
      let a = self.leaf(a, path)
      let c = self.value(c, step(path, "condition"))
      let t = self.value(t, step(path, "then"))
      IfThenElse(a, c, t, self.value(e, step(path, "else")))
    }
    PatternMatch(a, subject, cases) => {
      let a = self.leaf(a, path)
      let subject = self.value(subject, step(path, "subject"))
      let cases = cases.mapi((i, c) => {
        let p = self.pattern(c.0, step(path, "cases/\{i}/pattern"))
        (p, self.value(c.1, step(path, "cases/\{i}/body")))
      })
      PatternMatch(a, subject, cases)
    }
    _ => v
  }
}

///|
fn Walker::pattern(
  self : Walker,
  p : @ir.Pattern,
  path : String,
) -> @ir.Pattern {
  match p {
    WildcardPattern(a) => WildcardPattern(self.leaf(a, path))
    EmptyListPattern(a) => EmptyListPattern(self.leaf(a, path))
    UnitPattern(a) => UnitPattern(self.leaf(a, path))
    LiteralPattern(a, lit) => LiteralPattern(self.leaf(a, path), lit)
    AsPattern(a, inner, name) => {
      let a = self.leaf(a, path)
      AsPattern(a, self.pattern(inner, step(path, "pattern")), name)
    }
    TuplePattern(a, items) => {
      let a = self.leaf(a, path)
      TuplePattern(
        a,
        items.mapi((i, x) => self.pattern(x, step(path, "items/\{i}"))),
      )
    }
    ConstructorPattern(a, name, args) => {
      let a = self.leaf(a, path)
      let args = args.mapi((i, x) => self.pattern(x, step(path, "args/\{i}")))
      ConstructorPattern(a, name, args)
    }
    HeadTailPattern(a, head, tail) => {
      let a = self.leaf(a, path)
      let head = self.pattern(head, step(path, "head"))
      HeadTailPattern(a, head, self.pattern(tail, step(path, "tail")))
    }
  }
}

///|
/// Applies `walk` to every value declaration of `file`, with the declaration's root path
/// `value:<package>:<module>#<name>`, and rebuilds the file.
fn map_declarations(
  file : @ir.IRFile,
  walk : (@ir.ValueDefinition, String) -> @ir.ValueDefinition,
) -> @ir.IRFile {
  let rebuild = fn(
    pkg_name : @ir.PackageName,
    def : @ir.PackageDefinition,
  ) -> @ir.PackageDefinition {
    let modules : Map[
      @ir.ModuleName,
      @ir.AccessControlled[@ir.ModuleDefinition],
    ] = Map([])
    for module_, m in def.modules {
      let values : Map[
        @ir.Name,
        @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
      ] = Map([])
      for name, v in m.value.values {
        let fq : @ir.FQName = {
          package_name: pkg_name,
          module_name: module_,
          local_name: name,
        }
        let new = walk(v.value.value, "value:" + fq.to_canonical())
        values[name] = { ..v, value: { ..v.value, value: new, }, }
      }
      modules[module_] = { ..m, value: { ..m.value, values, }, }
    }
    { modules, }
  }
  let distribution : @ir.Distribution = match file.distribution {
    Library(name, deps, def) => Library(name, deps, rebuild(name, def))
    Application(name, bundled, def, entries) =>
      Application(name, bundled, rebuild(name, def), entries)
    Specs(_, _, _) => return file
  }
  @ir.IRFile::new(distribution, format_version=file.format_version) catch {
    _ => abort("the format version of the file is not valid")
  }
}

///|
/// Visits every node and signature of `file` without changing it. `signature` also sees whether the definition
/// is a let definition.
fn visit(
  file : @ir.IRFile,
  node : (@ir.ValueAttributes, String, Bool) -> Unit,
  signature : (@ir.ValueDefinition, String, Bool) -> Unit,
) -> Unit {
  map_declarations(file, (def, root) => {
    let walker : Walker = {
      node: (a, path, literal) => {
        node(a, path, literal)
        a
      },
      signature: (def, path) => {
        signature(def, path, path != root)
        def
      },
    }
    walker.definition(def, root)
  })
  |> ignore
}

///|
/// `file` with no node types for inference to use, for criterion B. Every `inferred_type` that inference walks is
/// `None`, and the let placeholders are marked with `mark_classic_let_placeholders`. Top-level signatures stay.
/// Classic IR does not separate annotated signatures from inferred ones, so a stripped top-level signature would
/// give a type that is correctly more general than the Elm annotation.
pub fn strip_node_types(file : @ir.IRFile) -> @ir.IRFile {
  let walker : Walker = {
    node: (a, _, _) => { ..a, inferred_type: None, },
    signature: (def, _) => def,
  }
  mark_classic_let_placeholders(
    map_declarations(file, (def, root) => walker.definition(def, root)),
  )
}

///|
/// `file` with no types for inference to use, for criterion A. It is `strip_node_types`, and also every
/// top-level signature type is an unknown variable: `t-0`, `t-1`, … in order, counted per declaration. An
/// incomplete definition with no output type keeps `None`. Inference must then solve every signature and type
/// every node.
pub fn strip_full(file : @ir.IRFile) -> @ir.IRFile {
  map_declarations(strip_node_types(file), (def, _) => {
    let mut counter = 0
    let unknown = fn(_ : @ir.Type) -> @ir.Type {
      let t = @typing.unknown_type(@ir.Name::from_words(["t", "\{counter}"]))
      counter += 1
      t
    }
    let inputs = fn(xs : Array[(@ir.Name, @ir.Type)]) {
      xs.map(x => (x.0, unknown(x.1)))
    }
    match def {
      ExpressionBody(xs, out, body) => {
        let xs = inputs(xs)
        ExpressionBody(xs, unknown(out), body)
      }
      NativeBody(xs, out, info) => {
        let xs = inputs(xs)
        NativeBody(xs, unknown(out), info)
      }
      ExternalBody(xs, out, bindings, fallback) => {
        let xs = inputs(xs)
        ExternalBody(xs, unknown(out), bindings, fallback)
      }
      IncompleteBody(xs, out, why, value) => {
        let xs = inputs(xs)
        IncompleteBody(xs, out.map(unknown), why, value)
      }
    }
  })
}

///|
/// Whether `name` is a morphir-elm placeholder: `t-` followed by digits, as in `t-8`.
fn is_placeholder(name : @ir.Name) -> Bool {
  match name.to_canonical() {
    [.. "t-", .. rest] if rest.length() > 0 =>
      rest.iter().all(c => c >= '0' && c <= '9')
    _ => false
  }
}

///|
/// `attrs` with the unknown marker of `@typing.unknown_type`.
fn with_marker(attrs : @ir.TypeAttributes) -> @ir.TypeAttributes {
  let extensions = attrs.extensions.copy()
  guard @typing.unknown_type(@ir.Name::from_words(["t"])) is Variable(marked, _) else {
    abort("unknown_type is a variable")
  }
  for key, value in marked.extensions {
    extensions[key] = value
  }
  { ..attrs, extensions, }
}

///|
/// `t` with the unknown marker on each placeholder variable. A placeholder row variable marks its record, because
/// inference reads a row variable's marker from the record's attributes.
fn mark_placeholders(t : @ir.Type) -> @ir.Type {
  let go_fields = fn(fields : Map[@ir.Name, @ir.Type]) {
    let out : Map[@ir.Name, @ir.Type] = Map([])
    for name, field in fields {
      out[name] = mark_placeholders(field)
    }
    out
  }
  match t {
    Variable(attrs, name) if is_placeholder(name) =>
      Variable(with_marker(attrs), name)
    Variable(_, _) | Unit(_) => t
    Reference(attrs, name, args) =>
      Reference(attrs, name, args.map(mark_placeholders))
    Tuple(attrs, items) => Tuple(attrs, items.map(mark_placeholders))
    Record(attrs, fields) => Record(attrs, go_fields(fields))
    ExtensibleRecord(attrs, row, fields) => {
      let attrs = if is_placeholder(row) { with_marker(attrs) } else { attrs }
      ExtensibleRecord(attrs, row, go_fields(fields))
    }
    Function(attrs, input, output) =>
      Function(attrs, mark_placeholders(input), mark_placeholders(output))
  }
}

///|
/// Whether `t` has a placeholder variable.
fn has_placeholder(t : @ir.Type) -> Bool {
  match t {
    Variable(_, name) => is_placeholder(name)
    Unit(_) => false
    Reference(_, _, items) | Tuple(_, items) =>
      items.iter().any(has_placeholder)
    Record(_, fields) => fields.values().any(has_placeholder)
    ExtensibleRecord(_, row, fields) =>
      is_placeholder(row) || fields.values().any(has_placeholder)
    Function(_, input, output) =>
      has_placeholder(input) || has_placeholder(output)
  }
}

///|
/// `file` with the unknown marker on each placeholder variable of a let-definition signature.
///
/// morphir-elm writes a signature for every let definition. When the Elm source has no annotation for the let,
/// the signature keeps the type variables that the frontend made before inference, named `t` and a number
/// (`t8`, canonical `t-8`). The solved types are only on the nodes. Without a marker, inference would check such
/// a variable as a rigid annotation and report `rigid_variable`. The marker tells inference that it may solve
/// the variable. Top-level signatures are not changed.
pub fn mark_classic_let_placeholders(file : @ir.IRFile) -> @ir.IRFile {
  let mark_inputs = fn(xs : Array[(@ir.Name, @ir.Type)]) {
    xs.map(x => (x.0, mark_placeholders(x.1)))
  }
  map_declarations(file, (def, root) => {
    let walker : Walker = {
      node: (a, _, _) => a,
      signature: (def, path) => {
        guard path != root else { return def }
        match def {
          ExpressionBody(xs, out, body) =>
            ExpressionBody(mark_inputs(xs), mark_placeholders(out), body)
          NativeBody(xs, out, info) =>
            NativeBody(mark_inputs(xs), mark_placeholders(out), info)
          ExternalBody(xs, out, bindings, fallback) =>
            ExternalBody(
              mark_inputs(xs),
              mark_placeholders(out),
              bindings,
              fallback,
            )
          IncompleteBody(xs, out, why, value) =>
            IncompleteBody(
              mark_inputs(xs),
              out.map(mark_placeholders),
              why,
              value,
            )
        }
      },
    }
    walker.definition(def, root)
  })
}

///|
/// The signature types of a definition, keyed `<path>:input/<i>` and `<path>:output`.
fn signature_entries(
  def : @ir.ValueDefinition,
  path : String,
) -> Array[(String, @ir.Type)] {
  let (xs, out) = match def {
    ExpressionBody(xs, out, _)
    | NativeBody(xs, out, _)
    | ExternalBody(xs, out, _, _) => (xs, Some(out))
    IncompleteBody(xs, out, _, _) => (xs, out)
  }
  let entries = xs.mapi((i, x) => (path + ":input/\{i}", x.1))
  if out is Some(t) {
    entries.push((path + ":output", t))
  }
  entries
}

///|
/// Every node type and signature type of `file`, by logical path, in walk order. With `skip_placeholders`, a
/// let-signature type that has a morphir-elm placeholder variable is left out: it holds no type to compare.
fn typed_entries(
  file : @ir.IRFile,
  skip_placeholders : Bool,
) -> Array[(String, @ir.Type?)] {
  let out : Array[(String, @ir.Type?)] = []
  visit(file, (a, path, _) => out.push((path, a.inferred_type)), (
    def,
    path,
    is_let,
  ) => {
    for entry in signature_entries(def, path) {
      if skip_placeholders && is_let && has_placeholder(entry.1) {
        continue
      }
      out.push((entry.0, Some(entry.1)))
    }
  })
  out
}

///|
/// The type aliases that `file` can use: those of the SDK, of the file's dependencies and of the file's own
/// package, by canonical FQName.
fn aliases_of(file : @ir.IRFile) -> Map[String, (Array[String], @ir.Type)] {
  let out : Map[String, (Array[String], @ir.Type)] = Map([])
  let add_spec = fn(
    pkg_name : @ir.PackageName,
    spec : @ir.PackageSpecification,
  ) {
    for module_, m in spec.modules {
      for name, t in m.types {
        if t.value.body is TypeAliasSpecification(params, body) {
          let fq : @ir.FQName = {
            package_name: pkg_name,
            module_name: module_,
            local_name: name,
          }
          out[fq.to_canonical()] = (params.map(p => p.to_canonical()), body)
        }
      }
    }
  }
  let add_def = fn(pkg_name : @ir.PackageName, def : @ir.PackageDefinition) {
    for module_, m in def.modules {
      for name, t in m.value.types {
        if t.value.value is TypeAliasDefinition(params, body) {
          let fq : @ir.FQName = {
            package_name: pkg_name,
            module_name: module_,
            local_name: name,
          }
          out[fq.to_canonical()] = (params.map(p => p.to_canonical()), body)
        }
      }
    }
  }
  add_spec(@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification())
  match file.distribution {
    Library(name, deps, def) => {
      for dep, spec in deps {
        add_spec(dep, spec)
      }
      add_def(name, def)
    }
    Application(name, bundled, def, _) => {
      for dep, dep_def in bundled {
        add_def(dep, dep_def)
      }
      add_def(name, def)
    }
    Specs(name, deps, spec) => {
      for dep, dep_spec in deps {
        add_spec(dep, dep_spec)
      }
      add_spec(name, spec)
    }
  }
  out
}

///|
/// `t` with every alias reference expanded. An alias that is already being expanded stays a reference, so a
/// cyclic alias ends.
fn expand(
  aliases : Map[String, (Array[String], @ir.Type)],
  t : @ir.Type,
  active : Array[String],
) -> @ir.Type {
  let go = fn(x : @ir.Type) { expand(aliases, x, active) }
  let go_fields = fn(fields : Map[@ir.Name, @ir.Type]) {
    let out : Map[@ir.Name, @ir.Type] = Map([])
    for name, field in fields {
      out[name] = go(field)
    }
    out
  }
  match t {
    Reference(attrs, name, args) => {
      let args = args.map(go)
      let key = name.to_canonical()
      match aliases.get(key) {
        Some((params, body)) if params.length() == args.length() &&
          !active.contains(key) => {
          let bound : Map[String, @ir.Type] = Map([])
          for i, p in params {
            bound[p] = args[i]
          }
          expand(aliases, substitute(body, bound), [..active, key])
        }
        _ => Reference(attrs, name, args)
      }
    }
    Tuple(attrs, items) => Tuple(attrs, items.map(go))
    Record(attrs, fields) => Record(attrs, go_fields(fields))
    ExtensibleRecord(attrs, row, fields) =>
      ExtensibleRecord(attrs, row, go_fields(fields))
    Function(attrs, input, output) => Function(attrs, go(input), go(output))
    Variable(_, _) | Unit(_) => t
  }
}

///|
/// `t` with each variable in `bound` replaced. A row variable bound to a variable is renamed.
fn substitute(t : @ir.Type, bound : Map[String, @ir.Type]) -> @ir.Type {
  let go = fn(x : @ir.Type) { substitute(x, bound) }
  let go_fields = fn(fields : Map[@ir.Name, @ir.Type]) {
    let out : Map[@ir.Name, @ir.Type] = Map([])
    for name, field in fields {
      out[name] = go(field)
    }
    out
  }
  match t {
    Variable(_, name) =>
      match bound.get(name.to_canonical()) {
        Some(arg) => arg
        None => t
      }
    Reference(attrs, name, args) => Reference(attrs, name, args.map(go))
    Tuple(attrs, items) => Tuple(attrs, items.map(go))
    Record(attrs, fields) => Record(attrs, go_fields(fields))
    ExtensibleRecord(attrs, row, fields) => {
      let row = match bound.get(row.to_canonical()) {
        Some(Variable(_, other)) => other
        _ => row
      }
      ExtensibleRecord(attrs, row, go_fields(fields))
    }
    Function(attrs, input, output) => Function(attrs, go(input), go(output))
    Unit(_) => t
  }
}

///|
/// A type with full canonical names, for oracle output.
fn type_text(t : @ir.Type) -> String {
  let fields_text = fn(fields : Map[@ir.Name, @ir.Type]) {
    fields
    .iter()
    .map(f => f.0.to_canonical() + " : " + type_text(f.1))
    .collect()
    .join(", ")
  }
  match t {
    Variable(_, name) => name.to_canonical()
    Reference(_, name, []) => name.to_canonical()
    Reference(_, name, args) =>
      "(" + [name.to_canonical(), ..args.map(type_text)].join(" ") + ")"
    Tuple(_, items) => "(tuple " + items.map(type_text).join(" ") + ")"
    Record(_, fields) => "{ " + fields_text(fields) + " }"
    ExtensibleRecord(_, row, fields) =>
      "{ " + row.to_canonical() + " | " + fields_text(fields) + " }"
    Function(_, input, output) =>
      "(" + type_text(input) + " -> " + type_text(output) + ")"
    Unit(_) => "()"
  }
}

///|
fn option_text(t : @ir.Type?) -> String {
  match t {
    Some(t) => type_text(t)
    None => "no type"
  }
}

///|
/// The differences between the types of `original` and of `filled`, one line per node or signature type:
/// `<path>: expected <t1>, found <t2>`. Types are compared with `@typing.types_equivalent` after alias
/// expansion. A path that `original` has and `filled` lacks is a difference too. A let-signature type of
/// `original` that has a morphir-elm placeholder (see `mark_classic_let_placeholders`) is not compared.
pub fn compare_types(
  original : @ir.IRFile,
  filled : @ir.IRFile,
) -> Array[String] {
  let aliases = aliases_of(original)
  let expected = typed_entries(original, true)
  let found : Map[String, @ir.Type?] = Map::from_array(
    typed_entries(filled, false),
  )
  let out : Array[String] = []
  for entry in expected {
    let (path, want) = entry
    let have = found.get(path)
    let same = match (want, have) {
      (Some(a), Some(Some(b))) =>
        @typing.types_equivalent(expand(aliases, a, []), expand(aliases, b, []))
      (None, Some(None)) => true
      _ => false
    }
    if !same {
      let have_text = match have {
        Some(t) => option_text(t)
        None => "no path"
      }
      out.push("\{path}: expected \{option_text(want)}, found \{have_text}")
    }
  }
  let known : Map[String, Bool] = Map::from_array(
    typed_entries(original, false).map(entry => (entry.0, true)),
  )
  for path, t in found {
    if !known.contains(path) {
      out.push("\{path}: expected no path, found \{option_text(t)}")
    }
  }
  out
}

///|
/// `file` with the `inferred_type` of its first `Literal` value changed: to `String`, or to `Int` when it was
/// `String`. The result also holds the logical path of that node.
pub fn mutate_first_literal_type(file : @ir.IRFile) -> (@ir.IRFile, String) {
  let string_type : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("morphir/SDK:string#string") catch {
      _ => abort("string#string")
    },
    [],
  )
  let int_type : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("morphir/SDK:basics#int") catch {
      _ => abort("basics#int")
    },
    [],
  )
  let mut found : String? = None
  let walker : Walker = {
    node: (a, path, literal) => {
      guard literal && found is None else { return a }
      found = Some(path)
      let replacement = match a.inferred_type {
        Some(t) if @typing.types_equivalent(t, string_type) => int_type
        _ => string_type
      }
      { ..a, inferred_type: Some(replacement), }
    },
    signature: (def, _) => def,
  }
  let mutated = map_declarations(file, (def, path) => {
    walker.definition(def, path)
  })
  guard found is Some(path) else { abort("the file has no literal") }
  (mutated, path)
}

///|
/// The number of `Value` and `Pattern` nodes of `file` with no `inferred_type`.
pub fn count_untyped(file : @ir.IRFile) -> Int {
  let mut count = 0
  visit(file, (a, _, _) => if a.inferred_type is None { count += 1 }, (_, _, _) => {
    ()
  })
  count
}

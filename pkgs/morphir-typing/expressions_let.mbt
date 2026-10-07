///|
/// A fresh meta at the current level for each variable of `types` that carries the unknown marker, by canonical
/// name. All occurrences of one name share the meta.
fn Infer::marked_metas(
  self : Infer,
  types : Array[@ir.Type],
) -> Map[String, Ty] {
  let metas : Map[String, Ty] = Map([])
  for t in types {
    to_ty(t, (name, attrs) => {
      if is_unknown(attrs) && !metas.contains(name) {
        metas[name] = self.solver.fresh(self.level, classes_of(name, attrs))
      }
      UnitTy
    })
    |> ignore
  }
  metas
}

///|
/// Converts a declared type. A variable in `metas` is that meta. Any other variable is rigid; `on_rigid` sees
/// its name and its classes.
fn Infer::declared(
  self : Infer,
  t : @ir.Type,
  metas : Map[String, Ty],
  on_rigid : (String, Array[String]) -> Unit,
) -> Ty {
  ignore(self)
  to_ty(t, (name, attrs) => {
    match metas.get(name) {
      Some(meta) => meta
      None => {
        on_rigid(name, classes_of(name, attrs))
        Rigid(name)
      }
    }
  })
}

///|
/// The inputs, the declared output and the body to infer of a definition. Native and incomplete bodies use
/// their signature only.
fn definition_parts(
  def : @ir.ValueDefinition,
) -> (Array[(@ir.Name, @ir.Type)], @ir.Type?, @ir.Value?) {
  match def {
    ExpressionBody(inputs, output, body) => (inputs, Some(output), Some(body))
    NativeBody(inputs, output, _) => (inputs, Some(output), None)
    ExternalBody(inputs, output, _, fallback) =>
      (inputs, Some(output), fallback)
    IncompleteBody(inputs, output, _, _) => (inputs, output, None)
  }
}

///|
/// Infers a definition at the current level. Its body is at `path_body(path)`. The declared input and output
/// types constrain it: marked variables are metas, and other variables are rigid. A rigid variable that is not
/// yet in `rigid_classes` is declared here: it is added with its classes and returned. The result is the
/// curried type of the definition.
fn Infer::definition(
  self : Infer,
  def : @ir.ValueDefinition,
  path : String,
) -> (Ty, Array[String]) raise Located {
  let (inputs, output, body) = definition_parts(def)
  let signature = inputs.map(input => input.1)
  if output is Some(t) {
    signature.push(t)
  }
  let metas = self.marked_metas(signature)
  let owned : Array[String] = []
  let on_rigid = fn(name : String, classes : Array[String]) {
    if !self.solver.rigid_classes.contains(name) {
      owned.push(name)
      self.solver.rigid_classes[name] = classes
    }
  }
  let ins = inputs.map(input => self.declared(input.1, metas, on_rigid))
  let out = match output {
    Some(t) => self.declared(t, metas, on_rigid)
    None => self.fresh()
  }
  if body is Some(body) {
    self.scoped(() => {
      for i, input in inputs {
        self.bind(input.0, ins[i])
      }
      let bt = self.value(body, path_body(path))
      self.unify(path_body(path), out, bt)
    })
  }
  (curry(ins, out), owned)
}

///|
/// Fails when a rigid variable in `owned` occurs in the type of a local or of the current group: the variable
/// would escape the definition that declares it.
fn Infer::check_escape(
  self : Infer,
  owned : Array[String],
  path : String,
) -> Unit raise Located {
  let outer = self.locals.values().map(p => p.body).collect()
  outer.append(self.current.values().collect())
  for name in owned {
    for t in outer {
      if self.solver.mentions_rigid(t, name) {
        raise MismatchAt(path, Mismatch("rigid_variable", Rigid(name), t))
      }
    }
  }
}

///|
/// Whether the rigid variable `name` occurs in `t`.
fn Solver::mentions_rigid(self : Solver, t : Ty, name : String) -> Bool {
  match self.prune(t) {
    Rigid(other) => other == name
    Con(_, items) | Tup(items) =>
      items.iter().any(x => self.mentions_rigid(x, name))
    Fun(input, output) =>
      self.mentions_rigid(input, name) || self.mentions_rigid(output, name)
    Rec(fields, tail) =>
      fields.values().any(x => self.mentions_rigid(x, name)) ||
      (tail is Some(row) && self.mentions_rigid(row, name))
    Meta(_) | Gen(_) | UnitTy => false
  }
}

///|
/// Removes the rigid variables that a let signature declared, once its scheme is made.
fn Infer::release(self : Infer, owned : Array[String]) -> Unit {
  for name in owned {
    self.solver.rigid_classes.remove(name)
  }
}

///|
/// `let name = def in rest`: the definition is inferred one level deeper and generalized at this level.
fn Infer::value_let(
  self : Infer,
  name : @ir.Name,
  def : @ir.ValueDefinition,
  rest : @ir.Value,
  path : String,
) -> Ty raise Located {
  let (t, owned) = self.deeper().definition(def, path_definition(path))
  self.check_escape(owned, path)
  let poly = self.solver.generalize_with(t, self.level, owned)
  self.release(owned)
  self.scoped(() => {
    self.locals[name.to_canonical()] = poly
    self.value(rest, path_in(path))
  })
}

///|
/// A recursive group: every name has a meta one level deeper while the group is solved, and the names are
/// generalized together.
fn Infer::value_let_recursion(
  self : Infer,
  defs : Map[@ir.Name, @ir.ValueDefinition],
  rest : @ir.Value,
  path : String,
) -> Ty raise Located {
  let inner = self.deeper()
  let monos : Map[@ir.Name, Ty] = Map([])
  for name, _ in defs {
    monos[name] = inner.fresh()
  }
  let owned : Array[String] = []
  inner.scoped(() => {
    for name, mono in monos {
      inner.bind(name, mono)
    }
    for name, def in defs {
      let (t, own) = inner.definition(def, path_definitions(path, name))
      owned.append(own)
      inner.unify(path_definitions_body(path, name), monos[name], t)
    }
  })
  self.check_escape(owned, path)
  let polys = monos
    .iter()
    .map(item => {
      (item.0, self.solver.generalize_with(item.1, self.level, owned))
    })
    .collect()
  self.release(owned)
  self.scoped(() => {
    for item in polys {
      self.locals[item.0.to_canonical()] = item.1
    }
    self.value(rest, path_in(path))
  })
}

///|
/// `let p = value in rest`: the pattern takes the type of the value, and binds monomorphically.
fn Infer::value_destructure(
  self : Infer,
  p : @ir.Pattern,
  value : @ir.Value,
  rest : @ir.Value,
  path : String,
) -> Ty raise Located {
  let vt = self.value(value, path_value(path))
  self.scoped(() => {
    let pt = self.pattern(p, path_pattern(path))
    self.unify(path_pattern(path), pt, vt)
    self.value(rest, path_in(path))
  })
}

///|
/// Whether `a` and `b` are the same type after a bijective renaming of their variables. Attributes do not count,
/// and a tuple of no items is the unit type. A record row variable is a variable.
///
/// This compares one pair of types alone. To compare the types of one declaration, use `TypeScope`.
pub fn types_equivalent(a : @ir.Type, b : @ir.Type) -> Bool {
  equivalent(a, b, { ab: Map([]), ba: Map([]), classes: false, })
}

///|
/// The renaming of type variables that the types of one declaration share. Inference names the variables of
/// one declaration consistently, so every type of the declaration is compared under one bijection:
///
/// - the variables of the declaration's signature (those without the unknown marker) map to themselves;
/// - any other variable pairs with one variable, and the pair holds for every later type;
/// - two paired variables have the same class set, from the `typeclass` constraint or the name prefix.
pub struct TypeScope {
  priv renaming : Renaming
}

///|
/// The scope of the declaration `def`, with its signature variables mapped to themselves.
pub fn TypeScope::of_definition(def : @ir.ValueDefinition) -> TypeScope {
  let renaming : Renaming = { ab: Map([]), ba: Map([]), classes: true, }
  for name in rigid_names(def) {
    renaming.ab[name] = name
    renaming.ba[name] = name
  }
  { renaming, }
}

///|
/// Whether `a`, a type of the declaration, is equivalent to `b` in this scope. When they are, the new variable
/// pairs are kept. When they are not, the scope does not change.
pub fn TypeScope::equivalent(
  self : TypeScope,
  a : @ir.Type,
  b : @ir.Type,
) -> Bool {
  let trial : Renaming = {
    ab: self.renaming.ab.copy(),
    ba: self.renaming.ba.copy(),
    classes: true,
  }
  guard equivalent(a, b, trial) else { return false }
  for x, y in trial.ab {
    self.renaming.ab[x] = y
    self.renaming.ba[y] = x
  }
  true
}

///|
/// A bijection between the variables of two sides. `ab` maps the variables of `a` to those of `b`, and `ba` is
/// its inverse. With `classes`, paired variables must have the same class set.
priv struct Renaming {
  ab : Map[String, String]
  ba : Map[String, String]
  classes : Bool
}

///|
fn equivalent(a : @ir.Type, b : @ir.Type, r : Renaming) -> Bool {
  match (a, b) {
    (Variable(c1, x), Variable(c2, y)) => same_variable(x, c1, y, c2, r)
    (Reference(_, n1, a1), Reference(_, n2, a2)) =>
      n1 == n2 && all_equivalent(a1, a2, r)
    (Tuple(_, []) | Unit(_), Tuple(_, []) | Unit(_)) => true
    (Tuple(_, x1), Tuple(_, x2)) => all_equivalent(x1, x2, r)
    (Record(_, f1), Record(_, f2)) => fields_equivalent(f1, f2, r)
    (ExtensibleRecord(c1, r1, f1), ExtensibleRecord(c2, r2, f2)) =>
      same_variable(r1, c1, r2, c2, r) && fields_equivalent(f1, f2, r)
    (Function(_, i1, o1), Function(_, i2, o2)) =>
      equivalent(i1, i2, r) && equivalent(o1, o2, r)
    _ => false
  }
}

///|
/// Pairs the variable `x` of `a` with the variable `y` of `b`, or checks the pair made before. `c1` and `c2` are
/// the attributes of the variables (of the record, for a row variable).
fn same_variable(
  x : @ir.Name,
  c1 : @ir.TypeAttributes,
  y : @ir.Name,
  c2 : @ir.TypeAttributes,
  r : Renaming,
) -> Bool {
  let x = x.to_canonical()
  let y = y.to_canonical()
  if r.classes && classes_of(x, c1) != classes_of(y, c2) {
    return false
  }
  let ab = r.ab
  let ba = r.ba
  match (ab.get(x), ba.get(y)) {
    (None, None) => {
      ab[x] = y
      ba[y] = x
      true
    }
    (Some(y2), Some(x2)) => y2 == y && x2 == x
    _ => false
  }
}

///|
fn all_equivalent(
  a : Array[@ir.Type],
  b : Array[@ir.Type],
  r : Renaming,
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i, x in a {
    if !equivalent(x, b[i], r) {
      return false
    }
  }
  true
}

///|
fn fields_equivalent(
  a : Map[@ir.Name, @ir.Type],
  b : Map[@ir.Name, @ir.Type],
  r : Renaming,
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  // The fields are compared in sorted order, so that the pairing of variables does not depend on map order.
  let names = a.keys().collect()
  names.sort_by((x, y) => x.to_canonical().compare(y.to_canonical()))
  for name in names {
    match (a.get(name), b.get(name)) {
      (Some(x), Some(y)) => if !equivalent(x, y, r) { return false }
      _ => return false
    }
  }
  true
}

///|
/// `t` with every alias reference expanded. A cyclic alias and an alias with the wrong number of arguments stay
/// as references.
fn Env::expand_ir(self : Env, t : @ir.Type) -> @ir.Type {
  match t {
    Reference(attrs, name, args) => {
      let args = args.map(a => self.expand_ir(a))
      let key = name.to_canonical()
      match self.types.get(key) {
        Some(Alias(params, body)) if !self.cyclic_aliases.contains(key) &&
          params.length() == args.length() => {
          let bound : Map[String, @ir.Type] = Map([])
          for i, p in params {
            bound[p] = args[i]
          }
          self.expand_ir(substitute(body, bound))
        }
        _ => Reference(attrs, name, args)
      }
    }
    Tuple(attrs, items) => Tuple(attrs, items.map(a => self.expand_ir(a)))
    Record(attrs, fields) =>
      Record(attrs, map_fields(fields, a => self.expand_ir(a)))
    ExtensibleRecord(attrs, row, fields) =>
      ExtensibleRecord(attrs, row, map_fields(fields, a => self.expand_ir(a)))
    Function(attrs, input, output) =>
      Function(attrs, self.expand_ir(input), self.expand_ir(output))
    Variable(_, _) | Unit(_) => t
  }
}

///|
/// `t` with each variable in `bound` replaced. A row variable is renamed when it is bound to a variable.
fn substitute(t : @ir.Type, bound : Map[String, @ir.Type]) -> @ir.Type {
  match t {
    Variable(_, name) =>
      match bound.get(name.to_canonical()) {
        Some(arg) => arg
        None => t
      }
    Reference(attrs, name, args) =>
      Reference(attrs, name, args.map(a => substitute(a, bound)))
    Tuple(attrs, items) => Tuple(attrs, items.map(a => substitute(a, bound)))
    Record(attrs, fields) =>
      Record(attrs, map_fields(fields, a => substitute(a, bound)))
    ExtensibleRecord(attrs, row, fields) => {
      let row = match bound.get(row.to_canonical()) {
        Some(Variable(_, other)) => other
        _ => row
      }
      ExtensibleRecord(
        attrs,
        row,
        map_fields(fields, a => substitute(a, bound)),
      )
    }
    Function(attrs, input, output) =>
      Function(attrs, substitute(input, bound), substitute(output, bound))
    Unit(_) => t
  }
}

///|
fn map_fields(
  fields : Map[@ir.Name, @ir.Type],
  f : (@ir.Type) -> @ir.Type,
) -> Map[@ir.Name, @ir.Type] {
  let out : Map[@ir.Name, @ir.Type] = Map([])
  for name, field in fields {
    out[name] = f(field)
  }
  out
}

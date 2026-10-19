///|
pub suberror TypeSubstitutionError {
  AttributeConflict
} derive(Eq, Debug)

///|
fn type_attributes(t : @ir.Type) -> @ir.TypeAttributes {
  match t {
    Variable(a, _)
    | Reference(a, _, _)
    | Tuple(a, _)
    | Union(a, _)
    | Record(a, _)
    | ExtensibleRecord(a, _, _)
    | Function(a, _, _)
    | Unit(a) => a
  }
}

///|
fn with_attributes(t : @ir.Type, a : @ir.TypeAttributes) -> @ir.Type {
  match t {
    Variable(_, n) => Variable(a, n)
    Reference(_, n, xs) => Reference(a, n, xs)
    Tuple(_, xs) => Tuple(a, xs)
    Union(_, xs) => Union(a, xs)
    Record(_, fs) => Record(a, fs)
    ExtensibleRecord(_, n, fs) => ExtensibleRecord(a, n, fs)
    Function(_, x, y) => Function(a, x, y)
    Unit(_) => Unit(a)
  }
}

///|
/// Conjoins representable attributes. Conflicts cannot be flattened into one IR node.
fn merge_attributes(
  a : @ir.TypeAttributes,
  b : @ir.TypeAttributes,
) -> @ir.TypeAttributes? {
  if a.source is Some(x) && b.source is Some(y) && x != y {
    return None
  }
  let constraints = a.constraints.copy()
  let extensions = a.extensions.copy()
  for k, v in b.constraints {
    if constraints.get(k) is Some(old) && old != v {
      return None
    }
    constraints[k] = v
  }
  for k, v in b.extensions {
    if extensions.get(k) is Some(old) && old != v {
      return None
    }
    extensions[k] = v
  }
  Some({
    source: if a.source is Some(_) {
      a.source
    } else {
      b.source
    },
    constraints,
    extensions,
  })
}

///|
/// Source positions are descriptive. Inference markers are consumed by conversion.
/// Every other extension remains an obligation; no runtime extension interpreter is claimed.
fn obligations(a : @ir.TypeAttributes) -> @ir.TypeAttributes {
  let extensions = a.extensions.copy()
  extensions.remove("morphir.inference")
  { ..a, source: None, extensions, }
}

///|
fn retained_attributes(t : @ir.Type) -> @ir.TypeAttributes {
  let a = type_attributes(t)
  let extensions = a.extensions.copy()
  extensions.remove("morphir.inference")
  let constraints = a.constraints.copy()
  if t is Variable(_, _) &&
    constraints.get(TYPECLASS) is Some(Text(c)) &&
    is_class(c) {
    constraints.remove(TYPECLASS)
  }
  { ..a, extensions, constraints, }
}

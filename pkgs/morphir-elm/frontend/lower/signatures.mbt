///|
/// The input names by morphir-elm's rule: the function arguments, then the
/// arguments of leading lambdas in the body (also inside any number of
/// parentheses), read left to right while each pattern is a plain variable.
/// When the value has an annotation, an input is taken only while the rest of
/// the annotation is a function type, looking through parentheses. A type alias
/// of a function type is not a function type here, so `f : Handler` with
/// `f x = x` has no inputs.
pub fn value_inputs(f : @ast.Function) -> Array[@ast.Node[String]] {
  inputs_of(f).0.map(input => input.0)
}

///|
/// The inputs with their annotations, and the rest of the annotation after the
/// last input. Both annotations are `None` when the value has no annotation.
fn inputs_of(
  f : @ast.Function,
) -> (
  Array[(@ast.Node[String], @ast.Node[@ast.TypeAnnotation]?)],
  @ast.Node[@ast.TypeAnnotation]?,
) {
  let inputs : Array[(@ast.Node[String], @ast.Node[@ast.TypeAnnotation]?)] = []
  let mut rest = f.signature.map(s => s.value.type_annotation)
  fn take(patterns : ArrayView[@ast.Node[@ast.Pattern]]) -> Bool {
    for p in patterns {
      guard p.value is VarPattern(n) else { return false }
      let name : @ast.Node[String] = { range: p.range, value: n, }
      match rest {
        None => inputs.push((name, None))
        Some(annotation) => {
          guard function_parts(annotation) is Some((arg, result)) else {
            return false
          }
          inputs.push((name, Some(arg)))
          rest = Some(result)
        }
      }
    }
    true
  }

  let fi = f.declaration.value
  if !take(fi.arguments) {
    return (inputs, rest)
  }
  let mut body = fi.expression
  while true {
    while body.value is ParenthesizedExpression(inner) {
      body = inner
    }
    guard body.value is LambdaExpression(lambda) else { break }
    if !take(lambda.args) {
      break
    }
    body = lambda.expression
  }
  (inputs, rest)
}

///|
/// The argument and the result of a function type, looking through parentheses
/// (a `Tupled` with one item). `None` for any other annotation.
fn function_parts(
  annotation : @ast.Node[@ast.TypeAnnotation],
) -> (@ast.Node[@ast.TypeAnnotation], @ast.Node[@ast.TypeAnnotation])? {
  let mut t = annotation
  while t.value is Tupled(items) && items.length() == 1 {
    t = items[0]
  }
  match t.value {
    FunctionTypeAnnotation(arg, result) => Some((arg, result))
    _ => None
  }
}

///|
fn placeholder(n : Int) -> @ir.Type {
  let name = @ir.Name::parse("t-" + n.to_string()) catch { _ => panic() }
  Variable(@ir.TypeAttributes::default().with_unknown(), name)
}

///|
pub fn lower_value_signature(
  scope : @resolve.Scope,
  f : @ast.Function,
) -> (String, @ir.ValueDefinition, String?) raise LowerError {
  let fi = f.declaration.value
  for p in fi.arguments {
    if p.value is RecordPattern(_) {
      raise LowerError(
        "elm.unsupported",
        "a record pattern as a function argument is not supported",
        Some(p.range),
      )
    }
  }
  let (found, rest) = inputs_of(f)
  let inputs : Array[(@ir.Name, @ir.Type)] = []
  for i, input in found {
    let (name, annotation) = input
    let t = match annotation {
      Some(a) => lower_type(scope, a, None)
      None => placeholder(i)
    }
    inputs.push((@mapping.elm_name(name.value), t))
  }
  let output = match rest {
    Some(a) => lower_type(scope, a, None)
    None => placeholder(found.length())
  }
  (
    fi.name.value,
    IncompleteBody(inputs, Some(output), Draft, None),
    doc_text(f.documentation),
  )
}

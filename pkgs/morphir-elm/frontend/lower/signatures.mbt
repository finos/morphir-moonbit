///|
/// The input names by morphir-elm's rule: the function arguments, then the
/// arguments of leading lambdas in the body (also inside any number of
/// parentheses), read left to right while each pattern is a plain variable.
pub fn value_inputs(
  f : @ast.FunctionImplementation,
) -> Array[@ast.Node[String]] {
  let names : Array[@ast.Node[String]] = []
  fn take(patterns : ArrayView[@ast.Node[@ast.Pattern]]) -> Bool {
    for p in patterns {
      guard p.value is VarPattern(n) else { return false }
      names.push({ range: p.range, value: n, })
    }
    true
  }

  if !take(f.arguments) {
    return names
  }
  let mut body = f.expression
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
  names
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
  let names = value_inputs(fi)
  let inputs : Array[(@ir.Name, @ir.Type)] = []
  let output = match f.signature {
    None => {
      for i, n in names {
        inputs.push((@mapping.elm_name(n.value), placeholder(i)))
      }
      placeholder(names.length())
    }
    Some(sig) => {
      let mut rest = sig.value.type_annotation
      for n in names {
        while rest.value is Tupled(items) && items.length() == 1 {
          rest = items[0]
        }
        guard rest.value is FunctionTypeAnnotation(arg, result) else {
          raise LowerError(
            "elm.signature_arity",
            "the annotation of \{fi.name.value} has fewer arguments than its definition",
            Some(sig.range),
          )
        }
        inputs.push((@mapping.elm_name(n.value), lower_type(scope, arg, None)))
        rest = result
      }
      lower_type(scope, rest, None)
    }
  }
  (
    fi.name.value,
    IncompleteBody(inputs, Some(output), Draft, None),
    doc_text(f.documentation),
  )
}

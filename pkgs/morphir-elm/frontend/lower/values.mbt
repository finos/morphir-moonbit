///|
/// The default value attributes with the source location of `range`.
pub fn value_attributes(range : @ast.Range) -> @ir.ValueAttributes {
  {
    ..@ir.ValueAttributes::default(),
    source: Some({
      start_line: range.start.row,
      start_column: range.start.column,
      end_line: range.end.row,
      end_column: range.end.column,
    }),
  }
}

///|
/// The state of lowering one top-level declaration: the scope, the local names
/// (one frame per binding form) and the next placeholder number, shared by the
/// declaration and its lets.
priv struct Lowering {
  scope : @resolve.Scope
  locals : Array[Map[String, Bool]]
  placeholders : Ref[Int]
}

///|
fn Lowering::is_local(self : Lowering, name : String) -> Bool {
  self.locals.iter().any(frame => frame.contains(name))
}

///|
/// A fresh placeholder type: `t-0`, `t-1`, … in the order of the declaration.
fn Lowering::placeholder(self : Lowering) -> @ir.Type {
  let n = self.placeholders.val
  self.placeholders.val = n + 1
  placeholder(n)
}

///|
fn starts_upper(name : String) -> Bool {
  match name.get_char(0) {
    Some(c) => c >= 'A' && c <= 'Z'
    None => false
  }
}

///|
/// One top-level value as morphir-elm's `make` writes it: the Elm name and an
/// `ExpressionBody`. The declaration arguments and the arguments of the leading
/// lambdas of the body form one list. Inputs are lifted from the front while the
/// pattern is a variable and the rest of the annotation is a function type (an
/// unannotated value lifts every leading variable, each with a fresh
/// placeholder type). The other arguments stay in the body as `Lambda` nodes.
pub fn lower_value_definition(
  scope : @resolve.Scope,
  f : @ast.Function,
) -> (String, @ir.ValueDefinition) raise LowerError {
  let lowering : Lowering = { scope, locals: [], placeholders: Ref(0), }
  let declaration = f.declaration.value
  let (arguments, body) = arguments_and_body(declaration)
  let frame : Map[String, Bool] = Map([])
  let patterns = lowering.patterns(arguments[:], frame)
  let inputs : Array[(@ir.Name, @ir.Type)] = []
  let mut rest = f.signature.map(s => s.value.type_annotation)
  let mut lifted = 0
  while lifted < arguments.length() {
    guard arguments[lifted].value is VarPattern(name) else { break }
    match rest {
      None => inputs.push((@mapping.elm_name(name), lowering.placeholder()))
      Some(annotation) => {
        guard function_parts(annotation) is Some((argument, result)) else {
          break
        }
        inputs.push(
          (@mapping.elm_name(name), lower_type(scope, argument, None)),
        )
        rest = Some(result)
      }
    }
    lifted += 1
  }
  let output = match rest {
    None => lowering.placeholder()
    Some(annotation) => lower_type(scope, annotation, None)
  }
  lowering.locals.push(frame)
  let mut value = lowering.expression(body)
  ignore(lowering.locals.pop())
  for i = arguments.length() - 1; i >= lifted; i = i - 1 {
    value = Lambda(value_attributes(arguments[i].range), patterns[i], value)
  }
  (declaration.name.value, ExpressionBody(inputs, output, value))
}

///|
/// The declaration arguments, then the arguments of each leading lambda of the
/// body (also inside any number of parentheses), and the body after the last of
/// them.
fn arguments_and_body(
  declaration : @ast.FunctionImplementation,
) -> (Array[@ast.Node[@ast.Pattern]], @ast.Node[@ast.Expression]) {
  let arguments = declaration.arguments.to_owned()
  let mut body = declaration.expression
  while true {
    let mut inner = body
    while inner.value is ParenthesizedExpression(e) {
      inner = e
    }
    guard inner.value is LambdaExpression(lambda) else { break }
    arguments.append(lambda.args.to_owned())
    body = lambda.expression
  }
  (arguments, body)
}

///|
/// One expression. The kinds that this function does not lower yet are
/// `elm.unsupported`.
fn Lowering::expression(
  self : Lowering,
  node : @ast.Node[@ast.Expression],
) -> @ir.Value raise LowerError {
  let a = value_attributes(node.range)
  let not_yet = (kind : String) => {
    LowerError(
      "elm.unsupported",
      "\{kind} is not lowered yet",
      Some(node.range),
    )
  }
  match node.value {
    UnitExpr => Unit(a)
    FunctionOrValue(qualifier, name) => {
      let resolved = self.scope.resolve_value(qualifier.to_owned(), name, n => {
        self.is_local(n)
      }) catch {
        @resolve.ResolveError(code, message) =>
          raise LowerError(code, message, Some(node.range))
      }
      match resolved {
        Local(n) => Variable(a, @mapping.elm_name(n))
        BoolLiteral(b) => Literal(a, BoolLiteral(b))
        Global(fq) if starts_upper(name) => Constructor(a, fq)
        Global(fq) => Reference(a, fq)
      }
    }
    ParenthesizedExpression(inner) => self.expression(inner)
    LambdaExpression(lambda) => {
      let frame : Map[String, Bool] = Map([])
      let patterns = self.patterns(lambda.args, frame)
      self.locals.push(frame)
      let mut value = self.expression(lambda.expression)
      ignore(self.locals.pop())
      for i = patterns.length() - 1; i >= 0; i = i - 1 {
        value = Lambda(a, patterns[i], value)
      }
      value
    }
    Application(_) => raise not_yet("a function application")
    OperatorApplication(_, _, _, _) => raise not_yet("an operator application")
    IfBlock(_, _, _) => raise not_yet("an if expression")
    PrefixOperator(_) => raise not_yet("an operator function")
    Operator(_) => raise not_yet("an operator")
    Integer(_) => raise not_yet("an integer literal")
    Hex(_) => raise not_yet("a hexadecimal literal")
    Floatable(_) => raise not_yet("a float literal")
    Negation(_) => raise not_yet("a negation")
    Literal(_) => raise not_yet("a string literal")
    CharLiteral(_) => raise not_yet("a char literal")
    TupledExpression(_) => raise not_yet("a tuple")
    LetExpression(_) => raise not_yet("a let expression")
    CaseExpression(_) => raise not_yet("a case expression")
    RecordExpr(_) => raise not_yet("a record")
    ListExpr(_) => raise not_yet("a list")
    RecordAccess(_, _) => raise not_yet("a record access")
    RecordAccessFunction(_) => raise not_yet("a record access function")
    RecordUpdateExpression(_, _) => raise not_yet("a record update")
    GLSLExpression(_) => raise not_yet("a GLSL block")
  }
}

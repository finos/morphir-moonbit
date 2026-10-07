///|
priv struct LibraryResolver {
  functions : Map[String, Int]
  cancelled : () -> Bool
  mut binding : Int
}

///|
fn LibraryResolver::expression(
  self : LibraryResolver,
  expr : LibraryExpr,
  scope : Map[String, @ir.Name],
) -> ResolvedExpr raise {
  library_poll(self.cancelled)
  match expr {
    Boolean(value, source) => Boolean(value, source)
    Identifier(text, source) =>
      match scope.get(text) {
        Some(name) => Variable(name, source)
        None => {
          library_error(
            if self.functions.contains(text) {
              "function_value"
            } else {
              "unknown_reference"
            },
            "Expected a bound Boolean value: " + text,
            Some(source),
          )
          abort("unreachable")
        }
      }
    Negation(value, source) => Negation(self.expression(value, scope), source)
    Binary(op, lhs, rhs, source) =>
      Binary(
        op,
        self.expression(lhs, scope),
        self.expression(rhs, scope),
        source,
      )
    Conditional(cond, yes, no, source) =>
      Conditional(
        self.expression(cond, scope),
        self.expression(yes, scope),
        self.expression(no, scope),
        source,
      )
    Binding(text, binder_source, value, body, source) => {
      // The initializer sees the preceding scope, including an older shadowed name.
      let value = self.expression(value, scope)
      let name = @ir.Name::from_words([
        "frontend",
        "binding",
        self.binding.to_string(),
      ])
      self.binding += 1
      let nested = scope.copy()
      nested[text] = name
      Binding(
        name,
        text,
        binder_source,
        value,
        self.expression(body, nested),
        source,
      )
    }
    Call(text, arguments, source) => {
      if scope.contains(text) {
        library_error(
          "not_callable",
          "A Boolean binding shadows the call target: " + text,
          Some(source),
        )
      }
      guard self.functions.get(text) is Some(index) else {
        library_error(
          "unknown_function",
          "Unknown library function: " + text,
          Some(source),
        )
        abort("unreachable")
      }
      Call(index, arguments.map(arg => self.expression(arg, scope)), source)
    }
  }
}

///|
fn library_resolve(
  functions : Array[LibraryFunction],
  cancelled : () -> Bool,
) -> Array[ResolvedFunction] raise {
  let indices : Map[String, Int] = Map([])
  for i = 0; i < functions.length(); i = i + 1 {
    indices[functions[i].name] = i
  }
  let resolver = LibraryResolver::{ functions: indices, cancelled, binding: 0, }
  let resolved = []
  for declaration in functions {
    library_poll(cancelled)
    let scope : Map[String, @ir.Name] = Map([])
    let parameters = declaration.parameters.map(p => source_name(p.0))
    for i = 0; i < parameters.length(); i = i + 1 {
      scope[declaration.parameters[i].0] = parameters[i]
    }
    resolved.push({
      declaration: {
        name: declaration.name,
        public: declaration.public,
        parameters: declaration.parameters,
        source: declaration.source,
        body_source: declaration.body_source,
      },
      parameters,
      body: resolver.expression(declaration.body, scope),
    })
  }
  resolved
}

///|
fn library_origin(name : String, source : @ir.SourceLocation) -> @ion.IonValue {
  ion_record([
    ("name", @ion.IonValue::string(name)),
    ("coordinate_profile", @ion.IonValue::string("moonbit-parser-position-v1")),
    ("start_line", @ion.IonValue::int(source.start_line)),
    ("start_column", @ion.IonValue::int(source.start_column)),
    ("end_line", @ion.IonValue::int(source.end_line)),
    ("end_column", @ion.IonValue::int(source.end_column)),
  ])
}

///|
fn library_attributes(
  source : @ir.SourceLocation,
  ty : @ir.Type,
) -> @ir.ValueAttributes {
  { source: Some(source), inferred_type: Some(ty), extensions: Map([]), }
}

///|
fn library_arrow(boolean : @ir.Type, arity : Int) -> @ir.Type {
  let mut result = boolean
  for i = 0; i < arity; i = i + 1 {
    result = @ir.Type::Function(@ir.TypeAttributes::default(), boolean, result)
  }
  result
}

///|
priv struct LibraryLowerer {
  functions : Array[ResolvedFunction]
  entries : Array[@ir.FQName]
  boolean : @ir.Type
  cancelled : () -> Bool
  origins : Array[@ion.IonValue]
  mut temporary : Int
}

///|
fn LibraryLowerer::literal(
  self : LibraryLowerer,
  value : Bool,
  source : @ir.SourceLocation,
) -> @ir.Value {
  @ir.Value::Literal(
    library_attributes(source, self.boolean),
    @ir.Literal::BoolLiteral(value),
  )
}

///|
fn LibraryLowerer::negate(
  self : LibraryLowerer,
  value : @ir.Value,
  source : @ir.SourceLocation,
) -> @ir.Value {
  @ir.Value::IfThenElse(
    library_attributes(source, self.boolean),
    value,
    self.literal(false, source),
    self.literal(true, source),
  )
}

///|
fn LibraryLowerer::fresh(self : LibraryLowerer) -> @ir.Name {
  let name = @ir.Name::from_words([
    "frontend",
    "temporary",
    self.temporary.to_string(),
  ])
  self.temporary += 1
  name
}

///|
fn LibraryLowerer::expression(
  self : LibraryLowerer,
  expr : ResolvedExpr,
) -> @ir.Value raise {
  library_poll(self.cancelled)
  match expr {
    Boolean(value, source) => self.literal(value, source)
    Variable(name, source) =>
      @ir.Value::Variable(library_attributes(source, self.boolean), name)
    Negation(value, source) => self.negate(self.expression(value), source)
    Conditional(cond, yes, no, source) =>
      @ir.Value::IfThenElse(
        library_attributes(source, self.boolean),
        self.expression(cond),
        self.expression(yes),
        self.expression(no),
      )
    Binding(name, text, binder_source, value, body, source) => {
      self.origins.push(
        ion_record([
          ("binding", library_origin(text, binder_source)),
          ("identity", @ion.IonValue::string(name.to_canonical())),
        ]),
      )
      @ir.Value::LetDefinition(
        library_attributes(source, self.boolean),
        name,
        @ir.ValueDefinition::ExpressionBody(
          [],
          self.boolean,
          self.expression(value),
        ),
        self.expression(body),
      )
    }
    Call(index, arguments, source) => {
      self.origins.push(
        ion_record([
          (
            "call",
            library_origin(self.functions[index].declaration.name, source),
          ),
        ]),
      )
      let mut value = @ir.Value::Reference(
        library_attributes(
          source,
          library_arrow(self.boolean, arguments.length()),
        ),
        self.entries[index],
      )
      for i = 0; i < arguments.length(); i = i + 1 {
        value = @ir.Value::Apply(
          library_attributes(
            source,
            library_arrow(self.boolean, arguments.length() - i - 1),
          ),
          value,
          self.expression(arguments[i]),
        )
      }
      value
    }
    Binary(op, lhs, rhs, source) => {
      let attrs = library_attributes(source, self.boolean)
      let left = self.expression(lhs)
      let right = self.expression(rhs)
      match op {
        "&&" =>
          @ir.Value::IfThenElse(attrs, left, right, self.literal(false, source))
        "||" =>
          @ir.Value::IfThenElse(attrs, left, self.literal(true, source), right)
        _ => {
          // Strict operand bindings preserve order and avoid duplicating call trees.
          let l = self.fresh()
          let r = self.fresh()
          let lv = @ir.Value::Variable(attrs, l)
          let rv = @ir.Value::Variable(attrs, r)
          let comparison = if op == "!=" {
            @ir.Value::IfThenElse(attrs, lv, self.negate(rv, source), rv)
          } else {
            @ir.Value::IfThenElse(attrs, lv, rv, self.negate(rv, source))
          }
          @ir.Value::LetDefinition(
            attrs,
            l,
            @ir.ValueDefinition::ExpressionBody([], self.boolean, left),
            @ir.Value::LetDefinition(
              attrs,
              r,
              @ir.ValueDefinition::ExpressionBody([], self.boolean, right),
              comparison,
            ),
          )
        }
      }
    }
  }
}

///|
fn library_lower(
  input : Input,
  package_name : @ir.Path,
  module_name : @ir.Path,
  checked : CheckedLibrary,
  cancelled : () -> Bool,
) -> LibraryOutput raise {
  let boolean = boolean_type()
  let entries = checked.functions.map(f => {
    @ir.FQName::parse(
      package_name.to_canonical() +
      ":" +
      module_name.to_canonical() +
      "#" +
      source_name(f.declaration.name).to_canonical(),
    )
  })
  let lowerer = LibraryLowerer::{
    functions: checked.functions,
    entries,
    boolean,
    cancelled,
    origins: [],
    temporary: 0,
  }
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map([])
  let metadata = []
  let public_entries = []
  for i = 0; i < checked.functions.length(); i = i + 1 {
    library_poll(cancelled)
    let function = checked.functions[i]
    let declaration = function.declaration
    lowerer.origins.clear()
    let body = lowerer.expression(function.body)
    values[source_name(declaration.name)] = {
      access: if declaration.public {
        @ir.Access::Public
      } else {
        @ir.Access::Private
      },
      value: {
        doc: None,
        value: @ir.ValueDefinition::ExpressionBody(
          function.parameters.map(name => (name, boolean)),
          boolean,
          body,
        ),
      },
    }
    if declaration.public {
      public_entries.push(entries[i])
    }
    let id = "value:" + entries[i].to_canonical()
    metadata.push({
      node_id: id,
      data: ion_record([
        ("declaration", library_origin(declaration.name, declaration.source)),
        (
          "parameters",
          @ion.IonValue::list(
            declaration.parameters.map(p => library_origin(p.0, p.1)),
          ),
        ),
      ]),
    })
    metadata.push({
      node_id: id + "/body",
      data: ion_record([
        ("body", library_origin(declaration.name, declaration.body_source)),
        ("nodes", @ion.IonValue::list(lowerer.origins.copy())),
      ]),
    })
  }
  public_entries.sort_by(fn(a, b) { a.to_canonical().compare(b.to_canonical()) })
  let module_def : @ir.ModuleDefinition = { types: Map([]), doc: None, values, }
  let ir = @ir.IRFile::new(
    @ir.Distribution::Library(package_name, Map([]), {
      modules: Map::from_array([
        (module_name, { access: @ir.Access::Public, value: module_def, }),
      ]),
    }),
  )
  {
    unit_id: input.unit_id,
    ir,
    entries: public_entries,
    metadata,
    annotations: [@ion.SymbolToken::new("morphir_pipeline")],
    provenance: [
      ion_record([
        ("language", @ion.IonValue::string("moonbit")),
        ("profile", @ion.IonValue::string(LIBRARY_PROFILE)),
        ("parser_version", @ion.IonValue::string(PARSER_VERSION)),
        ("unit_id", @ion.IonValue::string(input.unit_id)),
      ]).with_annotation(@ion.SymbolToken::new("morphir_moonbit_frontend")),
    ],
  }
}

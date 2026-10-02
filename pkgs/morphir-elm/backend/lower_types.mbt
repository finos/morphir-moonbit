///|
fn check_tuple_arity(count : Int, at : String) -> Unit raise ElmGenerationError {
  if count < 2 || count > 3 {
    refuse(
      "tuple_arity",
      at,
      "Elm tuples have 2 or 3 elements, not " + count.to_string(),
    )
  }
}

///|
fn lower_type(
  ctx : Ctx,
  t : @ir.Type,
  at : String,
) -> @ast.TypeAnnotation raise ElmGenerationError {
  match t {
    Variable(attributes, name) =>
      GenericType(type_variable_name(name, constraint_of(attributes, at)))
    Reference(_, name, args) =>
      match ctx.resolve(name, TypeName) {
        Qualified(qualifier, local) =>
          Typed(
            node((qualifier[:], local)),
            args.map(a => node(lower_type(ctx, a, at)))[:],
          )
        Op(op) =>
          refuse(
            "invalid_mapping",
            at,
            "type " + name.to_canonical() + " maps to operator " + op,
          )
      }
    Tuple(_, items) => {
      check_tuple_arity(items.length(), at)
      Tupled(items.map(i => node(lower_type(ctx, i, at)))[:])
    }
    Record(_, fields) => Record(record_fields(ctx, fields, at))
    ExtensibleRecord(_, variable, fields) =>
      GenericRecord(
        node(value_name(variable)),
        node(record_fields(ctx, fields, at)),
      )
    Function(_, input, output) =>
      FunctionTypeAnnotation(
        node(lower_type(ctx, input, at)),
        node(lower_type(ctx, output, at)),
      )
    Unit(_) => Unit
  }
}

///|
fn record_fields(
  ctx : Ctx,
  fields : Map[@ir.Name, @ir.Type],
  at : String,
) -> ArrayView[@ast.Node[@ast.RecordField]] raise ElmGenerationError {
  let result = []
  for name, field_type in fields {
    result.push(
      node(@ast.RecordField::{
        name: node(value_name(name)),
        type_annotation: node(lower_type(ctx, field_type, at)),
      }),
    )
  }
  result[:]
}

///|
fn constructors_of(
  ctx : Ctx,
  constructors : @ir.Constructors,
  at : String,
) -> ArrayView[@ast.Node[@ast.ValueConstructor]] raise ElmGenerationError {
  let result = []
  for name, args in constructors {
    result.push(
      node(@ast.ValueConstructor::{
        name: node(type_name(name)),
        arguments: args.map(arg => node(lower_type(ctx, arg.1, at)))[:],
      }),
    )
  }
  result[:]
}

///|
fn generics(params : Array[@ir.Name]) -> ArrayView[@ast.Node[String]] {
  params.map(p => node(value_name(p)))[:]
}

///|
fn custom_type(
  ctx : Ctx,
  name : @ir.Name,
  doc : String?,
  params : Array[@ir.Name],
  constructors : @ir.Constructors,
  at : String,
) -> @ast.Declaration raise ElmGenerationError {
  if constructors.is_empty() {
    refuse("placeholder", at, "a custom type needs at least one constructor")
  }
  CustomTypeDeclaration({
    documentation: doc_comment(doc, []),
    name: node(type_name(name)),
    generics: generics(params),
    constructors: constructors_of(ctx, constructors, at),
  })
}

///|
fn alias(
  ctx : Ctx,
  name : @ir.Name,
  doc : String?,
  params : Array[@ir.Name],
  body : @ir.Type,
  at : String,
) -> @ast.Declaration raise ElmGenerationError {
  AliasDeclaration({
    documentation: doc_comment(doc, []),
    name: node(type_name(name)),
    generics: generics(params),
    type_annotation: node(lower_type(ctx, body, at)),
  })
}

///|
fn lower_type_definition(
  ctx : Ctx,
  name : @ir.Name,
  doc : String?,
  definition : @ir.TypeDefinition,
  at : String,
) -> (@ast.Declaration, @ast.TopLevelExpose?) raise ElmGenerationError {
  match definition {
    TypeAliasDefinition(params, body) =>
      (
        alias(ctx, name, doc, params, body, at),
        Some(TypeOrAliasExpose(type_name(name))),
      )
    CustomTypeDefinition(params, constructors) => {
      let declaration = custom_type(
        ctx,
        name,
        doc,
        params,
        constructors.value,
        at,
      )
      let expose : @ast.TopLevelExpose = if constructors.access is Public {
        TypeExpose({ name: type_name(name), open: Some(zero), })
      } else {
        TypeOrAliasExpose(type_name(name))
      }
      (declaration, Some(expose))
    }
    IncompleteTypeDefinition(_, _, _) =>
      refuse("placeholder", at, "an incomplete type definition has no Elm form")
  }
}

///|
fn lower_type_specification(
  ctx : Ctx,
  name : @ir.Name,
  doc : String?,
  spec : @ir.TypeSpecification,
  at : String,
) -> (@ast.Declaration, @ast.TopLevelExpose) raise ElmGenerationError {
  match spec.body {
    TypeAliasSpecification(params, body) =>
      (
        alias(ctx, name, doc, params, body, at),
        TypeOrAliasExpose(type_name(name)),
      )
    OpaqueTypeSpecification(params) => {
      // A hidden constructor keeps the type opaque to other modules.
      let hidden = @ir.Name::parse(name.to_canonical() + "-opaque") catch {
        _ => refuse("print", at, "cannot name the opaque constructor")
      }
      let declaration = custom_type(
        ctx,
        name,
        doc,
        params,
        Map::from_array([(hidden, [])]),
        at,
      )
      (declaration, TypeOrAliasExpose(type_name(name)))
    }
    CustomTypeSpecification(params, constructors) =>
      (
        custom_type(ctx, name, doc, params, constructors, at),
        TypeExpose({ name: type_name(name), open: Some(zero), }),
      )
    DerivedTypeSpecification(_, _) =>
      refuse("derived_type", at, "derived types are not supported yet")
  }
}

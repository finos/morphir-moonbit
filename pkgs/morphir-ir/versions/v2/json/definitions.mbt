///|
pub fn[TA] read_constructors(
  json : Json,
  ta : (Json) -> TA raise,
) -> @model.Constructors[TA] raise {
  @wire.read_map(json, @wire.read_name, fn(args) raise {
    @wire.array(args).map(arg => {
      let a = @wire.tuple(arg, 2)
      (@wire.read_name(a[0]), read_type(a[1], ta))
    })
  })
}

///|
pub fn[TA] write_constructors(
  value : @model.Constructors[TA],
  ta : (TA) -> Json raise,
) -> Json raise {
  @wire.write_map(
    value,
    fn(key) raise { @wire.write_legacy_name(key) },
    fn(args) raise {
      Json::array(
        args.map(arg => {
          Json::array([@wire.write_legacy_name(arg.0), write_type(arg.1, ta)])
        }),
      )
    },
    legacy=true,
  )
}

///|
pub fn[T] read_access(
  json : Json,
  decode : (Json) -> T raise,
) -> @model.AccessControlled[T] raise {
  @wire.fields(json, ["access", "value"])
  let (access, value) = (
    @wire.string(@wire.field(json, "access")),
    @wire.field(json, "value"),
  )
  let access = match access {
    "Public" => @model.Access::Public
    "Private" => @model.Access::Private
    _ => raise @wire.Invalid("invalid_access", access)
  }
  { access, value: decode(value), }
}

///|
pub fn[T] write_access(
  value : @model.AccessControlled[T],
  encode : (T) -> Json raise,
) -> Json raise {
  let access = match value.access {
    Public => "Public"
    Private => "Private"
  }
  @wire.obj([("access", @wire.text(access)), ("value", encode(value.value))])
}

///|
pub fn[T] read_documented(
  json : Json,
  decode : (Json) -> T raise,
) -> @model.Documented[T] raise {
  match json {
    Object(fields) if fields.contains("doc") && fields.contains("value") => {
      @wire.fields(json, ["doc", "value"])
      {
        doc: @wire.string(@wire.field(json, "doc")),
        value: decode(@wire.field(json, "value")),
      }
    }
    _ => { doc: "", value: decode(json), }
  }
}

///|
pub fn[T] write_documented(
  value : @model.Documented[T],
  encode : (T) -> Json raise,
) -> Json raise {
  @wire.obj([("doc", @wire.text(value.doc)), ("value", encode(value.value))])
}

///|
pub fn[TA] read_type_definition(
  json : Json,
  ta : (Json) -> TA raise,
) -> @model.TypeDefinition[TA] raise {
  let a = @wire.tuple(json, 3)
  let params = @wire.array(a[1]).map(@wire.read_name)
  match @wire.string(a[0]) {
    "TypeAliasDefinition" =>
      @model.TypeAliasDefinition(params, read_type(a[2], ta))
    "CustomTypeDefinition" =>
      @model.CustomTypeDefinition(
        params,
        read_access(a[2], fn(c) raise { read_constructors(c, ta) }),
      )
    tag => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn[TA] write_type_definition(
  value : @model.TypeDefinition[TA],
  ta : (TA) -> Json raise,
) -> Json raise {
  match value {
    TypeAliasDefinition(params, body) =>
      Json::array([
        @wire.text("TypeAliasDefinition"),
        Json::array(params.map(@wire.write_legacy_name)),
        write_type(body, ta),
      ])
    CustomTypeDefinition(params, ctors) =>
      Json::array([
        @wire.text("CustomTypeDefinition"),
        Json::array(params.map(@wire.write_legacy_name)),
        write_access(ctors, fn(c) raise { write_constructors(c, ta) }),
      ])
  }
}

///|
pub fn[TA] read_type_specification(
  json : Json,
  ta : (Json) -> TA raise,
) -> @model.TypeSpecification[TA] raise {
  let a = @wire.array(json)
  if a.length() < 2 {
    raise @wire.Invalid("invalid_arity", "Type specification")
  }
  let params = @wire.array(a[1]).map(@wire.read_name)
  match @wire.string(a[0]) {
    "TypeAliasSpecification" => {
      ignore(@wire.tuple(json, 3))
      @model.TypeAliasSpecification(params, read_type(a[2], ta))
    }
    "OpaqueTypeSpecification" => {
      ignore(@wire.tuple(json, 2))
      @model.OpaqueTypeSpecification(params)
    }
    "CustomTypeSpecification" => {
      ignore(@wire.tuple(json, 3))
      @model.CustomTypeSpecification(params, read_constructors(a[2], ta))
    }
    "DerivedTypeSpecification" => {
      ignore(@wire.tuple(json, 3))
      @wire.fields(a[2], ["baseType", "fromBaseType", "toBaseType"])
      @model.DerivedTypeSpecification(params, {
        base_type: read_type(@wire.field(a[2], "baseType"), ta),
        from_base_type: @wire.read_fqname(@wire.field(a[2], "fromBaseType")),
        to_base_type: @wire.read_fqname(@wire.field(a[2], "toBaseType")),
      })
    }
    tag => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn[TA] write_type_specification(
  value : @model.TypeSpecification[TA],
  ta : (TA) -> Json raise,
) -> Json raise {
  match value {
    TypeAliasSpecification(params, body) =>
      Json::array([
        @wire.text("TypeAliasSpecification"),
        Json::array(params.map(@wire.write_legacy_name)),
        write_type(body, ta),
      ])
    OpaqueTypeSpecification(params) =>
      Json::array([
        @wire.text("OpaqueTypeSpecification"),
        Json::array(params.map(@wire.write_legacy_name)),
      ])
    CustomTypeSpecification(params, ctors) =>
      Json::array([
        @wire.text("CustomTypeSpecification"),
        Json::array(params.map(@wire.write_legacy_name)),
        write_constructors(ctors, ta),
      ])
    DerivedTypeSpecification(params, details) =>
      Json::array([
        @wire.text("DerivedTypeSpecification"),
        Json::array(params.map(@wire.write_legacy_name)),
        @wire.obj([
          ("baseType", write_type(details.base_type, ta)),
          ("fromBaseType", @wire.write_legacy_fqname(details.from_base_type)),
          ("toBaseType", @wire.write_legacy_fqname(details.to_base_type)),
        ]),
      ])
  }
}

///|
pub fn[TA] read_value_specification(
  json : Json,
  ta : (Json) -> TA raise,
) -> @model.ValueSpecification[TA] raise {
  @wire.fields(json, ["inputs", "output"])
  {
    inputs: @wire.array(@wire.field(json, "inputs")).map(input => {
      let a = @wire.tuple(input, 2)
      (@wire.read_name(a[0]), read_type(a[1], ta))
    }),
    output: read_type(@wire.field(json, "output"), ta),
  }
}

///|
pub fn[TA] write_value_specification(
  value : @model.ValueSpecification[TA],
  ta : (TA) -> Json raise,
) -> Json raise {
  @wire.obj([
    (
      "inputs",
      Json::array(
        value.inputs.map(input => {
          Json::array([
            @wire.write_legacy_name(input.0),
            write_type(input.1, ta),
          ])
        }),
      ),
    ),
    ("output", write_type(value.output, ta)),
  ])
}

///|
pub fn[TA, VA] read_value_definition(
  json : Json,
  ta : (Json) -> TA raise,
  va : (Json) -> VA raise,
) -> @model.ValueDefinition[TA, VA] raise {
  @wire.fields(json, ["inputTypes", "outputType", "body"])
  {
    input_types: @wire.array(@wire.field(json, "inputTypes")).map(input => {
      let a = @wire.tuple(input, 3)
      (@wire.read_name(a[0]), va(a[1]), read_type(a[2], ta))
    }),
    output_type: read_type(@wire.field(json, "outputType"), ta),
    body: read_value(@wire.field(json, "body"), ta, va),
  }
}

///|
pub fn[TA, VA] write_value_definition(
  value : @model.ValueDefinition[TA, VA],
  ta : (TA) -> Json raise,
  va : (VA) -> Json raise,
) -> Json raise {
  @wire.obj([
    (
      "inputTypes",
      Json::array(
        value.input_types.map(input => {
          Json::array([
            @wire.write_legacy_name(input.0),
            va(input.1),
            write_type(input.2, ta),
          ])
        }),
      ),
    ),
    ("outputType", write_type(value.output_type, ta)),
    ("body", write_value(value.body, ta, va)),
  ])
}

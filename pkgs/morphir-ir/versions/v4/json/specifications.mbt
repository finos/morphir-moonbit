///|
pub fn read_annotation(json : Json) -> @model.Annotation raise {
  match json {
    String(text) => {
      let parts = text.split(":").map(part => part.to_owned()).collect()
      if parts.length() < 2 {
        raise @wire.Invalid("invalid_name", text)
      }
      let name = @model.FQName::parse(parts[0] + ":" + parts[1])
      let text = if parts.length() > 2 {
        Some(parts[2:].iter().collect().join(":"))
      } else {
        None
      }
      @model.Compact(name, text)
    }
    _ => {
      @wire.fields(json, ["name", "arguments"])
      @model.Structured(
        @wire.read_fqname(@wire.field(json, "name")),
        @wire.array(optional_array(json, "arguments")).map(argument => {
          match argument {
            Object(fields) if fields.contains("name") &&
              fields.contains("value") => {
              @wire.fields(argument, ["name", "value"])
              @model.Named(
                @wire.read_name(@wire.field(argument, "name")),
                read_value(@wire.field(argument, "value")),
              )
            }
            _ => @model.Positional(read_value(argument))
          }
        }),
      )
    }
  }
}

///|
pub fn write_annotation(annotation : @model.Annotation) -> Json raise {
  match annotation {
    Compact(name, text) => {
      ignore(@wire.write_fqname(name))
      @wire.text(
        name.to_canonical() +
        (match text {
          None => ""
          Some(text) => ":" + text
        }),
      )
    }
    Structured(name, arguments) => {
      let fields = [("name", @wire.write_fqname(name))]
      if !arguments.is_empty() {
        fields.push(
          (
            "arguments",
            Json::array(
              arguments.map(argument => {
                match argument {
                  Positional(value) => write_value(value)
                  Named(name, value) =>
                    @wire.obj([
                      ("name", @wire.write_name(name)),
                      ("value", write_value(value)),
                    ])
                }
              }),
            ),
          ),
        )
      }
      @wire.obj(fields)
    }
  }
}

///|
fn read_annotations(json : Json) -> Array[@model.Annotation] raise {
  @wire.array(optional_array(json, "annotations")).map(read_annotation)
}

///|
fn put_annotations(
  fields : Array[(String, Json)],
  annotations : Array[@model.Annotation],
) -> Unit raise {
  if !annotations.is_empty() {
    fields.push(("annotations", Json::array(annotations.map(write_annotation))))
  }
}

///|
fn read_params(payload : Json) -> Array[@model.Name] raise {
  @wire.array(optional_array(payload, "typeParams")).map(@wire.read_name)
}

///|
fn read_constructors(json : Json) -> @model.Constructors raise {
  @wire.read_map(json, @wire.read_name, read_inputs)
}

///|
fn write_constructors(constructors : @model.Constructors) -> Json raise {
  // Constructor parameters have a pair-array wire form in v4.
  @wire.write_map(constructors, name_key, fn(parameters) raise {
    Json::array(
      parameters.map(parameter => {
        Json::array([name_key(parameter.0), write_type(parameter.1)])
      }),
    )
  })
}

///|
pub fn read_type_specification(json : Json) -> @model.TypeSpecification raise {
  let (tag, payload) = match json {
    Array(items) => {
      if items.length() < 2 {
        raise @wire.Invalid("invalid_arity", "Type specification")
      }
      let tag = @wire.string(items[0])
      let fields = [("typeParams", items[1])]
      if tag == "OpaqueTypeSpecification" {
        ignore(@wire.tuple(json, 2))
      } else {
        ignore(@wire.tuple(json, 3))
        match tag {
          "TypeAliasSpecification" => fields.push(("typeExp", items[2]))
          "CustomTypeSpecification" => fields.push(("constructors", items[2]))
          "DerivedTypeSpecification" =>
            fields.append(@wire.object(items[2]).iter().collect())
          _ => raise @wire.Invalid("unknown_node", tag)
        }
      }
      (tag, @wire.obj(fields))
    }
    _ => variant(json)
  }
  let annotations = read_annotations(payload)
  let params = read_params(payload)
  let body = match tag {
    "TypeAliasSpecification" => {
      @wire.fields(payload, ["annotations", "typeParams", "typeExp"])
      ignore(@wire.field(payload, "typeParams"))
      @model.TypeAliasSpecification(
        params,
        read_type(@wire.field(payload, "typeExp")),
      )
    }
    "OpaqueTypeSpecification" => {
      @wire.fields(payload, ["annotations", "typeParams"])
      @model.OpaqueTypeSpecification(params)
    }
    "CustomTypeSpecification" => {
      @wire.fields(payload, ["annotations", "typeParams", "constructors"])
      ignore(@wire.field(payload, "typeParams"))
      @model.CustomTypeSpecification(
        params,
        read_constructors(@wire.field(payload, "constructors")),
      )
    }
    "DerivedTypeSpecification" => {
      @wire.fields(payload, [
        "annotations", "typeParams", "baseType", "fromBaseType", "toBaseType",
      ])
      ignore(@wire.field(payload, "typeParams"))
      @model.DerivedTypeSpecification(params, {
        base_type: read_type(@wire.field(payload, "baseType")),
        from_base_type: @wire.read_fqname(@wire.field(payload, "fromBaseType")),
        to_base_type: @wire.read_fqname(@wire.field(payload, "toBaseType")),
      })
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
  { annotations, body, }
}

///|
pub fn write_type_specification(
  specification : @model.TypeSpecification,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  put_annotations(fields, specification.annotations)
  let tag = match specification.body {
    TypeAliasSpecification(params, body) => {
      fields.append([
        ("typeParams", Json::array(params.map(name_key))),
        ("typeExp", write_type(body)),
      ])
      "TypeAliasSpecification"
    }
    OpaqueTypeSpecification(params) => {
      if !params.is_empty() {
        fields.push(("typeParams", Json::array(params.map(name_key))))
      }
      "OpaqueTypeSpecification"
    }
    CustomTypeSpecification(params, constructors) => {
      fields.append([
        ("typeParams", Json::array(params.map(name_key))),
        ("constructors", write_constructors(constructors)),
      ])
      "CustomTypeSpecification"
    }
    DerivedTypeSpecification(params, details) => {
      fields.append([
        ("typeParams", Json::array(params.map(name_key))),
        ("baseType", write_type(details.base_type)),
        ("fromBaseType", @wire.write_fqname(details.from_base_type)),
        ("toBaseType", @wire.write_fqname(details.to_base_type)),
      ])
      "DerivedTypeSpecification"
    }
  }
  @wire.tag(tag, @wire.obj(fields))
}

///|
pub fn read_type_definition(json : Json) -> @model.TypeDefinition raise {
  let (tag, payload) = variant(json)
  let params = @wire.array(@wire.field(payload, "typeParams")).map(
    @wire.read_name,
  )
  match tag {
    "TypeAliasDefinition" => {
      @wire.fields(payload, ["typeParams", "typeExp"])
      @model.TypeAliasDefinition(
        params,
        read_type(@wire.field(payload, "typeExp")),
      )
    }
    "CustomTypeDefinition" => {
      @wire.fields(payload, ["typeParams", "access", "constructors"])
      let access = read_access_level(@wire.field(payload, "access"))
      @model.CustomTypeDefinition(params, {
        access,
        value: read_constructors(@wire.field(payload, "constructors")),
      })
    }
    "IncompleteTypeDefinition" => {
      @wire.fields(payload, ["typeParams", "incompleteness", "partialTypeExp"])
      @model.IncompleteTypeDefinition(
        params,
        read_incompleteness(@wire.field(payload, "incompleteness")),
        read_optional(payload, "partialTypeExp", read_type),
      )
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn write_type_definition(value : @model.TypeDefinition) -> Json raise {
  match value {
    TypeAliasDefinition(params, body) =>
      @wire.tag(
        "TypeAliasDefinition",
        @wire.obj([
          ("typeParams", Json::array(params.map(name_key))),
          ("typeExp", write_type(body)),
        ]),
      )
    CustomTypeDefinition(params, constructors) =>
      @wire.tag(
        "CustomTypeDefinition",
        @wire.obj([
          ("typeParams", Json::array(params.map(name_key))),
          ("access", write_access_level(constructors.access)),
          ("constructors", write_constructors(constructors.value)),
        ]),
      )
    IncompleteTypeDefinition(params, incompleteness, partial) => {
      let fields = [
        ("typeParams", Json::array(params.map(name_key))),
        ("incompleteness", write_incompleteness(incompleteness)),
      ]
      if partial is Some(tpe) {
        fields.push(("partialTypeExp", write_type(tpe)))
      }
      @wire.tag("IncompleteTypeDefinition", @wire.obj(fields))
    }
  }
}

///|
pub fn read_value_specification(json : Json) -> @model.ValueSpecification raise {
  @wire.fields(json, ["annotations", "inputs", "output"])
  {
    annotations: read_annotations(json),
    inputs: read_inputs(optional_object(json, "inputs")),
    output: read_type(@wire.field(json, "output")),
  }
}

///|
pub fn write_value_specification(
  value : @model.ValueSpecification,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  put_annotations(fields, value.annotations)
  if !value.inputs.is_empty() {
    fields.push(("inputs", write_inputs(value.inputs)))
  }
  fields.push(("output", write_type(value.output)))
  @wire.obj(fields)
}

///|
fn read_access_level(json : Json) -> @model.Access raise {
  match @wire.string(json) {
    "Public" | "public" | "pub" => @model.Access::Public
    "Private" | "private" => @model.Access::Private
    other => raise @wire.Invalid("invalid_access", other)
  }
}

///|
fn write_access_level(access : @model.Access) -> Json {
  @wire.text(
    match access {
      Public => "Public"
      Private => "Private"
    },
  )
}

///|
pub fn[T] read_access(
  json : Json,
  decode : (Json) -> T raise,
) -> @model.AccessControlled[T] raise {
  let fields = @wire.object(json)
  if fields.contains("access") {
    let access = read_access_level(@wire.field(json, "access"))
    let value = match fields.get("value") {
      Some(value) => {
        @wire.fields(json, ["access", "value"])
        value
      }
      None => {
        let rest = Map::from_array(fields.iter().collect())
        ignore(rest.remove("access"))
        Json::object(rest)
      }
    }
    { access, value: decode(value), }
  } else {
    let (tag, payload) = variant(json)
    { access: read_access_level(@wire.text(tag)), value: decode(payload), }
  }
}

///|
pub fn[T] write_access(
  value : @model.AccessControlled[T],
  encode : (T) -> Json raise,
) -> Json raise {
  @wire.tag(
    match value.access {
      Public => "Public"
      Private => "Private"
    },
    encode(value.value),
  )
}

///|
pub fn[T] read_documented(
  json : Json,
  decode : (Json) -> T raise,
) -> @model.Documented[T] raise {
  let fields = @wire.object(json)
  let doc = match fields.get("doc") {
    None => None
    Some(doc) => Some(@wire.string(doc))
  }
  if fields.contains("value") {
    @wire.fields(json, ["doc", "value"])
    { doc, value: decode(@wire.field(json, "value")), }
  } else {
    let body = Map::from_array(fields.iter().collect())
    ignore(body.remove("doc"))
    { doc, value: decode(Json::object(body)), }
  }
}

///|
pub fn[T] write_documented(
  value : @model.Documented[T],
  encode : (T) -> Json raise,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  if value.doc is Some(doc) {
    fields.push(("doc", @wire.text(doc)))
  }
  fields.append(@wire.object(encode(value.value)).iter().collect())
  @wire.obj(fields)
}

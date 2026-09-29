///|
pub fn[TA, VA] read_module_definition(
  json : Json,
  ta : (Json) -> TA raise,
  va : (Json) -> VA raise,
) -> @model.ModuleDefinition[TA, VA] raise {
  @wire.fields(json, ["types", "values", "doc"])
  {
    types: @wire.read_map(@wire.field(json, "types"), @wire.read_name, fn(
      item,
    ) raise {
      read_access(item, fn(item) raise {
        read_documented(item, fn(item) raise { read_type_definition(item, ta) })
      })
    }),
    values: @wire.read_map(@wire.field(json, "values"), @wire.read_name, fn(
      item,
    ) raise {
      read_access(item, fn(item) raise {
        read_documented(item, fn(item) raise {
          read_value_definition(item, ta, va)
        })
      })
    }),
    doc: match @wire.optional(json, "doc") {
      None => None
      Some(doc) => @wire.nullable_string(doc)
    },
  }
}

///|
pub fn[TA, VA] write_module_definition(
  value : @model.ModuleDefinition[TA, VA],
  ta : (TA) -> Json raise,
  va : (VA) -> Json raise,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  fields.push(
    (
      "types",
      @wire.write_map(
        value.types,
        fn(key) raise { @wire.write_legacy_name(key) },
        fn(item) raise {
          write_access(item, fn(item) raise {
            write_documented(item, fn(item) raise {
              write_type_definition(item, ta)
            })
          })
        },
        legacy=true,
      ),
    ),
  )
  fields.push(
    (
      "values",
      @wire.write_map(
        value.values,
        fn(key) raise { @wire.write_legacy_name(key) },
        fn(item) raise {
          write_access(item, fn(item) raise {
            write_documented(item, fn(item) raise {
              write_value_definition(item, ta, va)
            })
          })
        },
        legacy=true,
      ),
    ),
  )
  fields.push(("doc", @wire.write_nullable_string(value.doc)))
  @wire.obj(fields)
}

///|
pub fn[TA, VA] read_package_definition(
  json : Json,
  ta : (Json) -> TA raise,
  va : (Json) -> VA raise,
) -> @model.PackageDefinition[TA, VA] raise {
  @wire.fields(json, ["modules"])
  let modules = @wire.field(json, "modules")
  {
    modules: @wire.read_map(modules, @wire.read_path, fn(item) raise {
      read_access(item, fn(item) raise { read_module_definition(item, ta, va) })
    }),
  }
}

///|
pub fn[TA, VA] write_package_definition(
  value : @model.PackageDefinition[TA, VA],
  ta : (TA) -> Json raise,
  va : (VA) -> Json raise,
) -> Json raise {
  let modules = @wire.write_map(
    value.modules,
    fn(key) raise { @wire.write_legacy_path(key) },
    fn(item) raise {
      write_access(item, fn(item) raise {
        write_module_definition(item, ta, va)
      })
    },
    legacy=true,
  )
  @wire.obj([("modules", modules)])
}

///|
pub fn[TA] read_module_specification(
  json : Json,
  ta : (Json) -> TA raise,
) -> @model.ModuleSpecification[TA] raise {
  @wire.fields(json, ["types", "values", "doc"])
  {
    types: @wire.read_map(@wire.field(json, "types"), @wire.read_name, fn(
      item,
    ) raise {
      read_documented(item, fn(item) raise { read_type_specification(item, ta) })
    }),
    values: @wire.read_map(@wire.field(json, "values"), @wire.read_name, fn(
      item,
    ) raise {
      read_documented(item, fn(item) raise {
        read_value_specification(item, ta)
      })
    }),
    doc: match @wire.optional(json, "doc") {
      None => None
      Some(doc) => @wire.nullable_string(doc)
    },
  }
}

///|
pub fn[TA] write_module_specification(
  value : @model.ModuleSpecification[TA],
  ta : (TA) -> Json raise,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  fields.push(
    (
      "types",
      @wire.write_map(
        value.types,
        fn(key) raise { @wire.write_legacy_name(key) },
        fn(item) raise {
          write_documented(item, fn(item) raise {
            write_type_specification(item, ta)
          })
        },
        legacy=true,
      ),
    ),
  )
  fields.push(
    (
      "values",
      @wire.write_map(
        value.values,
        fn(key) raise { @wire.write_legacy_name(key) },
        fn(item) raise {
          write_documented(item, fn(item) raise {
            write_value_specification(item, ta)
          })
        },
        legacy=true,
      ),
    ),
  )
  fields.push(("doc", @wire.write_nullable_string(value.doc)))
  @wire.obj(fields)
}

///|
pub fn[TA] read_package_specification(
  json : Json,
  ta : (Json) -> TA raise,
) -> @model.PackageSpecification[TA] raise {
  @wire.fields(json, ["modules"])
  let modules = @wire.field(json, "modules")
  {
    modules: @wire.read_map(modules, @wire.read_path, fn(item) raise {
      read_module_specification(item, ta)
    }),
  }
}

///|
pub fn[TA] write_package_specification(
  value : @model.PackageSpecification[TA],
  ta : (TA) -> Json raise,
) -> Json raise {
  let modules = @wire.write_map(
    value.modules,
    fn(key) raise { @wire.write_legacy_path(key) },
    fn(item) raise { write_module_specification(item, ta) },
    legacy=true,
  )
  @wire.obj([("modules", modules)])
}

///|
fn read_ta(json : Json) -> Unit raise {
  @wire.unit(json)
}

///|
fn write_ta(unit : Unit) -> Json raise {
  @wire.unit(@wire.write_unit(unit))
  @wire.write_unit(unit)
}

///|
fn read_va(json : Json) -> @model.Type[Unit] raise {
  read_type(json, read_ta)
}

///|
fn write_va(value : @model.Type[Unit]) -> Json raise {
  write_type(value, write_ta)
}

///|
pub fn read_distribution(json : Json) -> @model.Distribution raise {
  let a = @wire.tuple(json, 4)
  let name = @wire.read_path(a[1])
  let dependencies = @wire.read_map(a[2], @wire.read_path, fn(spec) raise {
    read_package_specification(spec, read_ta)
  })
  match @wire.string(a[0]) {
    "Library" =>
      @model.Library(
        name,
        dependencies,
        read_package_definition(a[3], read_ta, read_va),
      )
    tag => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn write_distribution(value : @model.Distribution) -> Json raise {
  match value {
    Library(name, dependencies, body) =>
      Json::array([
        @wire.text("Library"),
        @wire.write_legacy_path(name),
        @wire.write_map(
          dependencies,
          fn(key) raise { @wire.write_legacy_path(key) },
          fn(spec) raise { write_package_specification(spec, write_ta) },
          legacy=true,
        ),
        write_package_definition(body, write_ta, write_va),
      ])
  }
}

///|
pub fn from_json(json : Json) -> @model.IRFile raise {
  let format_version = @wire.read_version(@wire.field(json, "formatVersion"))
  format_version.check_family(2U)
  @wire.fields(json, ["formatVersion", "distribution"])
  @model.IRFile::new(
    read_distribution(@wire.field(json, "distribution")),
    format_version~,
  )
}

///|
pub fn to_json(file : @model.IRFile) -> Json raise {
  @wire.obj([
    ("formatVersion", @wire.write_version(file.format_version)),
    ("distribution", write_distribution(file.distribution)),
  ])
}

///|
pub fn read(text : String) -> @model.IRFile raise {
  from_json(@wire.parse(text))
}

///|
pub fn write(file : @model.IRFile) -> String raise {
  to_json(file).stringify()
}

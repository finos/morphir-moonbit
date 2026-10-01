///|
pub fn generate(
  input : Input,
  limits? : Limits? = None,
  cancelled? : () -> Bool = fn() { false },
) -> Output raise GenerationError {
  generate_library(input, limits.unwrap_or(Limits::default()), cancelled) catch {
    Invalid(_, _, _) as error => raise error
    @wire.Invalid(code, message) => raise Invalid(code, input.unit_id, message)
    error =>
      raise Invalid("moonbit.invalid_input", input.unit_id, error.to_string())
  }
}

///|
fn generate_library(
  input : Input,
  limits : Limits,
  cancelled : () -> Bool,
) -> Output raise {
  fn check_cancelled() -> Unit raise {
    if cancelled() {
      raise Invalid("moonbit.cancelled", input.unit_id, "Cancelled")
    }
  }
  check_cancelled()
  if input.unit_id == "" ||
    limits.max_declarations <= 0 ||
    limits.max_bytes <= 0 {
    raise Invalid(
      "moonbit.invalid_input",
      input.unit_id,
      "Nonempty unit identity and positive limits are required",
    )
  }
  let (package_name, package_def) = match input.ir.distribution {
    Library(name, _, definition) => (name, definition)
    _ =>
      raise Invalid(
        "moonbit.unsupported_distribution",
        input.unit_id,
        "A complete library implementation is required",
      )
  }
  validate_path(package_name)
  let source_ir = canonical_json(@ir_json.to_json(input.ir))
  if @utf8.encode(source_ir).length() > limits.max_bytes {
    raise Invalid(
      "moonbit.byte_limit",
      input.unit_id,
      "Source IR snapshot exceeds the output budget",
    )
  }
  let owned = Map::from_array([("unit:" + input.unit_id, true)])
  let index : Map[@ir.FQName, Declaration] = Map([])
  let module_names = package_def.modules.keys().collect()
  module_names.sort()
  for module_name in module_names {
    check_cancelled()
    validate_path(module_name)
    let access = package_def.modules[module_name]
    let module_def = access.value
    let module_id = "module:" +
      package_name.to_canonical() +
      ":" +
      module_name.to_canonical()
    owned[module_id] = true
    if !module_def.types.is_empty() {
      raise Invalid(
        "moonbit.unsupported_type_definition", module_id, "Aliases and custom types belong to the next generator slice",
      )
    }
    for name, value in module_def.values {
      check_cancelled()
      validate_name(name)
      let fqname : @ir.FQName = { package_name, module_name, local_name: name, }
      let context = value_node(fqname)
      let (output, body) = match value.value.value {
        ExpressionBody(inputs, output, body) => {
          if !inputs.is_empty() {
            raise Invalid(
              "moonbit.unsupported_function", context, "This slice supports zero-input declarations",
            )
          }
          (scalar_type(output, context + "/output"), body)
        }
        IncompleteBody(_, _, _, _) =>
          raise Invalid(
            "moonbit.incomplete_body", context, "Incomplete definition",
          )
        NativeBody(_, _, _) | ExternalBody(_, _, _, _) =>
          raise Invalid(
            "moonbit.unresolved_implementation", context, "No target implementation is registered",
          )
      }
      index[fqname] = {
        fqname,
        module_name,
        output,
        body,
        public: access.access == @ir.Access::Public &&
        value.access == @ir.Access::Public,
      }
      for node in [context, context + "/output", context + "/body"] {
        owned[node] = true
      }
      if index.length() > limits.max_declarations {
        raise Invalid(
          "moonbit.declaration_limit", context, "Too many declarations",
        )
      }
    }
  }
  let names = index.keys().collect()
  names.sort()
  let imports = Map::from_array([("sdk", true)])
  let definitions = []
  let symbols = []
  let generated = Map([])
  for name in names {
    check_cancelled()
    let declaration = index[name]
    let identifier = value_name(name)
    if generated.contains(identifier) {
      raise Invalid("moonbit.name_collision", name.to_canonical(), identifier)
    }
    generated[identifier] = true
    let output = moon_type(declaration.output, imports)
    let body = scalar_expression(declaration, index, imports)
    definitions.push(
      "///|\n" +
      (if declaration.public { "pub " } else { "" }) +
      "fn " +
      identifier +
      "() -> " +
      output +
      " raise @sdk.SdkError {\n  " +
      body +
      "\n}\n",
    )
    let source_node = value_node(name)
    symbols.push({
      fqname: name.to_canonical(),
      generated_name: identifier,
      public: declaration.public,
      source_node,
      generated_node: "moonbit:fn:" + identifier,
      origins: [source_node, source_node + "/body"],
    })
  }
  let import_names = imports.keys().collect()
  import_names.sort()
  let package_manifest = "import {\n" +
    import_names
    .map(name => {
      "  " +
      quote("finos/morphir-sdk" + (if name == "sdk" { "" } else { "/" + name })) +
      " @" +
      name +
      ","
    })
    .join("\n") +
    "\n}\n"
  let module_name = "morphir-generated/p_" + hex(package_name.to_canonical())
  let module_manifest = "name = " +
    quote(module_name) +
    "\nversion = \"0.0.0\"\nimport {\n  \"finos/morphir-sdk@0.1.0\",\n}\n"
  check_cancelled()
  let metadata = symbol_metadata(input, source_ir, symbols, owned)
  let artifacts : Array[Artifact] = [
    { path: "moon.mod", role: ModuleManifest, content: Text(module_manifest), },
    {
      path: "moon.pkg",
      role: PackageManifest,
      content: Text(package_manifest),
    },
    {
      path: "library.mbt",
      role: Source,
      content: Text(definitions.join("\n")),
    },
    { path: "symbols.10n", role: Metadata, content: Binary(metadata), },
  ]
  let mut bytes = 0
  for artifact in artifacts {
    bytes += match artifact.content {
      Text(text) => @utf8.encode(text).length()
      Binary(data) => data.length()
    }
  }
  if bytes > limits.max_bytes {
    raise Invalid(
      "moonbit.byte_limit",
      input.unit_id,
      "Generated artifacts exceed the byte budget",
    )
  }
  check_cancelled()
  {
    artifacts,
    symbols,
    project: {
      module_name,
      root: "",
      members: artifacts.map(artifact => artifact.path),
      dependencies: [
        {
          module_name: "finos/morphir-sdk",
          version: "0.1.0",
          api_profile: "morphir-sdk-scalars-v1",
          semantic_pin: "bc99af69a8b24d391311fae3822a87eafef3c334",
        },
      ],
    },
  }
}

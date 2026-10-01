///|
fn part(text : String) -> String {
  text.replace(old="~", new="~0").replace(old="/", new="~1")
}

///|
fn collect(
  prefix : String,
  value : Json,
  result : Map[String, Bool],
  depth? : Int = 0,
) -> Unit raise {
  if depth > 128 || result.length() > 100000 {
    raise @codec_boundary.Invalid(
      "identity.tree_limit", "Identity depth or count exceeded",
    )
  }
  result[prefix] = true
  match value {
    Object(fields) =>
      for name, item in fields {
        collect(prefix + "/" + part(name), item, result, depth=depth + 1)
      }
    Array(items) =>
      for i, item in items {
        collect(prefix + "/" + i.to_string(), item, result, depth=depth + 1)
      }
    _ => ()
  }
}

///|
/// Stable declaration identities, with JSON-pointer suffixes for structural children.
/// Pair-array indices denote positions, not identities preserved through reordering.
pub fn nodes(unit_id : String, file : @ir.IRFile) -> Array[String] raise {
  let owned = Map::from_array([("unit:" + unit_id, true)])
  collect("unit:" + unit_id + "/ir", @ir_json.to_json(file), owned)
  if file.distribution is Library(package_name, _, definition) {
    for module_name, module_def in definition.modules {
      let module_id = "module:" +
        package_name.to_canonical() +
        ":" +
        module_name.to_canonical()
      owned[module_id] = true
      for name, value in module_def.value.values {
        let id = "value:" +
          package_name.to_canonical() +
          ":" +
          module_name.to_canonical() +
          "#" +
          name.to_canonical()
        owned[id] = true
        collect(
          id + "/definition",
          @codec.write_definition(value.value.value),
          owned,
        )
        match value.value.value {
          ExpressionBody(inputs, output, body) => {
            collect(id + "/output", @codec.write_type(output), owned)
            collect(id + "/body", @codec.write_value(body), owned)
            for input in inputs {
              collect(
                id + "/input/" + part(input.0.to_canonical()),
                @codec.write_type(input.1),
                owned,
              )
            }
          }
          _ => ()
        }
      }
      for name, entry in module_def.value.types {
        let id = "type:" +
          package_name.to_canonical() +
          ":" +
          module_name.to_canonical() +
          "#" +
          name.to_canonical()
        owned[id] = true
        if entry.value.value is CustomTypeDefinition(_, constructors) {
          for constructor_name, _ in constructors.value {
            owned["constructor:" +
            package_name.to_canonical() +
            ":" +
            module_name.to_canonical() +
            "#" +
            constructor_name.to_canonical()] = true
          }
        }
      }
    }
  }
  let result = owned.keys().collect()
  result.sort()
  result
}

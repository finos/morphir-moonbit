///|
fn closed_fields(
  value : Json,
  names : Array[String],
  code : String,
) -> Map[String, Json] raise {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    fields.keys().all(name => names.contains(name)) else {
    raise @execution.Invalid(code)
  }
  fields
}

///|
fn declaration_name(value : Json, code : String) -> String raise {
  guard value is String(name) && name.length() > 0 else {
    raise @execution.Invalid(code)
  }
  if name.length() > 1024 {
    raise @execution.Invalid("workbench.type_limit")
  }
  name
}

///|
fn declaration_nodes(budget : Ref[Int]) -> Unit raise {
  budget.val -= 1
  if budget.val < 0 {
    raise @execution.Invalid("workbench.type_limit")
  }
}

///|
fn declaration_array(
  value : Json,
  limit : Int,
  code : String,
) -> Array[Json] raise {
  guard value is Array(values) else { raise @execution.Invalid(code) }
  if values.length() > limit {
    raise @execution.Invalid("workbench.type_limit")
  }
  values
}

///|
fn declared_type(
  value : Json,
  depth : Int,
  budget : Ref[Int],
  references : Array[String],
) -> @execution.ValueType raise {
  declaration_nodes(budget)
  if depth > 64 {
    raise @execution.Invalid("workbench.type_limit")
  }
  let code = "workbench.invalid_type"
  let tag = field(value, "type")
  let names = match tag {
    String("list" | "maybe") => ["type", "item"]
    String("tuple") => ["type", "items"]
    String("record") => ["type", "fields"]
    String("custom") => ["type", "name"]
    String("result") => ["type", "ok", "err"]
    _ => ["type"]
  }
  ignore(closed_fields(value, names, code))
  fn child(value : Json) -> @execution.ValueType raise {
    declared_type(value, depth + 1, budget, references)
  }
  match tag {
    String("int") => Int
    String("bool") => Bool
    String("unit") => Unit
    String("decimal") => Decimal
    String("float64") => Float64
    String("text") => Text
    String("character") => Character
    String("function") =>
      raise @execution.Invalid("execution.boundary_function")
    String("list") => Sequence(child(field(value, "item")))
    String("maybe") => Optional(child(field(value, "item")))
    String("tuple") =>
      Product(declaration_array(field(value, "items"), 1024, code).map(child))
    String("record") => {
      let seen : Map[String, Bool] = Map([])
      let fields = declaration_array(field(value, "fields"), 1024, code).map(item => {
        declaration_nodes(budget)
        ignore(closed_fields(item, ["name", "type"], code))
        let name = declaration_name(field(item, "name"), code)
        if seen.contains(name) {
          raise @execution.Invalid(code)
        }
        seen[name] = true
        (name, child(field(item, "type")))
      })
      Record(fields)
    }
    String("custom") => {
      let name = declaration_name(field(value, "name"), code)
      references.push(name)
      Custom(name)
    }
    String("result") =>
      Outcome(child(field(value, "ok")), child(field(value, "err")))
    _ => raise @execution.Invalid(code)
  }
}

///|
/// Admit the complete bounded declaration graph before decoding argument data.
/// Named cycles are allowed; every referenced owner must exist, even if dormant.
fn admit_value(input : Json, format : Json) -> @execution.Value raise {
  ignore(
    closed_fields(
      input,
      ["value", "type", "definitions"],
      "workbench.invalid_request",
    ),
  )
  let budget = Ref(10000)
  let references : Array[String] = []
  let expected = declared_type(field(input, "type"), 0, budget, references)
  let names : Map[String, Bool] = Map([])
  let code = "workbench.invalid_definitions"
  let definitions = declaration_array(field(input, "definitions"), 256, code).map(item => {
      declaration_nodes(budget)
      ignore(closed_fields(item, ["name", "constructors"], code))
      let name = declaration_name(field(item, "name"), code)
      if names.contains(name) {
        raise @execution.Invalid(code)
      }
      names[name] = true
      let tags : Map[String, Bool] = Map([])
      let constructors = declaration_array(
        field(item, "constructors"),
        256,
        code,
      ).map(variant => {
        declaration_nodes(budget)
        ignore(closed_fields(variant, ["name", "inputs"], code))
        let tag = declaration_name(field(variant, "name"), code)
        if tags.contains(tag) {
          raise @execution.Invalid(code)
        }
        tags[tag] = true
        let inputs = declaration_array(field(variant, "inputs"), 64, code).map(t => {
          declared_type(t, 0, budget, references)
        })
        @execution.ConstructorType::{ name: tag, inputs, }
      })
      @execution.CustomType::{ name, constructors, }
    },
  )
  for reference in references {
    if !names.contains(reference) {
      raise @execution.Invalid("execution.unresolved_custom_type")
    }
  }
  let value = decode_value(format, field(input, "value"))
  @execution.validate_as(value, expected, definitions)
  value
}

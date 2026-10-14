///|
/// The differences between the `expected` and the `actual` IR, one line per difference. The order is stable:
/// modules, types and values come in sorted key order, and the types of a module come before its values.
///
/// The comparison ignores what the Elm frontend does not give in Plan 1: type attributes (source locations and
/// constraints) and value bodies. A doc of `None` is the same as `Some("")`. A value compares its inputs and its
/// output, so `ExpressionBody(inputs, output, _)` matches `IncompleteBody(inputs, Some(output), Draft, None)`.
fn differences(expected : @ir.IRFile, actual : @ir.IRFile) -> Array[String] {
  let lines : Array[String] = []
  guard expected.distribution is Library(expected_package, _, expected_def) &&
    actual.distribution is Library(actual_package, _, actual_def) else {
    return ["distribution: not a library"]
  }
  if expected_package != actual_package {
    lines.push("package: name")
  }
  for path in sorted_keys(expected_def.modules, actual_def.modules) {
    let label = path.to_canonical()
    match (expected_def.modules.get(path), actual_def.modules.get(path)) {
      (Some(e), Some(a)) => {
        if e.access != a.access {
          lines.push("module \{label}: access")
        }
        if !same_doc(e.value.doc, a.value.doc) {
          lines.push("module \{label}: doc")
        }
        module_differences(label, e.value, a.value, lines)
      }
      (Some(_), None) => lines.push("module \{label}: missing")
      (None, Some(_)) => lines.push("module \{label}: unexpected")
      (None, None) => ()
    }
  }
  lines
}

///|
fn module_differences(
  label : String,
  expected : @ir.ModuleDefinition,
  actual : @ir.ModuleDefinition,
  lines : Array[String],
) -> Unit {
  for name in sorted_keys(expected.types, actual.types) {
    let item = "type \{label}#\{name.to_canonical()}"
    match (expected.types.get(name), actual.types.get(name)) {
      (Some(e), Some(a)) => {
        if e.access != a.access {
          lines.push("\{item}: access")
        }
        if !same_doc(e.value.doc, a.value.doc) {
          lines.push("\{item}: doc")
        }
        if strip_definition(e.value.value) != strip_definition(a.value.value) {
          lines.push("\{item}: definition")
        }
      }
      (Some(_), None) => lines.push("\{item}: missing")
      (None, Some(_)) => lines.push("\{item}: unexpected")
      (None, None) => ()
    }
  }
  for name in sorted_keys(expected.values, actual.values) {
    let item = "value \{label}#\{name.to_canonical()}"
    match (expected.values.get(name), actual.values.get(name)) {
      (Some(e), Some(a)) => {
        if e.access != a.access {
          lines.push("\{item}: access")
        }
        if !same_doc(e.value.doc, a.value.doc) {
          lines.push("\{item}: doc")
        }
        let (expected_inputs, expected_output) = signature(e.value.value)
        let (actual_inputs, actual_output) = signature(a.value.value)
        if expected_inputs != actual_inputs {
          lines.push("\{item}: inputs")
        }
        if expected_output != actual_output {
          lines.push("\{item}: output")
        }
      }
      (Some(_), None) => lines.push("\{item}: missing")
      (None, Some(_)) => lines.push("\{item}: unexpected")
      (None, None) => ()
    }
  }
}

///|
/// The keys of both maps, each once, in sorted order.
fn[K : Compare + Hash, A, B] sorted_keys(
  left : Map[K, A],
  right : Map[K, B],
) -> Array[K] {
  let keys : Array[K] = left.keys().collect()
  for key in right.keys() {
    if !left.contains(key) {
      keys.push(key)
    }
  }
  keys.sort()
  keys
}

///|
/// A doc of `None` is the same as an empty doc.
fn same_doc(expected : String?, actual : String?) -> Bool {
  expected.unwrap_or("") == actual.unwrap_or("")
}

///|
/// The inputs, with their types, and the output type of a value. The body is not part of it.
fn signature(
  definition : @ir.ValueDefinition,
) -> (Array[(@ir.Name, @ir.Type)], @ir.Type?) {
  let (inputs, output) = match definition {
    ExpressionBody(inputs, output, _)
    | NativeBody(inputs, output, _)
    | ExternalBody(inputs, output, _, _) => (inputs, Some(output))
    IncompleteBody(inputs, output, _, _) => (inputs, output)
  }
  (inputs.map(input => (input.0, strip_type(input.1))), output.map(strip_type))
}

///|
fn strip_definition(definition : @ir.TypeDefinition) -> @ir.TypeDefinition {
  match definition {
    TypeAliasDefinition(params, target) =>
      TypeAliasDefinition(params, strip_type(target))
    CustomTypeDefinition(params, constructors) => {
      let stripped : Map[@ir.Name, Array[(@ir.Name, @ir.Type)]] = Map([])
      for name, args in constructors.value {
        stripped[name] = args.map(arg => (arg.0, strip_type(arg.1)))
      }
      CustomTypeDefinition(params, { ..constructors, value: stripped, })
    }
    IncompleteTypeDefinition(params, reason, target) =>
      IncompleteTypeDefinition(
        params,
        strip_incompleteness(reason),
        target.map(strip_type),
      )
  }
}

///|
fn strip_incompleteness(reason : @ir.Incompleteness) -> @ir.Incompleteness {
  match reason {
    Hole(why, target) => Hole(why, target.map(strip_type))
    Draft => Draft
  }
}

///|
/// The type with every `TypeAttributes` set to the default.
fn strip_type(t : @ir.Type) -> @ir.Type {
  let none = @ir.TypeAttributes::default()
  match t {
    Variable(_, name) => Variable(none, name)
    Reference(_, name, args) => Reference(none, name, args.map(strip_type))
    Tuple(_, items) => Tuple(none, items.map(strip_type))
    Record(_, fields) => Record(none, strip_fields(fields))
    ExtensibleRecord(_, name, fields) =>
      ExtensibleRecord(none, name, strip_fields(fields))
    Function(_, argument, result) =>
      Function(none, strip_type(argument), strip_type(result))
    Unit(_) => Unit(none)
  }
}

///|
fn strip_fields(fields : Map[@ir.Name, @ir.Type]) -> Map[@ir.Name, @ir.Type] {
  let stripped : Map[@ir.Name, @ir.Type] = Map([])
  for name, field in fields {
    stripped[name] = strip_type(field)
  }
  stripped
}

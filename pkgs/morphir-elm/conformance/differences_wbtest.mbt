///|
/// The differences between the `expected` and the `actual` IR, one line per difference. The order is stable:
/// modules, types and values come in sorted key order, and the types of a module come before its values.
///
/// Type attributes (source locations and constraints) and value attributes do not count, and a doc of `None` is
/// the same as `Some("")`. A value compares its access, its doc, its input names (`inputs`) and the shape of its
/// body (`body`, see `body_shape`). When the body shapes are the same, each node type and signature type of the
/// value that differs is one `type <path>: expected <t1>, found <t2>` line from `@typing.compare_types`, with the
/// morphir-elm placeholders of the signatures masked: morphir-elm writes the signature of an unannotated value
/// from a first inference pass, so those placeholders are not declared types.
fn differences(expected : @ir.IRFile, actual : @ir.IRFile) -> Array[String] {
  let lines : Array[String] = []
  guard expected.distribution is Library(expected_package, _, expected_def) &&
    actual.distribution is Library(actual_package, _, actual_def) else {
    return ["distribution: not a library"]
  }
  if expected_package != actual_package {
    lines.push("package: name")
  }
  let types = type_differences(expected, actual)
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
        let root = (name : @ir.Name) => {
          let fq : @ir.FQName = {
            package_name: expected_package,
            module_name: path,
            local_name: name,
          }
          "value:" + fq.to_canonical()
        }
        module_differences(label, e.value, a.value, lines, (name : @ir.Name) => {
          types.get(root(name)).unwrap_or([])
        })
      }
      (Some(_), None) => lines.push("module \{label}: missing")
      (None, Some(_)) => lines.push("module \{label}: unexpected")
      (None, None) => ()
    }
  }
  lines
}

///|
/// The `@typing.compare_types` lines of the two files, with the SDK and with the signature placeholders masked,
/// by the logical path of their declaration (`value:<package>:<module>#<name>`).
fn type_differences(
  expected : @ir.IRFile,
  actual : @ir.IRFile,
) -> Map[String, Array[String]] {
  let sdk = Map::from_array([
    (@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification()),
  ])
  let out : Map[String, Array[String]] = Map([])
  for line in @typing.compare_types(expected, actual, sdk, mask_signatures=true) {
    let root = declaration_of(line)
    match out.get(root) {
      Some(lines) => lines.push(line)
      None => out[root] = [line]
    }
  }
  out
}

///|
/// The logical path of the declaration of a `compare_types` line: the text before the first `/` or `:` after
/// the `#`.
fn declaration_of(line : String) -> String {
  let chars = line.to_array()
  guard chars.search('#') is Some(hash) else { return line }
  for i = hash + 1; i < chars.length(); i = i + 1 {
    if chars[i] == '/' || chars[i] == ':' {
      return String::from_array(chars[:i])
    }
  }
  line
}

///|
/// The differences of one module. `types` gives the `type` lines of a value, by its name.
fn module_differences(
  label : String,
  expected : @ir.ModuleDefinition,
  actual : @ir.ModuleDefinition,
  lines : Array[String],
  types : (@ir.Name) -> Array[String],
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
        if input_names(e.value.value) != input_names(a.value.value) {
          lines.push("\{item}: inputs")
        }
        if body_shape(e.value.value) != body_shape(a.value.value) {
          lines.push("\{item}: body")
        } else {
          for line in types(name) {
            lines.push("type " + line)
          }
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
/// The input names of a value.
fn input_names(definition : @ir.ValueDefinition) -> Array[@ir.Name] {
  let inputs = match definition {
    ExpressionBody(inputs, _, _)
    | NativeBody(inputs, _, _)
    | ExternalBody(inputs, _, _, _)
    | IncompleteBody(inputs, _, _, _) => inputs
  }
  inputs.map(input => input.0)
}

///|
/// The shape of the body of a top-level value: the definition with no inputs and the output `()`, and its body
/// as `shape_value` gives it. The inputs and the signature types are compared elsewhere.
fn body_shape(definition : @ir.ValueDefinition) -> @ir.ValueDefinition {
  match shape_definition(definition) {
    ExpressionBody(_, output, body) => ExpressionBody([], output, body)
    NativeBody(_, output, info) => NativeBody([], output, info)
    ExternalBody(_, output, bindings, fallback) =>
      ExternalBody([], output, bindings, fallback)
    IncompleteBody(_, output, why, value) =>
      IncompleteBody([], output, why, value)
  }
}

///|
/// A definition with every signature type `()` and its body as `shape_value` gives it. The input names stay.
fn shape_definition(definition : @ir.ValueDefinition) -> @ir.ValueDefinition {
  let hole : @ir.Type = Unit(@ir.TypeAttributes::default())
  let inputs = (xs : Array[(@ir.Name, @ir.Type)]) => xs.map(x => (x.0, hole))
  match definition {
    ExpressionBody(xs, _, body) =>
      ExpressionBody(inputs(xs), hole, shape_value(body))
    NativeBody(xs, _, info) => NativeBody(inputs(xs), hole, info)
    ExternalBody(xs, _, bindings, fallback) =>
      ExternalBody(inputs(xs), hole, bindings, fallback.map(shape_value))
    IncompleteBody(xs, output, why, value) =>
      IncompleteBody(
        inputs(xs),
        output.map(_ => hole),
        strip_incompleteness(why),
        value.map(shape_value),
      )
  }
}

///|
/// A value with every `ValueAttributes` the default and every let-definition signature type `()`. The node
/// types and the let signature types are compared by `@typing.compare_types`. A `Record` and a `LetRecursion`
/// keep their maps, which compare as maps.
fn shape_value(value : @ir.Value) -> @ir.Value {
  let none = @ir.ValueAttributes::default()
  let fields = (fields : Map[@ir.Name, @ir.Value]) => {
    let out : Map[@ir.Name, @ir.Value] = Map([])
    for name, field in fields {
      out[name] = shape_value(field)
    }
    out
  }
  match value {
    Literal(_, literal) => Literal(none, literal)
    Constructor(_, name) => Constructor(none, name)
    Tuple(_, items) => Tuple(none, items.map(shape_value))
    List(_, items) => List(none, items.map(shape_value))
    Record(_, items) => Record(none, fields(items))
    Variable(_, name) => Variable(none, name)
    Reference(_, name) => Reference(none, name)
    Field(_, record, name) => Field(none, shape_value(record), name)
    FieldFunction(_, name) => FieldFunction(none, name)
    Apply(_, function, argument) =>
      Apply(none, shape_value(function), shape_value(argument))
    Lambda(_, pattern, body) =>
      Lambda(none, shape_pattern(pattern), shape_value(body))
    LetDefinition(_, name, definition, rest) =>
      LetDefinition(none, name, shape_definition(definition), shape_value(rest))
    LetRecursion(_, definitions, rest) => {
      let out : Map[@ir.Name, @ir.ValueDefinition] = Map([])
      for name, definition in definitions {
        out[name] = shape_definition(definition)
      }
      LetRecursion(none, out, shape_value(rest))
    }
    Destructure(_, pattern, bound, rest) =>
      Destructure(
        none,
        shape_pattern(pattern),
        shape_value(bound),
        shape_value(rest),
      )
    IfThenElse(_, condition, then_, else_) =>
      IfThenElse(
        none,
        shape_value(condition),
        shape_value(then_),
        shape_value(else_),
      )
    PatternMatch(_, subject, cases) =>
      PatternMatch(
        none,
        shape_value(subject),
        cases.map(c => (shape_pattern(c.0), shape_value(c.1))),
      )
    UpdateRecord(_, record, items) =>
      UpdateRecord(none, shape_value(record), fields(items))
    Unit(_) => Unit(none)
    Hole(_, reason, target) => Hole(none, reason, target.map(strip_type))
  }
}

///|
/// A pattern with every `ValueAttributes` the default.
fn shape_pattern(pattern : @ir.Pattern) -> @ir.Pattern {
  let none = @ir.ValueAttributes::default()
  match pattern {
    WildcardPattern(_) => WildcardPattern(none)
    AsPattern(_, inner, name) => AsPattern(none, shape_pattern(inner), name)
    TuplePattern(_, items) => TuplePattern(none, items.map(shape_pattern))
    ConstructorPattern(_, name, args) =>
      ConstructorPattern(none, name, args.map(shape_pattern))
    EmptyListPattern(_) => EmptyListPattern(none)
    HeadTailPattern(_, head, tail) =>
      HeadTailPattern(none, shape_pattern(head), shape_pattern(tail))
    LiteralPattern(_, literal) => LiteralPattern(none, literal)
    UnitPattern(_) => UnitPattern(none)
  }
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

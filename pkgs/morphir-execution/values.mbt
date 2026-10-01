///|
pub(all) suberror ExecutionError {
  Invalid(String)
} derive(Eq, Debug)

///|
pub extend ExecutionError with Eq::{equal, not_equal}

///|
pub extend ExecutionError with @debug.Debug::{to_repr}

///|
pub(all) enum Value {
  Integer(@bigint.BigInt)
  Boolean(Bool)
  Unit
} derive(Eq, Debug)

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub(all) enum ValueType {
  Int
  Bool
  Unit
} derive(Eq, Debug)

///|
pub extend ValueType with Eq::{equal, not_equal}

///|
pub extend ValueType with @debug.Debug::{to_repr}

///|
pub fn Value::value_type(self : Value) -> ValueType {
  match self {
    Integer(_) => Int
    Boolean(_) => Bool
    Unit => Unit
  }
}

///|
pub(all) struct Call {
  id : String
  entry : String
  arguments : Array[Value]
} derive(Eq, Debug)

///|
pub extend Call with Eq::{equal, not_equal}

///|
pub extend Call with @debug.Debug::{to_repr}

///|
pub(all) struct Suite {
  calls : Array[Call]
} derive(Eq, Debug)

///|
pub extend Suite with Eq::{equal, not_equal}

///|
pub extend Suite with @debug.Debug::{to_repr}

///|
pub fn Suite::validate(self : Suite) -> Unit raise {
  if self.calls.is_empty() || self.calls.length() > 1000 {
    raise Invalid("execution.call_limit")
  }
  let seen = Map([])
  for call in self.calls {
    if call.id == "" ||
      call.id.length() > 128 ||
      call.entry == "" ||
      call.entry.length() > 1024 ||
      seen.contains(call.id) {
      raise Invalid("execution.invalid_call_identity")
    }
    seen[call.id] = true
    if call.arguments.length() > 64 {
      raise Invalid("execution.argument_limit")
    }
  }
}

///|
pub fn Value::to_ion(self : Value) -> @ion.IonValue {
  match self {
    Integer(n) => @ion.IonValue::new(@ion.Int(n))
    Boolean(b) => @ion.IonValue::bool(b)
    Unit =>
      @ion.IonValue::untyped_null().with_annotation(
        @ion.SymbolToken::new("morphir_unit"),
      )
  }
}

///|
pub fn Value::from_ion(value : @ion.IonValue) -> Value raise {
  let a = value.annotations()
  if a.length() == 1 &&
    a[0].text() == Some("morphir_unit") &&
    value.kind() is Null(@ion.Null) {
    return Unit
  }
  if !a.is_empty() {
    raise Invalid("execution.value_annotation")
  }
  match value.kind() {
    Int(n) => Integer(n)
    Bool(b) => Boolean(b)
    _ => raise Invalid("execution.unsupported_value")
  }
}

///|
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Integer(n) => { "type": "int", "value": n.to_string() }
    Boolean(b) => { "type": "bool", "value": b }
    Unit => { "type": "unit" }
  }
}

///|
pub fn fields(
  value : @ion.IonValue,
  allowed : Array[String],
) -> Map[String, @ion.IonValue] raise {
  let result = Map([])
  guard value.kind() is Struct(items) else {
    raise Invalid("execution.expected_struct")
  }
  for item in items {
    let name = item.name().text().unwrap_or("")
    if !allowed.contains(name) || result.contains(name) {
      raise Invalid("execution.invalid_field: " + name)
    }
    result[name] = item.value()
  }
  result
}

///|
pub fn required(
  fields : Map[String, @ion.IonValue],
  name : String,
) -> @ion.IonValue raise {
  match fields.get(name) {
    Some(v) => v
    None => raise Invalid("execution.missing_field: " + name)
  }
}

///|
pub fn string(value : @ion.IonValue) -> String raise {
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  match value.kind() {
    String(s) => s
    _ => raise Invalid("execution.expected_string")
  }
}

///|
fn list(value : @ion.IonValue) -> Array[@ion.IonValue] raise {
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  match value.kind() {
    List(v) => v
    _ => raise Invalid("execution.expected_list")
  }
}

///|
pub fn record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::from_fields(fields.map(p => @ion.Field::new(p.0, p.1)))
}

///|
pub fn Suite::to_ion(self : Suite) -> @ion.IonValue raise {
  self.validate()
  record([
    ("profile", @ion.IonValue::string("morphir-invocations-v1")),
    (
      "calls",
      @ion.IonValue::list(
        self.calls.map(call => {
          record([
            ("id", @ion.IonValue::string(call.id)),
            ("entry", @ion.IonValue::string(call.entry)),
            (
              "arguments",
              @ion.IonValue::list(call.arguments.map(Value::to_ion)),
            ),
          ])
        }),
      ),
    ),
  ])
}

///|
pub fn Suite::from_ion(value : @ion.IonValue) -> Suite raise {
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  let f = fields(value, ["profile", "calls"])
  if string(required(f, "profile")) != "morphir-invocations-v1" {
    raise Invalid("execution.unsupported_profile")
  }
  let suite = Suite::{
    calls: list(required(f, "calls")).map(v => {
      if v.has_annotations() {
        raise Invalid("execution.unexpected_annotation")
      }
      let f = fields(v, ["id", "entry", "arguments"])
      Call::{
        id: string(required(f, "id")),
        entry: string(required(f, "entry")),
        arguments: list(required(f, "arguments")).map(Value::from_ion),
      }
    }),
  }
  suite.validate()
  suite
}

///|
pub fn Suite::to_json(self : Suite) -> Json {
  {
    "profile": "morphir-invocations-v1",
    "calls": self.calls.map(call => {
      (
        {
          "id": call.id,
          "entry": call.entry,
          "arguments": call.arguments.map(Value::to_json),
        } : Json)
    }),
  }
}

///|
pub fn Value::from_json(value : Json) -> Value raise {
  guard value is Object(fields) else {
    raise Invalid("execution.invalid_json_value")
  }
  let unit = fields.get("type") == Some(Json::string("unit"))
  if fields.length() != (if unit { 1 } else { 2 }) ||
    fields.keys().any(k => k != "type" && k != "value") {
    raise Invalid("execution.invalid_json_value")
  }
  match value {
    { "type": String("int"), "value": String(s), .. } => {
      let chars = s.to_array()
      let start = if s.has_prefix("-") { 1 } else { 0 }
      if chars.length() <= start ||
        chars.length() > 10000 ||
        !chars[start:].iter().all(c => c >= '0' && c <= '9') {
        raise Invalid("execution.invalid_integer")
      }
      Integer(@bigint.BigInt::from_string(s))
    }
    { "type": String("bool"), "value": True, .. } => Boolean(true)
    { "type": String("bool"), "value": False, .. } => Boolean(false)
    { "type": String("unit"), .. } => Unit
    _ => raise Invalid("execution.invalid_json_value")
  }
}

///|
pub fn Suite::from_json(value : Json) -> Suite raise {
  guard value is Object(fields) else {
    raise Invalid("execution.invalid_json_suite")
  }
  if fields.length() != 2 {
    raise Invalid("execution.invalid_json_suite")
  }
  guard value
    is {
      "profile": String("morphir-invocations-v1"),
      "calls": Array(calls),
      ..
    } else {
    raise Invalid("execution.unsupported_profile")
  }
  let suite = Suite::{
    calls: calls.map(call => {
      guard call is Object(fields) else {
        raise Invalid("execution.invalid_call")
      }
      if fields.length() != 3 {
        raise Invalid("execution.invalid_call")
      }
      guard call
        is {
          "id": String(id),
          "entry": String(entry),
          "arguments": Array(arguments),
          ..
        } else {
        raise Invalid("execution.invalid_call")
      }
      Call::{ id, entry, arguments: arguments.map(Value::from_json), }
    }),
  }
  suite.validate()
  suite
}

///|
pub fn Suite::decode(bytes : Bytes, format : String) -> Suite raise {
  if bytes.length() > 1048576 {
    raise Invalid("execution.input_limit")
  }
  match format {
    "ion-binary" => Suite::from_ion(@binary.read_binary_value(bytes[:]))
    "ion-text" => Suite::from_ion(@text.read_ion(@utf8.decode(bytes[:])[:]))
    "json" => {
      let source = @utf8.decode(bytes[:])
      ignore(@json.parse(source))
      json_ion_suite(@text.read_ion(source[:]))
    }
    _ => raise Invalid("execution.unsupported_format")
  }
}

///|
pub fn Suite::encode(self : Suite, format : String) -> Bytes raise {
  let value = self.to_ion()
  match format {
    "ion-binary" => @binary.write_binary_value(value)
    "ion-text" => @utf8.encode(@text.write_ion(value))
    "json" => @utf8.encode(self.to_json().stringify())
    _ => raise Invalid("execution.unsupported_format")
  }
}

///|
pub fn ValueType::name(self : ValueType) -> String {
  match self {
    Int => "int"
    Bool => "bool"
    Unit => "unit"
  }
}

///|
// Reading the schema as Ion after JSON syntax validation preserves duplicate keys.
fn json_ion_suite(value : @ion.IonValue) -> Suite raise {
  let f = fields(value, ["profile", "calls"])
  if string(required(f, "profile")) != "morphir-invocations-v1" {
    raise Invalid("execution.unsupported_profile")
  }
  let suite = Suite::{
    calls: list(required(f, "calls")).map(call => {
      let f = fields(call, ["id", "entry", "arguments"])
      Call::{
        id: string(required(f, "id")),
        entry: string(required(f, "entry")),
        arguments: list(required(f, "arguments")).map(v => {
          let fields = fields(v, ["type", "value"])
          match string(required(fields, "type")) {
            "int" =>
              Value::from_json({
                "type": "int",
                "value": string(required(fields, "value")),
              })
            "bool" =>
              match required(fields, "value").kind() {
                Bool(b) => Boolean(b)
                _ => raise Invalid("execution.invalid_json_value")
              }
            "unit" => {
              if fields.length() != 1 {
                raise Invalid("execution.invalid_json_value")
              }
              Unit
            }
            _ => raise Invalid("execution.invalid_json_value")
          }
        }),
      }
    }),
  }
  suite.validate()
  suite
}

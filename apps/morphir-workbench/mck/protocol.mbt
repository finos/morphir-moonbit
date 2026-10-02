///|
fn invalid(id : Json, code : String) -> Json {
  { "id": id, "status": "invalid", "code": code }
}

///|
fn field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn valid_id(id : Json) -> Bool {
  id is Number(n, ..) && n >= 1 && n <= 9007199254740991.0 && n.floor() == n
}

///|
fn duplicate_members(value : @ion.IonValue) -> Bool {
  match value.kind() {
    Struct(fields) => {
      let seen = Map([])
      for item in fields {
        let name = item.name().text().unwrap_or("")
        if seen.contains(name) || duplicate_members(item.value()) {
          return true
        }
        seen[name] = true
      }
      false
    }
    List(items) => items.any(duplicate_members)
    _ => false
  }
}

///|
/// Core JSON validates grammar/depth. Ion retains member pairs so duplicates
/// cannot disappear during conversion to the core Json map. None means exit.
pub fn handle_line(source : String) -> Json? raise {
  let request = @json.parse(source)
  if duplicate_members(@text.read_ion(source[:])) {
    return Some(invalid(field(request, "id"), "workbench.invalid_request"))
  }
  if exit_requested(request) {
    None
  } else {
    Some(handle(request))
  }
}

///|
/// The shared MCK transport sends exit and expects EOF without a response.
pub fn exit_requested(request : Json) -> Bool {
  request is Object(fields) &&
  fields.length() == 2 &&
  valid_id(field(request, "id")) &&
  field(request, "op") == Json::string("exit")
}

///|
/// Implements the parent's exact draft codec and declared-value observations.
/// These test claims do not advertise connected RPC or job execution.
pub fn handle(request : Json) -> Json {
  let id = field(request, "id")
  guard request is Object(fields) else {
    return invalid(id, "workbench.invalid_request")
  }
  guard valid_id(id) else { return invalid(id, "workbench.invalid_request") }
  let op = field(request, "op")
  let allowed = if op == Json::string("capabilities") {
    ["id", "op", "suite", "contractVersion"]
  } else {
    ["id", "op", "suite", "contractVersion", "format", "input"]
  }
  let version = field(request, "contractVersion")
  let draft2 = version == Json::string("0.1.0-draft.2")
  guard fields.length() == allowed.length() &&
    fields.keys().all(name => allowed.contains(name)) &&
    field(request, "suite") == Json::string("workbench") &&
    (version == Json::string("0.1.0-draft.1") || draft2) else {
    return invalid(id, "workbench.invalid_request")
  }
  if op == Json::string("capabilities") {
    return {
      "id": id,
      "suite": "workbench",
      "contractVersion": version,
      "binding": "morphir-moonbit",
      "language": "moonbit",
      "operations": if draft2 {
        ["decode-value", "validate-value"]
      } else {
        ["decode-value"]
      },
      "formats": ["json", "ion-text"],
    }
  }
  guard op == Json::string("decode-value") ||
    (draft2 && op == Json::string("validate-value")) else {
    return invalid(id, "workbench.invalid_request")
  }
  try {
    let input = field(request, "input")
    if draft2 && @utf8.encode(input.stringify()).length() > 1024 * 1024 {
      return invalid(id, "workbench.input_limit")
    }
    let value = if op == Json::string("validate-value") {
      admit_value(input, field(request, "format"))
    } else {
      decode_value(field(request, "format"), input)
    }
    { "id": id, "status": "ok", "value": value.to_json() }
  } catch {
    @execution.Invalid(code) => {
      // Legacy codec diagnostics append input paths/names after a colon.
      // The MCK observation carries only the bounded, stable rejection code.
      let stable = code.split(":").next().unwrap_or("workbench.codec_failure")
      invalid(id, stable.to_owned())
    }
    _ => invalid(id, "workbench.codec_failure")
  }
}

///|
fn decode_value(format : Json, input : Json) -> @execution.Value raise {
  match format {
    String("json") => @execution.Value::from_json(input)
    String("ion-text") => {
      guard input is String(source) else {
        raise @execution.Invalid("workbench.invalid_request")
      }
      let ion = @text.read_ion(source[:]) catch {
        _ => raise @execution.Invalid("workbench.invalid_ion")
      }
      @execution.Value::from_ion(ion)
    }
    _ => raise @execution.Invalid("workbench.invalid_request")
  }
}

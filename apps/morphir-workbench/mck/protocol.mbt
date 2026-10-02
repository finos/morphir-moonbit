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
/// Implements only the parent-owned draft's codec observation protocol.
/// Declared argument types and job execution are outside these capabilities.
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
  guard fields.length() == allowed.length() &&
    fields.keys().all(name => allowed.contains(name)) &&
    field(request, "suite") == Json::string("workbench") &&
    field(request, "contractVersion") == Json::string("0.1.0-draft.1") else {
    return invalid(id, "workbench.invalid_request")
  }
  if op == Json::string("capabilities") {
    return {
      "id": id,
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.1",
      "binding": "morphir-moonbit",
      "language": "moonbit",
      "operations": ["decode-value"],
      "formats": ["json", "ion-text"],
    }
  }
  guard op == Json::string("decode-value") else {
    return invalid(id, "workbench.invalid_request")
  }
  try {
    let value = match field(request, "format") {
      String("json") => @execution.Value::from_json(field(request, "input"))
      String("ion-text") => {
        guard field(request, "input") is String(source) else {
          return invalid(id, "workbench.invalid_request")
        }
        let ion = @text.read_ion(source[:]) catch {
          _ => return invalid(id, "workbench.invalid_ion")
        }
        @execution.Value::from_ion(ion)
      }
      _ => return invalid(id, "workbench.invalid_request")
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

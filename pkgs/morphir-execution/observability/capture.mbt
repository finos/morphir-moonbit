///|
/// Embedding hosts configure payload capture independently of diagnostic logging.
/// Redaction runs before any record reaches the capture sink.
pub(all) struct PayloadCapture {
  enabled : Bool
  redact : (String, @execution.Value) -> Json? raise
  try_record : (Json) -> Delivery raise
}

///|
pub fn PayloadCapture::disabled() -> PayloadCapture {
  { enabled: false, redact: fn(_, _) { None }, try_record: fn(_) { Filtered }, }
}

///|
pub fn PayloadCapture::record(
  self : PayloadCapture,
  call : @execution.Call,
  actual : @execution.Value,
) -> Delivery {
  if !self.enabled {
    return Filtered
  }
  try {
    let arguments = call.arguments.map(v => {
      (self.redact)(call.entry, @execution.Value::from_ion(v.to_ion())).unwrap_or(
        Json::null(),
      )
    })
    let result = (self.redact)(
      call.entry,
      @execution.Value::from_ion(actual.to_ion()),
    ).unwrap_or(Json::null())
    let packet : Json = {
      "profile": "morphir-redacted-payload-v1",
      "entry": call.entry,
      "call_id": call.id,
      "arguments": arguments,
      "result": result,
    }
    if @utf8.encode(packet.stringify()).length() > 16384 {
      return Dropped
    }
    (self.try_record)(packet)
  } catch {
    _ => Unavailable
  }
}

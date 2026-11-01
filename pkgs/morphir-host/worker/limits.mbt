///|
/// Bounds on one model transfer. The host enforces the encoded and decoded
/// byte limits, and checks the decoded length that a payload declares. The
/// depth and node limits are negotiated; the party that decodes the model
/// enforces them.
pub struct ModelLimits {
  encoded_bytes : Int32
  decoded_bytes : Int32
  depth : Int32
  nodes : Int32
} derive(Eq, Debug)

///|
pub extend ModelLimits with Eq::{equal, not_equal}

///|
pub extend ModelLimits with @debug.Debug::{to_repr}

///|
fn positive(name : String, value : Int32) -> Int32 raise ValueError {
  guard value > 0 else { raise InvalidLimit("\{name}=\{value}") }
  value
}

///|
pub fn ModelLimits::new(
  encoded_bytes~ : Int32,
  decoded_bytes~ : Int32,
  depth~ : Int32,
  nodes~ : Int32,
) -> ModelLimits raise ValueError {
  {
    encoded_bytes: positive("encoded_bytes", encoded_bytes),
    decoded_bytes: positive("decoded_bytes", decoded_bytes),
    depth: positive("depth", depth),
    nodes: positive("nodes", nodes),
  }
}

///|
/// Bounds on the messages of one session.
pub struct Limits {
  request_bytes : Int32
  response_bytes : Int32
  model : ModelLimits
} derive(Eq, Debug)

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub fn Limits::new(
  request_bytes~ : Int32,
  response_bytes~ : Int32,
  model~ : ModelLimits,
) -> Limits raise ValueError {
  {
    request_bytes: positive("request_bytes", request_bytes),
    response_bytes: positive("response_bytes", response_bytes),
    model,
  }
}

///|
/// The largest framed request of a call that carries no model payload: a compile
/// call, or any call of a MEP 0.1 session. A guest on MEP 0.1 has this bound on
/// every runtime.
let call_frame_bytes : Int32 = 4 * 1024 * 1024

///|
/// The host's own limits: a 6 MiB framed request, a 16 MiB response and model
/// limits of 4 MiB decoded, 5,592,408 encoded bytes, depth 128 and 100,000
/// nodes.
///
/// The encoded limit is 4 * ceil(4194304 / 3), the base64 length of the decoded
/// limit. The frame must hold that and the envelope, the method and the other
/// parameters, about 1 KiB for a plain IR file. The 6 MiB frame leaves 699,048
/// bytes for them. Only a generate call on the model line uses a frame over
/// `call_frame_bytes`.
pub fn Limits::host() -> Limits {
  {
    request_bytes: 6 * 1024 * 1024,
    response_bytes: 16 * 1024 * 1024,
    model: {
      encoded_bytes: 5592408,
      decoded_bytes: 4 * 1024 * 1024,
      depth: 128,
      nodes: 100000,
    },
  }
}

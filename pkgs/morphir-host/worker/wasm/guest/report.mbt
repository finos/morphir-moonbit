///|
/// The command name of the worker mode in its reports.
pub let worker_command : String = "extension worker"

///|
/// One event of the worker mode's report on stderr. With `--json` each event
/// is one `morphir/command-event` line; the host reads the last `fault` or
/// `refused` event when the worker's stdout ends.
pub(all) enum WorkerEvent {
  /// The worker loaded the module and serves frames.
  Started(
    abi~ : @worker.WasmAbi,
    module_sha256~ : @worker.Sha256,
    build_identity~ : String,
    bounds~ : @worker.EnforcedBounds
  )
  /// The guest wrote or logged something.
  Output(GuestOutput)
  /// The guest stopped serving for a fault.
  Fault(@worker.GuestFault)
  /// The worker refused to serve before any request.
  Refused(code~ : @worker.RefusalCode, message~ : String)
  /// The worker exits with this status.
  Exited(code~ : Int32)
} derive(Eq, Debug)

///|
pub extend WorkerEvent with Eq::{equal, not_equal}

///|
pub extend WorkerEvent with @debug.Debug::{to_repr}

///|
fn fault_kind(fault : @worker.GuestFault) -> (String, String?) {
  match fault {
    Trap(text) => ("trap", Some(text))
    MemoryLimit(text) => ("memory-limit", Some(text))
    CallDeadline => ("call-deadline", None)
    BudgetExhausted => ("budget-exhausted", None)
    Failure(text) => ("failure", Some(text))
  }
}

///|
fn fault_of(kind : String, message : String) -> @worker.GuestFault? {
  match kind {
    "trap" => Some(Trap(message))
    "memory-limit" => Some(MemoryLimit(message))
    "call-deadline" => Some(CallDeadline)
    "budget-exhausted" => Some(BudgetExhausted)
    "failure" => Some(Failure(message))
    _ => None
  }
}

///|
/// The refusal codes that a worker reports.
let refusal_codes : Array[@worker.RefusalCode] = [
  WorkerRuntimeMismatch,
  AbiUnsupported,
  AbiMismatch,
  WasmFeatureUnsupported,
  RequestLimit,
]

///|
/// The event as one `morphir/command-event` value with its sequence number.
pub fn WorkerEvent::to_json(self : WorkerEvent, sequence~ : Int32) -> Json {
  let fields : Map[String, Json] = {
    "profile": "morphir/command-event",
    "contractVersion": "0.1.0",
    "command": worker_command,
    "sequence": sequence,
  }
  match self {
    Started(abi~, module_sha256~, build_identity~, bounds~) => {
      fields["event"] = "started"
      fields["abi"] = Json(abi.to_string())
      fields["moduleSha256"] = Json(module_sha256.to_string())
      fields["buildIdentity"] = Json(build_identity)
      fields["bounds"] = Json(bounds)
    }
    Output(output) => {
      fields["event"] = "output"
      fields["output"] = Json(output.to_string())
    }
    Fault(fault) => {
      let (kind, message) = fault_kind(fault)
      let detail : Map[String, Json] = { "kind": Json(kind) }
      if message is Some(text) {
        detail["message"] = Json(text)
      }
      fields["event"] = "fault"
      fields["fault"] = Json::object(detail)
    }
    Refused(code~, message~) => {
      fields["event"] = "refused"
      fields["error"] = { "code": code.to_string(), "message": message }
    }
    Exited(code~) => {
      fields["event"] = "exited"
      fields["exitCode"] = Json(code)
    }
  }
  Json::object(fields)
}

///|
/// The event as one line of text, for the default report.
pub fn WorkerEvent::to_text(self : WorkerEvent) -> String {
  let prefix = "morphir \{worker_command}: "
  prefix +
  (match self {
    Started(abi~, module_sha256~, ..) =>
      "serving \{abi} module \{module_sha256}"
    Output(output) => output.to_string()
    Fault(fault) => {
      let (kind, message) = fault_kind(fault)
      "fault \{kind}" + message.map(text => ": \{text}").unwrap_or("")
    }
    Refused(code~, message~) => "refused \{code}: \{message}"
    Exited(code~) => "exit \{code}"
  })
}

///|
/// The channel error for the last `fault` or `refused` event in a worker's
/// stderr, or `None` when it has neither. Lines that are not report events,
/// such as a line cut at the start of a stderr tail, are skipped.
pub fn WorkerEvent::ending_in(stderr : Bytes) -> @worker.ChannelError? {
  let lines = @utf8.decode_lossy(stderr).split("\n").to_array()
  for index = lines.length() - 1; index >= 0; index = index - 1 {
    let event = @json.parse(lines[index]) catch { _ => continue }
    guard event
      is {
        "profile": "morphir/command-event",
        "command": String(command),
        "event": String(name),
        ..
      } &&
      command == worker_command else {
      continue
    }
    match (name, event) {
      ("fault", { "fault": { "kind": String(kind), .. } as detail, .. }) => {
        let message = match detail {
          { "message": String(text), .. } => text
          _ => ""
        }
        if fault_of(kind, message) is Some(fault) {
          return Some(GuestFailed(fault))
        }
      }
      (
        "refused",
        {
          "error": { "code": String(code), "message": String(message), .. },
          ..
        },
      ) =>
        for known in refusal_codes {
          if known.to_string() == code {
            return Some(Refused(code=known, message~))
          }
        }
      _ => ()
    }
  }
  None
}

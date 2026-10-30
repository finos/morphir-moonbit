///|
/// The host's failure and refusal codes.
pub(all) enum FailureCode {
  IncompleteSession
  FrameInvalid
  UnexpectedResponse
  ResponseLimit
  RequestLimit
  ProtocolUnavailable
  TupleUnavailable
  DescribeFailed
  ClaimsMismatch
  CapabilityUnavailable
  PlatformMismatch
  RuntimeUnavailable
  DigestMismatch
  AbiUnsupported
  AbiMismatch
  WasmFeatureUnsupported
  MemoryLimit
  GuestTrap
  TreeTerminationFailed
} derive(Eq, Debug)

///|
pub extend FailureCode with Eq::{equal, not_equal}

///|
pub extend FailureCode with @debug.Debug::{to_repr}

///|
pub impl Show for FailureCode with fn output(self, logger) {
  logger.write_string(
    match self {
      IncompleteSession => "extension.incomplete_session"
      FrameInvalid => "extension.frame_invalid"
      UnexpectedResponse => "extension.unexpected_response"
      ResponseLimit => "extension.response_limit"
      RequestLimit => "extension.request_limit"
      ProtocolUnavailable => "extension.protocol_unavailable"
      TupleUnavailable => "extension.tuple_unavailable"
      DescribeFailed => "extension.describe_failed"
      ClaimsMismatch => "extension.claims_mismatch"
      CapabilityUnavailable => "extension.capability_unavailable"
      PlatformMismatch => "extension.platform_mismatch"
      RuntimeUnavailable => "extension.runtime_unavailable"
      DigestMismatch => "extension.digest_mismatch"
      AbiUnsupported => "extension.abi_unsupported"
      AbiMismatch => "extension.abi_mismatch"
      WasmFeatureUnsupported => "extension.wasm_feature_unsupported"
      MemoryLimit => "extension.memory_limit"
      GuestTrap => "extension.guest_trap"
      TreeTerminationFailed => "execution.tree_termination_failed"
    },
  )
}

///|
pub extend FailureCode with Show::{to_string, output}

///|
/// Why a session did not complete: a host check, or a JSON-RPC error that the
/// guest returned.
pub(all) enum Failure {
  Host(code~ : FailureCode, message~ : String)
  Guest(code~ : Int32, message~ : String)
} derive(Eq, Debug)

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub extend Failure with @debug.Debug::{to_repr}

///|
let stderr_tail_bytes : Int32 = 65536

///|
/// The last 64 KiB of a worker's stderr, kept as diagnostics.
pub struct StderrTail {
  priv data : Bytes
} derive(Eq, Debug)

///|
pub extend StderrTail with Eq::{equal, not_equal}

///|
pub extend StderrTail with @debug.Debug::{to_repr}

///|
pub fn StderrTail::empty() -> StderrTail {
  { data: b"", }
}

///|
pub fn StderrTail::of(bytes : Bytes) -> StderrTail {
  let start = @cmp.maximum(0, bytes.length() - stderr_tail_bytes)
  { data: bytes[start:].to_owned(), }
}

///|
pub fn StderrTail::bytes(self : StderrTail) -> Bytes {
  self.data
}

///|
/// The class of a finished session. `Unsuccessful` is a guest answer with
/// `success: false`; `Refused` is a check that failed before any operation.
pub(all) enum OutcomeClass[T] {
  Completed(T)
  Unsuccessful
  Failed(Failure)
  Refused(Failure)
  Deadline
  Cancelled
} derive(Eq, Debug)

///|
pub extend OutcomeClass with Eq::{equal, not_equal}

///|
pub extend OutcomeClass with @debug.Debug::{to_repr}

///|
/// A session result. Every class keeps the guest's diagnostics and stderr tail.
pub struct Outcome[T] {
  class : OutcomeClass[T]
  diagnostics : Array[Json]
  stderr : StderrTail
} derive(Eq, Debug)

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend Outcome with @debug.Debug::{to_repr}

///|
pub fn[T] Outcome::new(
  class : OutcomeClass[T],
  diagnostics~ : Array[Json],
  stderr~ : StderrTail,
) -> Outcome[T] {
  { class, diagnostics, stderr, }
}

///|
/// One whole MEP message and its size in bytes, as encoded or as read.
/// Framing belongs to the transport; the session core checks the size again.
pub struct Message {
  priv body : Json
  priv bytes : Int32
} derive(Eq, Debug)

///|
pub extend Message with Eq::{equal, not_equal}

///|
pub extend Message with @debug.Debug::{to_repr}

///|
pub fn Message::new(body : Json) -> Message {
  { body, bytes: @utf8.encode(body.stringify()).length(), }
}

///|
/// Decodes one message body that a transport has read in full.
pub fn Message::parse(bytes : Bytes) -> Message raise ChannelError {
  let text = @utf8.decode(bytes) catch {
    _ => raise FrameInvalid("message is not UTF-8")
  }
  let body = @json.parse(text) catch {
    _ => raise FrameInvalid("message is not JSON")
  }
  { body, bytes: bytes.length(), }
}

///|
pub fn Message::json(self : Message) -> Json {
  self.body
}

///|
pub fn Message::size(self : Message) -> Int32 {
  self.bytes
}

///|
pub fn Message::to_bytes(self : Message) -> Bytes {
  @utf8.encode(self.body.stringify())
}

///|
/// A transport fault. `WorkerClosed` is the end of the worker's stream;
/// `Stopped` is a call on a channel that the host has already closed or
/// aborted.
pub(all) suberror ChannelError {
  WorkerClosed
  FrameInvalid(String)
  FrameLimit(declared~ : Int32, limit~ : Int32)
  Stopped
} derive(Eq, Debug)

///|
pub extend ChannelError with Eq::{equal, not_equal}

///|
pub extend ChannelError with @debug.Debug::{to_repr}

///|
/// Why the host stops a worker without waiting for it.
pub(all) enum StopReason {
  GraceExpired
  Deadline
  Cancelled
  Fault
} derive(Eq, Debug)

///|
pub extend StopReason with Eq::{equal, not_equal}

///|
pub extend StopReason with @debug.Debug::{to_repr}

///|
/// How a worker stopped. `Unconfirmed` means the host could not confirm that
/// the worker's process tree stopped.
pub(all) enum WorkerStop {
  Exited(code~ : Int32?)
  Terminated(StopReason)
  Unconfirmed(StopReason)
} derive(Eq, Debug)

///|
pub extend WorkerStop with Eq::{equal, not_equal}

///|
pub extend WorkerStop with @debug.Debug::{to_repr}

///|
/// Whole MEP messages between the host and one worker. `close` follows `exit`:
/// it waits for the grace period, then stops the worker's tree and confirms.
/// `abort` stops the tree at once. Both return the first stop on later calls.
pub(open) trait Channel {
  async fn send(Self, Message) -> Unit raise ChannelError
  async fn receive(Self) -> Message raise ChannelError
  async fn close(Self) -> WorkerStop
  async fn abort(Self, StopReason) -> WorkerStop
}

///|
/// A launcher could not start a worker.
pub(all) suberror LaunchError {
  PlatformMismatch(Platform)
  RuntimeUnavailable(WorkerRuntime)
  LaunchFailed(String)
} derive(Eq, Debug)

///|
pub extend LaunchError with Eq::{equal, not_equal}

///|
pub extend LaunchError with @debug.Debug::{to_repr}

///|
/// Starts a worker from a specification and returns its channel.
pub(open) trait Launcher {
  async fn launch(Self, WorkerSpec) -> &Channel raise LaunchError
}

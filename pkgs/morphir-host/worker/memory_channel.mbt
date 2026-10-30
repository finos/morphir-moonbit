///|
priv struct Link {
  to_worker : @aqueue.Queue[Message]
  to_host : @aqueue.Queue[Message]
  exits : @aqueue.Queue[Int32?]
  grace_ms : Int32
  mut exited : Int32??
  mut stop : WorkerStop?
}

///|
/// The host end of an in-memory channel, for tests and fake workers.
pub struct MemoryChannel {
  priv link : Link
}

///|
/// The worker end of an in-memory channel.
pub struct MemoryWorker {
  priv link : Link
}

///|
/// A connected host end and worker end. `close` waits `grace_ms` for the
/// worker to exit.
pub fn MemoryChannel::pair(
  grace_ms~ : Int32 = 2000,
) -> (MemoryChannel, MemoryWorker) {
  let link = {
    to_worker: @aqueue.Queue(kind=Unbounded),
    to_host: @aqueue.Queue(kind=Unbounded),
    exits: @aqueue.Queue(kind=Unbounded),
    grace_ms,
    exited: None,
    stop: None,
  }
  ({ link, }, { link, })
}

///|
fn Link::stopped(self : Link, stop : WorkerStop) -> WorkerStop {
  self.stop = Some(stop)
  self.to_worker.close(clear=true)
  self.to_host.close(clear=true)
  stop
}

///|
pub extend MemoryChannel with Channel::{send, receive, close, abort}

///|
pub impl Channel for MemoryChannel with fn send(self, message) {
  let link = self.link
  guard link.stop is None else { raise Stopped }
  guard link.exited is None else { raise WorkerClosed }
  link.to_worker.put(message) catch {
    _ => raise WorkerClosed
  }
}

///|
pub impl Channel for MemoryChannel with fn receive(self) {
  let link = self.link
  guard link.stop is None else { raise Stopped }
  link.to_host.get() catch {
    _ => raise if link.stop is None { WorkerClosed } else { Stopped }
  }
}

///|
pub impl Channel for MemoryChannel with fn close(self) {
  let link = self.link
  if link.stop is Some(stop) {
    return stop
  }
  link.to_worker.close()
  let exited = match link.exited {
    Some(code) => Some(code)
    None =>
      @async.with_timeout_opt(link.grace_ms, () => link.exits.get()) catch {
        _ => None
      }
  }
  link.stopped(
    match exited {
      Some(code) => Exited(code~)
      None => Terminated(GraceExpired)
    },
  )
}

///|
pub impl Channel for MemoryChannel with fn abort(self, reason) {
  let link = self.link
  match (link.stop, link.exited) {
    (Some(stop), _) => stop
    (None, Some(code)) => link.stopped(Exited(code~))
    (None, None) => link.stopped(Terminated(reason))
  }
}

///|
/// Reads the host's next message. The end of the host's input raises
/// `WorkerClosed`.
pub async fn MemoryWorker::receive(
  self : MemoryWorker,
) -> Message raise ChannelError {
  self.link.to_worker.get() catch {
    _ => raise WorkerClosed
  }
}

///|
pub async fn MemoryWorker::send(
  self : MemoryWorker,
  message : Message,
) -> Unit raise ChannelError {
  let link = self.link
  guard link.stop is None && link.exited is None else { raise Stopped }
  link.to_host.put(message) catch {
    _ => raise Stopped
  }
}

///|
/// Ends the worker. The host reads the messages sent before the exit, then
/// the end of the stream.
pub fn MemoryWorker::exit(self : MemoryWorker, code? : Int32) -> Unit {
  let link = self.link
  guard link.exited is None else { return }
  link.exited = Some(code)
  link.to_host.close()
  let _ = link.exits.try_put(code) catch { _ => false }
}

///|
/// A launcher that hands out one prepared in-memory channel.
pub struct MemoryLauncher {
  priv mut channel : MemoryChannel?
}

///|
pub fn MemoryLauncher::new(channel : MemoryChannel) -> MemoryLauncher {
  { channel: Some(channel), }
}

///|
pub extend MemoryLauncher with Launcher::{launch}

///|
pub impl Launcher for MemoryLauncher with fn launch(self, _spec) {
  guard self.channel is Some(channel) else {
    raise LaunchFailed("the in-memory channel is already in use")
  }
  self.channel = None
  channel
}

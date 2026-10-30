///|
/// A process worker that Node's `child_process` runs. It owns the worker's
/// tree: a process group on Unix, the root's tree on Windows.
pub struct NodeProcessChannel {
  priv child : Child
  priv pid : Int32
  priv tree : Tree
  priv directory : String
  priv stdout : @js_async.ReadableStream
  priv reader : @process.FrameReader
  priv writer : @process.FrameWriter
  priv pending : @deque.Deque[@worker.Message]
  priv stderr : @process.StderrBuffer
  /// Abort reasons that reach a `close` waiting for the grace period.
  priv aborts : @aqueue.Queue[@worker.StopReason]
  priv stopped : @async.CondVar
  priv mut stopping : Bool
  priv mut stop : @worker.WorkerStop?
}

///|
/// Starts the staged artifact with the argument array, unchanged, in its
/// empty private working directory. The channel owns the staged directory
/// from now on and checks frames against `limits`.
pub async fn NodeProcessChannel::start(
  staged : @process.StagedArtifact,
  args : Array[String],
  limits~ : @worker.Limits = @worker.Limits::host(),
) -> NodeProcessChannel {
  let directory = staged.directory()
  let stderr = @process.StderrBuffer::new()
  let child = Child::spawn(
    staged.executable(),
    FixedArray::from_array(args),
    staged.working_directory(),
    chunk => stderr.write(chunk),
  ).wait() catch {
    error => {
      remove_directory(directory)
      raise @worker.LaunchFailed("cannot start the worker: \{error}")
    }
  }
  {
    child,
    pid: child.pid(),
    tree: Tree::host(),
    directory,
    stdout: @js_async.ReadableStream::from_js(child.stdout()),
    reader: @process.FrameReader::new(limit=limits.response_bytes),
    writer: @process.FrameWriter::new(limit=limits.request_bytes),
    pending: @deque.Deque([]),
    stderr,
    aborts: @aqueue.Queue(kind=Unbounded),
    stopped: @async.CondVar::Cond(),
    stopping: false,
    stop: None,
  }
}

///|
/// The exit status, once the `exit` event has arrived.
fn Child::status(self : Child) -> @worker.StopStatus? {
  match (self.exit_code(), self.exit_signal()) {
    (code, _) if code >= 0 => Some(Exited(code~))
    (_, signal) if signal > 0 => Some(Signalled(signal~))
    _ => None
  }
}

///|
async fn NodeProcessChannel::wait_exit(self : NodeProcessChannel) -> Unit {
  @js_async.run_promise(signal => self.child.exited(signal))
}

///|
/// Waits at most `bound` ms for the worker's exit. Returns whether it exited.
async fn NodeProcessChannel::exits_within(
  self : NodeProcessChannel,
  bound : Int32,
) -> Bool {
  @async.with_timeout_opt(bound, () => self.wait_exit()) is Some(_)
}

///|
/// Signals the worker's process group and confirms that it is empty.
async fn NodeProcessChannel::stop_group(
  self : NodeProcessChannel,
  before : @worker.StopStatus?,
) -> TreeAction {
  let present = group_present(self.pid)
  if !present && before is Some(_) {
    return NotNeeded
  }
  if present {
    ignore(signal_group(self.pid))
  }
  let started = @async.now()
  guard self.exits_within(@process.STOP_CONFIRM_MS) else { return Unconfirmed }
  // The group outlives its leader while a descendant or a zombie remains.
  while group_present(self.pid) {
    guard @async.now() - started < @process.STOP_CONFIRM_MS.to_int64() else {
      return Unconfirmed
    }
    @async.sleep(10)
  }
  if present {
    Stopped
  } else {
    NotNeeded
  }
}

///|
/// Stops the worker's tree with `taskkill /T /F` and confirms that the root
/// has exited. After the root has exited, `taskkill` cannot reach its tree.
async fn NodeProcessChannel::stop_root(
  self : NodeProcessChannel,
  before : @worker.StopStatus?,
) -> TreeAction {
  if before is Some(_) {
    return NotNeeded
  }
  ignore(
    @async.with_timeout_opt(@process.STOP_CONFIRM_MS, () => {
      @js_async.run_promise(signal => kill_tree(self.pid, signal))
    }) catch {
      _ => None
    },
  )
  if self.exits_within(@process.STOP_CONFIRM_MS) {
    Stopped
  } else {
    Unconfirmed
  }
}

///|
/// Stops the tree, records the first stop and wakes every waiter. The host
/// removes the private directory only after it confirms the stop.
async fn NodeProcessChannel::stop_tree(
  self : NodeProcessChannel,
  reason : @worker.StopReason,
) -> @worker.WorkerStop {
  let before = self.child.status()
  let action = match self.tree {
    Group => self.stop_group(before)
    RootTree => self.stop_root(before)
  }
  if action != Unconfirmed {
    // The stopped tree no longer holds stderr open; take its last bytes.
    ignore(
      @async.with_timeout_opt(1000, () => {
        @js_async.run_promise(signal => self.child.stderr_closed(signal))
      }) catch {
        _ => None
      },
    )
    remove_directory(self.directory)
  } else {
    // The tree may still run; it must not keep the host alive.
    self.child.release()
  }
  let (status, stop_method) = stop_result(
    self.tree,
    reason,
    action,
    before~,
    after=self.child.status(),
  )
  let stop = @worker.WorkerStop::new(
    status,
    stop_method~,
    stderr=self.stderr.tail(),
  )
  self.stop = Some(stop)
  self.stdout.close()
  self.aborts.close()
  self.stopped.broadcast()
  stop
}

///|
/// Waits for the stop that another call has started.
async fn NodeProcessChannel::wait_stop(
  self : NodeProcessChannel,
) -> @worker.WorkerStop {
  @async.protect_from_cancel(() => {
    while self.stop is None {
      self.stopped.wait()
    }
    self.stop.unwrap()
  })
}

///|
pub extend NodeProcessChannel with @worker.Channel::{
  send,
  receive,
  close,
  abort,
}

///|
pub impl @worker.Channel for NodeProcessChannel with fn send(self, message) {
  guard self.stop is None else { raise @worker.Stopped }
  let frame = self.writer.encode(message)
  @js_async.run_promise(signal => self.child.write(frame, signal)) catch {
    _ => raise if self.stop is None { @worker.WorkerClosed } else { Stopped }
  }
}

///|
pub impl @worker.Channel for NodeProcessChannel with fn receive(self) {
  guard self.stop is None else { raise @worker.Stopped }
  while self.pending.is_empty() {
    // A read error ends the stream like the end of input.
    let chunk = self.stdout.read_some() catch { _ => None }
    guard self.stop is None else { raise @worker.Stopped }
    guard chunk is Some(bytes) else {
      self.reader.finish()
      raise @worker.WorkerClosed
    }
    for message in self.reader.feed(bytes) {
      self.pending.push_back(message)
    }
  }
  self.pending.pop_front().unwrap()
}

///|
pub impl @worker.Channel for NodeProcessChannel with fn close(self) {
  if self.stop is Some(stop) {
    return stop
  }
  if self.stopping {
    return self.wait_stop()
  }
  self.stopping = true
  @async.protect_from_cancel(() => {
    self.child.end_input()
    let woken = @async.with_timeout_opt(@process.EXIT_GRACE_MS, () => {
      @async.any([
        () => {
          self.wait_exit()
          None
        },
        () => Some(self.aborts.get()),
      ])
    }) catch {
      _ => None
    }
    // An abort during the wait wins; otherwise the grace has passed or the
    // worker has exited, and `stop_tree` sees its exit.
    let reason : @worker.StopReason = match woken {
      Some(Some(reason)) => reason
      _ => GraceExpired
    }
    self.stop_tree(reason)
  })
}

///|
pub impl @worker.Channel for NodeProcessChannel with fn abort(self, reason) {
  if self.stop is Some(stop) {
    return stop
  }
  if self.stopping {
    ignore(self.aborts.try_put(reason) catch { _ => false })
    return self.wait_stop()
  }
  self.stopping = true
  @async.protect_from_cancel(() => self.stop_tree(reason))
}

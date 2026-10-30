///|
fn request(id : Int32) -> @worker.Message {
  @worker.Message::new({ "jsonrpc": "2.0", "id": id, "method": "morphir.ping" })
}

///|
test "a message records the size of its encoded JSON" {
  let message = @worker.Message::new({ "id": 1, "text": "é" })
  assert_eq(message.size(), message.to_bytes().length())
  assert_eq(@worker.Message::parse(message.to_bytes()).json(), message.json())
  for bytes in [b"{", b"\xff\xfe"] {
    guard (Ok(@worker.Message::parse(bytes)) catch { e => Err(e) })
      is Err(FrameInvalid(_)) else {
      fail("accepted a malformed message")
    }
  }
}

///|
async test "messages arrive in the order they were sent" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  channel.send(request(1))
  channel.send(request(2))
  assert_eq(worker.receive().json(), request(1).json())
  assert_eq(worker.receive().json(), request(2).json())
  worker.send(request(3))
  worker.send(request(4))
  assert_eq(channel.receive().json(), request(3).json())
  assert_eq(channel.receive().json(), request(4).json())
}

///|
async test "a receive waits for the peer" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let message = worker.receive()
      worker.send(message)
    })
    channel.send(request(7))
    assert_eq(channel.receive().json(), request(7).json())
  })
}

///|
async test "a worker that exits ends the stream after its last message" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  worker.send(request(1))
  worker.exit(code=0)
  assert_eq(channel.receive().json(), request(1).json())
  guard (Ok(channel.receive()) catch { e => Err(e) }) is Err(WorkerClosed) else {
    fail("read past the end of the stream")
  }
  guard (Ok(channel.send(request(2))) catch { e => Err(e) })
    is Err(WorkerClosed) else {
    fail("wrote to an exited worker")
  }
}

///|
async test "close waits for the worker to exit" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      guard (Ok(worker.receive()) catch { e => Err(e) }) is Err(WorkerClosed) else {
        fail("worker did not see the end of its input")
      }
      worker.exit(code=0)
    })
    assert_eq(channel.close(), Exited(code=Some(0)))
  })
  guard (Ok(channel.send(request(1))) catch { e => Err(e) }) is Err(Stopped) else {
    fail("sent on a closed channel")
  }
}

///|
async test "close stops a worker that ignores exit after the grace period" {
  let (channel, _worker) = @worker.MemoryChannel::pair(grace_ms=10)
  assert_eq(channel.close(), Terminated(GraceExpired))
}

///|
async test "abort stops the worker at once" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  channel.send(request(1))
  assert_eq(channel.abort(Deadline), Terminated(Deadline))
  guard (Ok(channel.receive()) catch { e => Err(e) }) is Err(Stopped) else {
    fail("received after abort")
  }
  guard (Ok(worker.receive()) catch { e => Err(e) }) is Err(WorkerClosed) else {
    fail("worker kept its input after abort")
  }
  guard (Ok(worker.send(request(2))) catch { e => Err(e) }) is Err(Stopped) else {
    fail("an aborted worker could still send")
  }
  // A second stop reports the first one.
  assert_eq(channel.close(), Terminated(Deadline))
}

///|
async test "a launcher returns a channel for a specification" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let launcher = @worker.MemoryLauncher::new(channel)
  let spec = @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(
      @worker.ArtifactPath::parse("/opt/morphir/guest.wasm"),
      @worker.Sha256::of(b"guest"),
    ),
    Wasm(abi=Some(MorphirBytesV1)),
  )
  let launched : &@worker.Channel = launcher.launch(spec)
  launched.send(request(5))
  assert_eq(worker.receive().json(), request(5).json())
  guard (Ok(launcher.launch(spec)) catch { e => Err(e) })
    is Err(LaunchFailed(_)) else {
    fail("launched a second worker from one channel")
  }
}

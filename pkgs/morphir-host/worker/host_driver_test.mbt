///|
/// A launcher that records each specification and hands out one channel.
struct RecordingLauncher {
  channel : @worker.MemoryChannel
  specs : Array[@worker.WorkerSpec]
}

///|
impl @worker.Launcher for RecordingLauncher with fn launch(self, spec) {
  self.specs.push(spec)
  self.channel
}

///|
fn process_spec(
  platform~ : @worker.Platform = Aarch64AppleDarwin,
) -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(
      File(@worker.ArtifactPath::parse("/stage/elm", Posix)),
      @worker.Sha256::parse(digest),
    ),
    Process(platform~, args=["serve"]),
  ) catch {
    _ => abort("invalid test specification")
  }
}

///|
fn wasm_spec() -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(b"\x00asm"), @worker.Sha256::of(b"\x00asm")),
    Wasm(abi=Some(ExtismKernelV1)),
  )
}

///|
/// A fake worker. It records every message, answers each request with
/// `reply`, stays silent when `reply` gives `None`, and exits on `exit`.
async fn serve(
  worker : @worker.MemoryWorker,
  received : Array[Json],
  reply : (String) -> Json?,
) -> Unit {
  while true {
    let message = worker.receive() catch { _ => return }
    received.push(message.json())
    guard message.json() is Object({ "method": String(name), .. } as fields) else {
      continue
    }
    if name == "morphir.exit" {
      worker.exit(code=0)
      return
    }
    if fields.get("id") is Some(Number(id, ..)) && reply(name) is Some(result) {
      worker.send(
        @worker.Message::new({ "jsonrpc": "2.0", "id": id, "result": result }),
      )
    }
  }
}

///|
fn received_methods(received : Array[Json]) -> Array[String] {
  received.map(message => {
    match message {
      Object({ "method": String(name), .. }) => name
      _ => "?"
    }
  })
}

///|
/// A legacy guest that answers every request, and `silent` ones not at all.
fn legacy_guest(silent~ : String = "") -> (String) -> Json? {
  name => {
    match name {
      _ if name == silent => None
      "morphir.extension.describe" => Some(legacy_result())
      "morphir.initialize" => Some(legacy_result(protocol="0.1"))
      "morphir.shutdown" => Some({})
      _ => Some({ "success": true, "diagnostics": [] })
    }
  }
}

///|
fn host_error(error : Error) -> (@worker.Ending, @worker.SessionReport) {
  guard error is @worker.Ended(ending, report~) else {
    abort("not a host error")
  }
  (ending, report)
}

///|
async test "probe a staged artifact: the probe returns claims and the worker is gone" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(Aarch64AppleDarwin),
  )
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, received, legacy_guest()))
    let description = host.probe(process_spec())
    assert_eq(description.claims, legacy_claims())
  })
  assert_eq(received_methods(received), [
    "morphir.extension.describe", "morphir.exit",
  ])
  // The host stopped the worker: its channel takes no more messages.
  guard (Ok(channel.send(@worker.Message::new({}))) catch { e => Err(e) })
    is Err(@worker.Stopped) else {
    fail("the probe left the worker running")
  }
}

///|
async test "probe of a guest that does not describe: describe_failed and no claims" {
  for case in ["error", "exit"] {
    let (channel, worker) = @worker.MemoryChannel::pair()
    let host = @worker.Host::new(
      @worker.MemoryLauncher::new(channel),
      Native(Aarch64AppleDarwin),
    )
    let failure = @async.with_task_group(group => {
      group.spawn_bg(() => {
        let message = worker.receive()
        if case == "exit" {
          worker.exit(code=1)
          return
        }
        guard message.json() is Object({ "id": id, .. }) else { return }
        worker.send(
          @worker.Message::new({
            "jsonrpc": "2.0",
            "id": id,
            "error": { "code": -32601, "message": "Unknown MEP operation" },
          }),
        )
        ignore(worker.receive())
        worker.exit(code=0)
      })
      try host.probe(process_spec()) catch {
        error => Some(host_error(error))
      } noraise {
        _ => None
      }
    })
    guard failure is Some((Failed(Host(code=DescribeFailed, ..)), report)) else {
      fail("the \{case} probe did not fail with describe_failed")
    }
    assert_true(report.stop is Some(_))
  }
}

///|
async test "deadline: the worker is stopped, its stderr is kept and wire cancellation is not used" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(Aarch64AppleDarwin),
  )
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      worker.write_stderr(b"stuck in compile")
      serve(worker, received, legacy_guest(silent="morphir.frontend.compile"))
    })
    let session = host.activate(
      process_spec(),
      expected=legacy_claims(),
      offer=Legacy,
      deadline=@worker.Deadline::of_ms(200),
    )
    let outcome = session.compile(compile_request())
    assert_eq(outcome.class, Deadline)
    assert_true(outcome.stderr.bytes() == b"stuck in compile")
    let report = session.close()
    guard report.stop is Some(stop) else { fail("no worker stop") }
    assert_eq(stop.status, Terminated(Deadline))
    assert_eq(report.ending, Some(Deadline))
    guard report.to_json() is Object({ "wireCancellation": False, .. }) else {
      fail("the report does not say wireCancellation: false")
    }
  })
  assert_false(received_methods(received).contains("$/cancelRequest"))
}

///|
async test "caller cancels: a stop interrupts a pending receive and stops the worker" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Node(Aarch64AppleDarwin),
  )
  let stopping = Ref(false)
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      serve(worker, received, legacy_guest(silent="morphir.frontend.compile"))
    })
    let session = host.activate(
      process_spec(),
      expected=legacy_claims(),
      offer=Legacy,
      stop=@worker.StopSignal::new(() => stopping.val),
    )
    group.spawn_bg(() => {
      @async.sleep(30)
      stopping.val = true
    })
    let started = @async.now()
    let outcome = session.compile(compile_request())
    // The worker never answers; the stop, not the 60 s deadline, ended it.
    assert_true(@async.now() - started < 5000L)
    assert_eq(outcome.class, Cancelled)
    // The worker was stopped before the call returned.
    let report = session.close()
    guard report.stop is Some(stop) else { fail("no worker stop") }
    assert_eq(stop.status, Terminated(Cancelled))
  })
  assert_false(received_methods(received).contains("$/cancelRequest"))
}

///|
async test "browser host and a process artifact: runtime_unavailable and nothing starts" {
  let (channel, _worker) = @worker.MemoryChannel::pair()
  let launcher = { channel, specs: [], }
  let host = @worker.Host::new(launcher, Browser)
  assert_eq(host.runtimes(), [Wasm])
  assert_false(host.supports(process_spec().runtime))
  assert_true(host.supports(wasm_spec().runtime))
  let failure = try host.probe(process_spec()) catch {
    error => Some(host_error(error))
  } noraise {
    _ => None
  }
  guard failure is Some((Refused(code=RuntimeUnavailable, message~), report)) else {
    fail("a browser host accepted a process worker")
  }
  assert_true(message.contains("wasm"))
  assert_true(report.stop is None)
  assert_eq(launcher.specs.length(), 0)
}

///|
async test "platform mismatch: a process for another platform is refused and nothing starts" {
  let (channel, _worker) = @worker.MemoryChannel::pair()
  let launcher = { channel, specs: [], }
  let host = @worker.Host::new(launcher, Native(Aarch64AppleDarwin))
  let spec = process_spec(platform=X86_64UnknownLinuxGnu)
  assert_false(host.supports(spec.runtime))
  let failure = try
    host.activate(spec, expected=legacy_claims(), offer=Legacy)
  catch {
    error => Some(host_error(error))
  } noraise {
    _ => None
  }
  guard failure is Some((Refused(code=PlatformMismatch, ..), _)) else {
    fail("started a process for another platform")
  }
  assert_eq(launcher.specs.length(), 0)
}

///|
async test "specification from an installed catalog: the host starts it with the recorded arguments" {
  let entry : Json = {
    "artifact": {
      "path": "/home/u/.morphir/extensions/elm/elm",
      "sha256": digest,
    },
    "runtime": {
      "kind": "process",
      "platform": "aarch64-apple-darwin",
      "args": ["mep", "--", "", "--stdio"],
    },
  }
  let spec = @worker.WorkerSpec::from_json(entry, Posix)
  let (channel, worker) = @worker.MemoryChannel::pair()
  let launcher = { channel, specs: [], }
  let host = @worker.Host::new(launcher, Native(Aarch64AppleDarwin))
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, [], legacy_guest()))
    let session = host.activate(spec, expected=legacy_claims(), offer=Legacy)
    ignore(session.close())
  })
  assert_eq(launcher.specs, [spec])
  guard launcher.specs[0].runtime is Process(args~, ..) else {
    fail("not a process")
  }
  assert_eq(args, ["mep", "--", "", "--stdio"])
}

///|
async test "claims drift through the host: claims_mismatch, shutdown and exit, no operation" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(Aarch64AppleDarwin),
  )
  let received = []
  let failure = @async.with_task_group(group => {
    group.spawn_bg(() => {
      serve(worker, received, name => {
        match name {
          "morphir.initialize" =>
            Some(legacy_result(version="9.9.9", protocol="0.1"))
          _ => Some({})
        }
      })
    })
    try
      host.activate(process_spec(), expected=legacy_claims(), offer=Legacy)
    catch {
      error => Some(host_error(error))
    } noraise {
      _ => None
    }
  })
  guard failure is Some((Refused(code=ClaimsMismatch, ..), report)) else {
    fail("activation accepted drifted claims")
  }
  assert_eq(received_methods(received), [
    "morphir.initialize", "morphir.shutdown", "morphir.exit",
  ])
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.status, Exited(code=0))
}

///|
async test "the report states the limits that applied and how the worker stopped" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Node(Aarch64AppleDarwin),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, [], legacy_guest()))
    let session = host.activate(
      wasm_spec(),
      expected=legacy_claims(),
      offer=Legacy,
    )
    let outcome = session.compile(compile_request())
    assert_true(outcome.class is Completed(_))
    let report = session.close()
    assert_eq(report.extism, Some(@worker.ExtismProfile::restricted()))
    guard report.stop is Some(stop) else { fail("no worker stop") }
    assert_eq(stop.status, Exited(code=0))
    assert_eq(stop.stop_method, ExitedAfterExit)
    assert_true(report.ending is None)
    guard report.to_json()
      is Object(
        {
          "protocolVersion": String("0.1"),
          "limits": Object({ "requestBytes": _, "responseBytes": _, .. }),
          "extismProfile": Object(_),
          "wireCancellation": False,
          ..
        }
      ) else {
      fail("the report does not state the limits")
    }
    // A closed session gives the same report again and takes no calls.
    assert_eq(session.close(), report)
    let again = try session.compile(compile_request()) catch {
      @worker.SessionUnavailable(_) => None
      _ => Some("another error")
    } noraise {
      _ => Some("an outcome")
    }
    assert_true(again is None)
  })
}

///|
async test "same guest, two worker kinds: the host sends the same messages and returns the same result" {
  let run = async fn(spec : @worker.WorkerSpec) {
    let (channel, worker) = @worker.MemoryChannel::pair()
    let host = @worker.Host::new(
      @worker.MemoryLauncher::new(channel),
      Native(Aarch64AppleDarwin),
    )
    let received = []
    let outcome = @async.with_task_group(group => {
      group.spawn_bg(() => {
        serve(worker, received, name => {
          match name {
            "morphir.initialize" =>
              Some(model_result([ion_tuple], protocol="0.2.0-draft.1"))
            "morphir.shutdown" => Some({})
            _ => Some({ "success": true, "modules": ["main"] })
          }
        })
      })
      let session = host.activate(
        spec,
        expected=model_claims(),
        offer=Model(ion_tuple),
      )
      let outcome = session.compile(compile_request())
      ignore(session.close())
      outcome
    })
    (received, outcome)
  }
  let process = run(process_spec())
  let wasm = run(
    @worker.WorkerSpec::new(
      wasm_spec().artifact,
      Wasm(abi=Some(MorphirBytesV1)),
    ),
  )
  assert_eq(process, wasm)
  assert_true(process.1.class is Completed(_))
}

///|
/// The native CLI with the worker mode: MORPHIR_CLI names it. The
/// qualification builds it and sets the variable.
fn cli() -> String? {
  @env.get_env_var("MORPHIR_CLI")
}

///|
fn wasm_spec(bytes : Bytes, abi? : @worker.WasmAbi) -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(bytes), @worker.Sha256::of(bytes)),
    Wasm(abi~),
  )
}

///|
fn host(
  path : String,
  identity? : @native.BuildIdentity,
  call? : @guest.CallBounds,
) -> @worker.Host {
  let platform = @process.host_platform().unwrap()
  @worker.Host::new(
    @native.WasmProcessLauncher::new(executable=At(path), identity?, call?),
    Native(platform),
  )
}

///|
/// How a probe ended early, or `None` when it described the guest.
async fn probe_ending(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
  deadline? : @worker.Deadline,
) -> (@worker.Ending, @worker.SessionReport)? {
  try host.probe(spec, deadline?) catch {
    @worker.Ended(ending, report~) => Some((ending, report))
    error => abort("not a host error: \{@debug.to_string(error)}")
  } noraise {
    _ => None
  }
}

///|
async test "native WASM worker runtime: an Extism guest runs in a worker process of the CLI" {
  guard cli() is Some(path) else { return }
  // The echo guest answers describe with the request, which is not a
  // description: the probe fails after a full round trip through the
  // worker process.
  guard probe_ending(host(path), wasm_spec(@fixtures.extism_echo_guest()))
    is Some((ending, report)) else {
    fail("the echo guest described itself")
  }
  assert_true(ending is Failed(Host(..)))
  assert_eq(report.bounds, Some(@guest.engine_bounds()))
}

///|
async test "runaway guest: the call is stopped at its deadline and the worker is gone" {
  guard cli() is Some(path) else { return }
  let failure = probe_ending(
    host(path, call=@guest.CallBounds::new(deadline_ms=300, instructions=None)),
    wasm_spec(@fixtures.runaway_guest()),
    deadline=@worker.Deadline::of_ms(20000),
  )
  guard failure is Some((Deadline, report)) else {
    fail("a runaway guest did not end at its deadline")
  }
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_true(stop.status is Exited(code=1))
}

///|
async test "runaway guest: the session deadline stops the worker's process group" {
  guard cli() is Some(path) else { return }
  // A call deadline and a budget beyond the session deadline.
  let call = @guest.CallBounds::new(
    deadline_ms=60000,
    instructions=Some(2147483647),
  )
  let failure = probe_ending(
    host(path, call~),
    wasm_spec(@fixtures.runaway_guest()),
    deadline=@worker.Deadline::of_ms(3000),
  )
  guard failure is Some((Deadline, report)) else {
    fail(
      "the session deadline did not end the probe: \{@debug.to_string(failure)}",
    )
  }
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_true(
    stop.status is Terminated(Deadline) || stop.status is Signalled(..),
  )
}

///|
async test "memory ceiling: a growth past 256 MiB fails the call with memory_limit" {
  guard cli() is Some(path) else { return }
  let failure = probe_ending(
    host(path),
    wasm_spec(@fixtures.growing_guest(4096)),
  )
  guard failure is Some((Failed(Host(code=MemoryLimit, ..)), _)) else {
    fail("a growth past the ceiling did not fail with memory_limit")
  }
}

///|
async test "build identity: a worker of another build is refused with worker_runtime_mismatch" {
  guard cli() is Some(path) else { return }
  let other = @native.BuildIdentity::parse(
    "1111111111111111111111111111111111111111111111111111111111111111",
  )
  let failure = probe_ending(
    host(path, identity=other),
    wasm_spec(@fixtures.extism_echo_guest()),
  )
  guard failure is Some((Refused(code=WorkerRuntimeMismatch, ..), _)) else {
    fail(
      "a worker of another build was not refused: \{@debug.to_string(failure)}",
    )
  }
}

///|
async test "unsupported WASM features: a shared memory is refused at load, before any request" {
  // The launcher refuses before it starts a process, so no CLI is needed.
  let plain = @fixtures.module_(
    imports=@fixtures.byte_callbacks(),
    functions=[
      @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
    ],
    memory=@fixtures.Memory::new(1, maximum=2, exported=false),
  )
  // Set the shared flag of the memory limits: 0x01 becomes 0x03.
  let shared = plain.to_array()
  for index in 0..<(shared.length() - 5) {
    if shared[index] == b'\x05' &&
      shared[index + 1] == b'\x04' &&
      shared[index + 2] == b'\x01' &&
      shared[index + 3] == b'\x01' {
      shared[index + 3] = b'\x03'
      break
    }
  }
  let failure = probe_ending(
    host("/nonexistent/morphir"),
    wasm_spec(Bytes::from_array(shared)),
  )
  guard failure
    is Some((Refused(code=WasmFeatureUnsupported, message~), report)) else {
    fail("a shared memory was not refused: \{@debug.to_string(failure)}")
  }
  assert_true(message.contains("threads"))
  assert_true(report.stop is None)
}

///|
async test "ABI classification at launch: env.open_socket is refused and nothing starts" {
  let guest = @fixtures.module_(
    imports=[
      @fixtures.ImportedFunction::new("env", "open_socket", [I32], [I32]),
    ],
    functions=[
      @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
    ],
  )
  let failure = probe_ending(host("/nonexistent/morphir"), wasm_spec(guest))
  guard failure is Some((Refused(code=AbiUnsupported, message~), report)) else {
    fail("env.open_socket was not refused")
  }
  assert_true(message.contains("env.open_socket"))
  assert_true(report.stop is None)
}

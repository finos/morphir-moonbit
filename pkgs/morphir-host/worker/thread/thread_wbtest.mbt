///|
/// The built worker entry module: MORPHIR_WASM_THREAD_ENTRY names it. The
/// qualification builds worker/thread/entry for js and sets the variable.
fn entry() -> String? {
  @env.get_env_var("MORPHIR_WASM_THREAD_ENTRY")
}

///|
fn wasm_spec(bytes : Bytes, abi? : @worker.WasmAbi) -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(bytes), @worker.Sha256::of(bytes)),
    Wasm(abi~),
  )
}

///|
fn host(path : String, call_ms? : Int32) -> @worker.Host {
  @worker.Host::new(
    ThreadLauncher::new(entry=path, call_ms?),
    Node(Aarch64AppleDarwin),
  )
}

///|
/// How a probe ended early, or `None` when it described the guest.
async fn probe_ending(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
  deadline? : @worker.Deadline,
  stop? : @worker.StopSignal,
) -> (@worker.Ending, @worker.SessionReport)? {
  try host.probe(spec, deadline?, stop?) catch {
    @worker.Ended(ending, report~) => Some((ending, report))
    _ => abort("not a host error")
  } noraise {
    _ => None
  }
}

///|
async test "Node worker threads: an Extism guest runs in a thread with the js bounds" {
  guard entry() is Some(path) else { return }
  guard probe_ending(host(path), wasm_spec(@fixtures.extism_echo_guest()))
    is Some((ending, report)) else {
    fail("the echo guest described itself")
  }
  // The echo guest answers describe with the request, which is not a
  // description, after a full round trip through the thread.
  assert_true(ending is Failed(Host(..)))
  guard report.bounds is Some(bounds) else { fail("no bounds in the report") }
  assert_eq(bounds.instruction_budget, NotEnforced(NoInstructionMetering))
  assert_eq(bounds.call_deadline, Enforced)
  assert_eq(bounds.memory_ceiling, Enforced)
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.stop_method, ThreadTermination)
}

///|
async test "runaway guest in a thread: the call deadline terminates the thread" {
  guard entry() is Some(path) else { return }
  guard probe_ending(
      host(path, call_ms=300),
      wasm_spec(@fixtures.runaway_guest()),
    )
    is Some((ending, report)) else {
    fail("a runaway guest described itself")
  }
  assert_eq(ending, Deadline)
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.status, Terminated(Deadline))
}

///|
async test "runaway guest in a thread: the session deadline terminates the thread" {
  guard entry() is Some(path) else { return }
  guard probe_ending(
      host(path),
      wasm_spec(@fixtures.runaway_guest()),
      deadline=@worker.Deadline::of_ms(800),
    )
    is Some((ending, report)) else {
    fail("a runaway guest described itself")
  }
  assert_eq(ending, Deadline)
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.status, Terminated(Deadline))
}

///|
async test "cancel a WASM call in a thread: the thread is terminated and the outcome is cancelled" {
  guard entry() is Some(path) else { return }
  let started = @async.now()
  let stop = @worker.StopSignal::new(() => @async.now() - started > 500L)
  guard probe_ending(host(path), wasm_spec(@fixtures.runaway_guest()), stop~)
    is Some((ending, report)) else {
    fail("a runaway guest described itself")
  }
  assert_eq(ending, Cancelled)
  guard report.stop is Some(worker) else { fail("no worker stop") }
  assert_eq(worker.status, Terminated(Cancelled))
}

///|
async test "guest traps in a thread: the session fails with guest_trap" {
  guard entry() is Some(path) else { return }
  guard probe_ending(host(path), wasm_spec(@fixtures.trapping_guest()))
    is Some((Failed(Host(code=GuestTrap, ..)), _)) else {
    fail("a trap did not fail with guest_trap")
  }
}

///|
async test "memory ceiling in a thread: a growth past 256 MiB fails with memory_limit" {
  guard entry() is Some(path) else { return }
  guard probe_ending(host(path), wasm_spec(@fixtures.growing_guest(4096)))
    is Some((Failed(Host(code=MemoryLimit, ..)), _)) else {
    fail("a growth past the ceiling did not fail with memory_limit")
  }
}

///|
async test "the thread launcher refuses a module outside its profile before a thread starts" {
  let guest = @fixtures.module_(
    imports=[
      @fixtures.ImportedFunction::new("env", "open_socket", [I32], [I32]),
    ],
    functions=[
      @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
    ],
  )
  guard probe_ending(host("/nonexistent/entry.js"), wasm_spec(guest))
    is Some((Refused(code=AbiUnsupported, ..), report)) else {
    fail("env.open_socket was not refused")
  }
  assert_true(report.stop is None)
}

///|
async test "Node worker threads: the portable guest and Python describe themselves" {
  guard entry() is Some(path) else { return }
  if @env.get_env_var("MORPHIR_PORTABLE_GUEST") is Some(portable) {
    let bytes = read_file(portable)
    let description = host(path).probe(wasm_spec(bytes, abi=MorphirBytesV1))
    assert_true(
      description.claims.languages
      .iter()
      .any(claim => claim.language_id.to_string() == "moonbit"),
    )
  }
  if @env.get_env_var("MORPHIR_PYTHON_EXTENSIONS") is Some(root) {
    for version in ["0.4.1", "0.4.2"] {
      let bytes = read_file(
        "\{root}/\{version}/morphir-python-binding-\{version}.wasm",
      )
      let description = host(path).probe(wasm_spec(bytes, abi=ExtismKernelV1))
      assert_eq(description.claims.version.to_string(), version)
    }
  }
}

///|
async test "a missing entry module fails the launch and names the file" {
  guard probe_ending(
      host("/nonexistent/wasm-worker.js"),
      wasm_spec(@fixtures.echo_guest()),
    )
    is Some((Failed(Host(code=IncompleteSession, message~)), report)) else {
    fail("a missing entry module did not fail the launch")
  }
  assert_true(message.contains("/nonexistent/wasm-worker.js"))
  assert_true(report.stop is None)
}

///|
test "the bundled launcher looks for wasm-worker.js beside the running script" {
  let path = beside_script(ENTRY_FILE)
  assert_true(
    path.has_suffix("/wasm-worker.js") || path.has_suffix("\\wasm-worker.js"),
  )
}

///|
/// A module in a new temporary directory.
async fn module_file(bytes : Bytes) -> String {
  let directory = @fs.tmpdir(prefix="morphir-wasm-worker-test-")
  let path = directory + "/module.wasm"
  @fs.write_file(path, bytes)
  path
}

///|
fn options(
  abi : @worker.WasmAbi,
  module_path : String,
  identity~ : @native.BuildIdentity = @native.BuildIdentity::current(),
) -> @native.WorkerOptions {
  let args = [
    "--abi",
    abi.to_string(),
    "--module",
    module_path,
    "--build-identity",
    identity.to_string(),
    "--json",
  ]
  let invocation = @native.WorkerInvocation::parse(args) catch {
    error => abort("invalid arguments: \{@debug.to_string(error)}")
  }
  guard invocation is Serve(options) else { abort("not a serve invocation") }
  options
}

///|
/// Runs the worker mode with `requests` as framed stdin. Returns the exit
/// status, the response messages and the stderr report.
async fn run_worker(
  options : @native.WorkerOptions,
  requests : Array[Json],
) -> (Int32, Array[Json], Bytes) {
  let (stdin_read, stdin_write) = @io.pipe()
  let (stdout_read, stdout_write) = @io.pipe()
  let (stderr_read, stderr_write) = @io.pipe()
  let writer = @shared.FrameWriter::new(limit=4194304)
  let mut code = -1
  let mut responses = []
  let mut report = b""
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      // A worker that refuses reads nothing; its stdin closes under the
      // writer.
      for request in requests {
        guard request is Object(fields) else { abort("not an object") }
        stdin_write.write(writer.encode(@worker.Message::new(fields))) catch {
          _ => break
        }
      }
      stdin_write.close()
    })
    group.spawn_bg(() => {
      let reader = @shared.FrameReader::new(limit=16777216)
      let all = stdout_read.read_all().binary()
      responses = reader.feed(all).map(message => message.json())
    })
    group.spawn_bg(() => report = stderr_read.read_all().binary())
    code = options.serve(
      stdin_read,
      stdout_write,
      stderr_write,
      workspace_root="/work",
    )
    stdin_read.close()
    stdout_write.close()
    stderr_write.close()
  })
  (code, responses, report)
}

///|
fn request(id : Int32, method_name : String) -> Json {
  { "jsonrpc": "2.0", "id": id, "method": method_name }
}

///|
fn exit_notification() -> Json {
  { "jsonrpc": "2.0", "method": "morphir.exit" }
}

///|
async test "worker mode output: stdout carries only frames and the report goes to stderr" {
  let path = module_file(@fixtures.extism_echo_guest())
  let (code, responses, report) = run_worker(options(ExtismKernelV1, path), [
    request(1, "morphir.extension.describe"),
    { "jsonrpc": "2.0", "method": "morphir.initialized" },
    request(2, "morphir.shutdown"),
    exit_notification(),
  ])
  assert_eq(code, 0)
  assert_eq(responses, [
    request(1, "morphir.extension.describe"),
    request(2, "morphir.shutdown"),
  ])
  let lines = @utf8.decode(report).split("\n").to_array()
  guard lines[0].has_prefix("{\"profile\":\"morphir/command-event\"") else {
    fail("the report does not start with an event: \{lines[0]}")
  }
  assert_true(lines[0].contains("\"event\":\"started\""))
  assert_true(lines.iter().any(line => line.contains("\"event\":\"exited\"")))
  assert_eq(@guest.WorkerEvent::ending_in(report), None)
}

///|
async test "build identity: a worker of another build refuses before it reads a request" {
  let path = module_file(@fixtures.extism_echo_guest())
  let other = @native.BuildIdentity::parse(
    "0000000000000000000000000000000000000000000000000000000000000000",
  )
  let (code, responses, report) = run_worker(
    options(ExtismKernelV1, path, identity=other),
    [request(1, "morphir.extension.describe")],
  )
  assert_eq(code, 3)
  assert_eq(responses, [])
  guard @guest.WorkerEvent::ending_in(report)
    is Some(Refused(code=WorkerRuntimeMismatch, ..)) else {
    fail("no runtime mismatch in the report")
  }
}

///|
async test "declared ABI must agree: the worker refuses a module of another profile" {
  let path = module_file(@fixtures.extism_echo_guest())
  let (code, _, report) = run_worker(options(MorphirBytesV1, path), [])
  assert_eq(code, 3)
  assert_true(
    @guest.WorkerEvent::ending_in(report) is Some(Refused(code=AbiMismatch, ..)),
  )
}

///|
async test "guest traps: the worker reports the trap and exits 1" {
  let path = module_file(@fixtures.trapping_guest())
  let (code, responses, report) = run_worker(options(MorphirBytesV1, path), [
    request(1, "morphir.extension.describe"),
  ])
  assert_eq(code, 1)
  assert_eq(responses, [])
  assert_true(
    @guest.WorkerEvent::ending_in(report) is Some(GuestFailed(Trap(_))),
  )
}

///|
async test "guest prints: WASI output goes to the report, never to the response stream" {
  let path = module_file(@fixtures.extism_wasi_guest())
  let (code, responses, report) = run_worker(options(ExtismKernelV1, path), [
    request(1, "x"),
  ])
  // The guest answers with one byte, which is not a JSON message.
  assert_eq(code, 1)
  assert_eq(responses, [])
  let text = @utf8.decode(report)
  assert_true(text.contains("stdout: hello"))
}

///|
async test "the worker ends with a fault when the host closes stdin before exit" {
  let path = module_file(@fixtures.echo_guest())
  let (code, _, report) = run_worker(options(MorphirBytesV1, path), [])
  assert_eq(code, 1)
  assert_true(
    @guest.WorkerEvent::ending_in(report) is Some(GuestFailed(Failure(_))),
  )
}

///|
test "worker arguments: missing or invalid values are usage errors" {
  let refused = (args : Array[String]) => {
    try @native.WorkerInvocation::parse(args) catch {
      UsageError(_) => true
    } noraise {
      _ => false
    }
  }
  assert_true(refused([]))
  assert_true(
    refused(["--abi", "wasi-cli", "--module", "m", "--build-identity", "0"]),
  )
  assert_true(@native.WorkerInvocation::parse(["--help"]) is Help(json=false))
  assert_true(@native.worker_help().contains("stdout carries only"))
}

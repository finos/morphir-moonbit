///|
#cfg(not(platform="windows"))
#borrow(path, problem)
extern "C" fn read_artifact_ffi(
  path : Bytes,
  limit : Int64,
  problem : FixedArray[Int32],
) -> Bytes = "morphir_worker_read_artifact"

///|
#cfg(not(platform="windows"))
#borrow(path, args, cwd, host, pid)
extern "C" fn spawn_ffi(
  path : Bytes,
  args : FixedArray[Bytes],
  count : Int32,
  cwd : Bytes,
  host : FixedArray[Int32],
  pid : FixedArray[Int32],
) -> Int32 = "morphir_worker_spawn"

///|
#cfg(not(platform="windows"))
extern "C" fn signal_group_ffi(pgid : Int32, terminate : Bool) -> Int32 = "morphir_worker_signal_group"

///|
#cfg(not(platform="windows"))
extern "C" fn group_state_ffi(pgid : Int32) -> Int32 = "morphir_worker_group_state"

///|
/// A NUL-terminated UTF-8 string for a C call.
#cfg(not(platform="windows"))
fn os_text(text : String) -> Bytes raise @worker.LaunchError {
  guard !text.contains_char('\u0000') else {
    raise LaunchFailed("a worker argument or path holds a NUL character")
  }
  let buffer = @buffer.Buffer::Buffer()
  buffer.write_bytes(@utf8.encode(text))
  buffer.write_byte(b'\x00')
  buffer.to_bytes()
}

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn file_present_ffi(path : Bytes) -> Int32 = "morphir_worker_file_present"

///|
/// Whether a regular file exists at `path`, after links.
#cfg(not(platform="windows"))
fn file_present(path : String) -> Bool {
  (file_present_ffi(os_text(path)) catch { _ => 0 }) == 1
}

///|
#cfg(not(platform="windows"))
fn read_artifact(path : String) -> Bytes raise @worker.LaunchError {
  let problem : FixedArray[Int32] = [0, 0]
  let bytes = read_artifact_ffi(
    os_text(path),
    @shared.ARTIFACT_LIMIT_BYTES.to_int64(),
    problem,
  )
  match problem[0] {
    0 => bytes
    code => raise ArtifactUnreadable(artifact_problem(code, problem[1]))
  }
}

///|
/// A worker's process group. Its ID is the PID of the worker, its leader.
#cfg(not(platform="windows"))
priv struct ProcessGroup {
  pgid : Int32
}

///|
#cfg(not(platform="windows"))
impl Tree for ProcessGroup with fn terminate(self) {
  ignore(signal_group_ffi(self.pgid, true))
}

///|
#cfg(not(platform="windows"))
impl Tree for ProcessGroup with fn kill(self) {
  ignore(signal_group_ffi(self.pgid, false))
}

///|
#cfg(not(platform="windows"))
impl Tree for ProcessGroup with fn state(self) {
  match group_state_ffi(self.pgid) {
    0 | 1 => Gone
    2 => Live
    code => Unknown(code)
  }
}

///|
#cfg(not(platform="windows"))
impl Tree for ProcessGroup with fn release(_self) {
  ()
}

///|
/// Starts the staged copy as the leader of a new process group, with three
/// pipes, no other descriptor, an empty environment and the private working
/// directory. The C stub makes the pipes, so the worker's ends are never
/// registered with the host's event loop; the host wraps only its own ends.
#cfg(not(platform="windows"))
async fn spawn(
  staged : @shared.StagedArtifact,
  args : Array[String],
) -> Spawned {
  let executable = staged.executable()
  let argv = FixedArray::make(args.length() + 1, b"")
  argv[0] = os_text(executable)
  for i, argument in args {
    argv[i + 1] = os_text(argument)
  }
  let host : FixedArray[Int32] = [-1, -1, -1]
  let pid : FixedArray[Int32] = [0]
  let error = spawn_ffi(
    os_text(executable),
    argv,
    argv.length(),
    os_text(staged.working_directory()),
    host,
    pid,
  )
  if error != 0 {
    raise @worker.LaunchError::LaunchFailed(
      "posix_spawn failed with errno \{error}",
    )
  }
  let group = ProcessGroup::{ pgid: pid[0], }
  // Until the worker is handed over, any way out stops its group and reaps
  // the leader, so that the caller can remove the private directory.
  let mut handed_over = false
  defer (if !handed_over {
    @async.protect_from_cancel(() => {
      Tree::kill(group)
      ignore(Leader::new(pid[0]).wait_for(@shared.STOP_CONFIRM_MS))
    })
  })
  let (input, output, errors) = @async.protect_from_cancel(() => {
    (
      @raw_fd.RawFdStream(host[0]),
      @raw_fd.RawFdStream(host[1]),
      @raw_fd.RawFdStream(host[2]),
    )
  }) catch {
    error =>
      raise @worker.LaunchError::LaunchFailed(
        "cannot open the worker's pipes: \{error}",
      )
  }
  handed_over = true
  {
    pid: pid[0],
    tree: group,
    stop_method: GroupSignal,
    input,
    output,
    errors,
    close_streams: () => {
      input.close()
      output.close()
      errors.close()
    },
    close_input: () => input.close(),
  }
}

///|
/// A started worker: its PID, its tree and the host's ends of its standard
/// streams.
priv struct Spawned {
  pid : Int32
  tree : &Tree
  stop_method : @worker.StopMethod
  input : &@io.Writer
  output : &@io.Reader
  errors : &@io.Reader
  close_streams : () -> Unit
  close_input : () -> Unit
}

///|
/// Maps the problem code of `morphir_worker_read_artifact`. `detail` is the
/// operating system error, kept for diagnostics only.
fn artifact_problem(code : Int32, detail : Int32) -> @worker.ArtifactProblem {
  match code {
    1 => SymbolicLink
    2 => NotRegularFile
    3 => TooLarge
    _ =>
      Unreadable(
        detail=if detail == 0 { None } else { Some("os error \{detail}") },
      )
  }
}

///|
/// The command line that a Windows worker receives, quoted so that the
/// Microsoft C runtime splits it back into exactly `program` and `args`,
/// including empty arguments, quotes and trailing backslashes.
pub fn windows_command_line(
  program : String,
  args : ArrayView[String],
) -> String {
  let line = StringBuilder()
  fn quote(argument : String) {
    line.write_char('"')
    let mut slashes = 0
    for c in argument {
      if c == '\\' {
        slashes += 1
        continue
      }
      let escaped = if c == '"' { slashes * 2 + 1 } else { slashes }
      for _ in 0..<escaped {
        line.write_char('\\')
      }
      line.write_char(c)
      slashes = 0
    }
    for _ in 0..<(slashes * 2) {
      line.write_char('\\')
    }
    line.write_char('"')
  }

  quote(program)
  for argument in args {
    line.write_char(' ')
    quote(argument)
  }
  line.to_string()
}

///|
extern "C" fn process_alive_ffi(pid : Int32) -> Bool = "morphir_worker_process_alive"

///|
/// Whether a process with this ID runs on the host. A process that has
/// exited but is not reaped yet does not run.
pub fn process_alive(pid : Int32) -> Bool {
  process_alive_ffi(pid)
}

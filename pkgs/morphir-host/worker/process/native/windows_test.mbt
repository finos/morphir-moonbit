// Windows tests. The command-line tests run everywhere; the job object test
// runs only on Windows, in the deliberate Windows run of task 2.3.

///|
test "a Windows command line keeps empty arguments, quotes and backslashes" {
  assert_eq(
    @native.windows_command_line("C:\\work\\bin\\worker.exe", [
      "", "a b", "say \"hi\"", "trailing\\", "C:\\dir\\", "--",
    ]),
    "\"C:\\work\\bin\\worker.exe\" \"\" \"a b\" \"say \\\"hi\\\"\" \"trailing\\\\\" \"C:\\dir\\\\\" \"--\"",
  )
  assert_eq(
    @native.windows_command_line("w.exe", ["a\\\\\"b"]),
    "\"w.exe\" \"a\\\\\\\\\\\"b\"",
  )
}

///|
#cfg(platform="windows")
async test "cancellation terminates the worker's job and every process in it" {
  let system_root = @env.get_env_var("SystemRoot").unwrap_or("C:\\Windows")
  let cmd = system_root + "\\System32\\cmd.exe"
  let artifact = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(cmd, Windows)),
    @worker.Sha256::of(@fs.read_file(cmd).binary()),
  )
  let ping = system_root + "\\System32\\PING.EXE"
  let channel = @native.ProcessLauncher::new().start(@native.stage(artifact), [
    "/d",
    "/c",
    "start /b \{ping} -n 300 127.0.0.1 >nul & \{ping} -n 300 127.0.0.1 >nul",
  ])
  @async.sleep(500)
  let stop = channel.abort(Cancelled)
  assert_eq(stop.status, Terminated(Cancelled))
  assert_eq(stop.stop_method, JobTermination)
  let (_, listing) = @process.collect_stdout(
    system_root + "\\System32\\tasklist.exe",
    ["/FI", "PID eq \{channel.pid()}", "/NH"],
  )
  assert_true(!listing.text().contains("\{channel.pid()}"))
}

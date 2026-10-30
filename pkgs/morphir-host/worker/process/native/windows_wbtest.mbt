// White-box Windows tests. They run only on Windows, in the deliberate
// Windows run of task 2.3.

///|
#cfg(platform="windows")
#borrow(pids)
extern "C" fn processes_ffi(
  worker : WinWorker,
  pids : FixedArray[Int32],
  capacity : Int32,
) -> Int32 = "morphir_worker_win_processes"

///|
/// The IDs of the processes in the job, or none after it is released.
#cfg(platform="windows")
fn Job::processes(self : Job) -> Array[Int32] {
  guard !self.released else { return [] }
  let pids = FixedArray::make(256, 0)
  let count = processes_ffi(self.worker, pids, pids.length())
  Array::makei(@cmp.maximum(count, 0), i => pids[i])
}

///|
/// The IDs of the `PING.EXE` processes that run on the host.
#cfg(platform="windows")
async fn ping_processes(system_root : String) -> Array[Int32] {
  let (_, listing) = @process.collect_stdout(
    system_root + "\\System32\\tasklist.exe",
    ["/FI", "IMAGENAME eq PING.EXE", "/FO", "CSV", "/NH"],
  )
  let pids = []
  for line in listing.text().split("\n") {
    // "PING.EXE","1234","Console","1","4,000 K"
    let fields = line.trim().split(",").to_array()
    guard fields is [image, pid, ..] && image.to_upper() == "\"PING.EXE\"" else {
      continue
    }
    let digits = pid.trim(chars="\"")
    let value = @string.parse_int(digits) catch { _ => continue }
    pids.push(value)
  }
  pids
}

///|
#cfg(platform="windows")
async test "cancellation terminates the worker's job and every process in it" {
  let system_root = @env.get_env_var("SystemRoot").unwrap_or("C:\\Windows")
  let cmd = system_root + "\\System32\\cmd.exe"
  let ping = system_root + "\\System32\\PING.EXE"
  // PING processes that ran before the test are not the worker's.
  let before = ping_processes(system_root)
  let staged = stage(
    @worker.ArtifactRef::new(
      File(@worker.ArtifactPath::parse(cmd, Windows)),
      @worker.Sha256::of(@fs.read_file(cmd).binary()),
    ),
  )
  let job = Job::start(staged, [
    "/d",
    "/c",
    "start /b \{ping} -n 300 127.0.0.1 >nul & \{ping} -n 300 127.0.0.1 >nul",
  ])
  let channel = ProcessChannel::new(
    job.spawned(),
    staged,
    @worker.Limits::host(),
    grace_ms=@shared.EXIT_GRACE_MS,
    confirm_ms=@shared.STOP_CONFIRM_MS,
  )
  // Wait until both PING grandchildren run.
  let deadline = @async.now() + 10000L
  let mut pings = []
  while @async.now() < deadline {
    pings = ping_processes(system_root).filter(pid => !before.contains(pid))
    if pings.length() >= 2 {
      break
    }
    @async.sleep(50)
  }
  let members = job.processes()
  assert_true(pings.length() >= 2, msg="PING processes: \{pings.length()}")
  assert_true(members.contains(channel.pid()))
  for pid in pings {
    assert_true(members.contains(pid), msg="PING \{pid} is not in the job")
  }
  let stop = channel.abort(Cancelled)
  assert_eq(stop.status, Terminated(Cancelled))
  assert_eq(stop.stop_method, JobTermination)
  for pid in members {
    assert_false(process_alive(pid), msg="process \{pid} of the job runs")
  }
  let left = ping_processes(system_root).filter(pid => !before.contains(pid))
  assert_eq(left, [])
}

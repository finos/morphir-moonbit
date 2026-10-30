///|
fn report_of(events : Array[@guest.WorkerEvent]) -> Bytes {
  let lines = events.mapi((index, event) => {
    event.to_json(sequence=index + 1).stringify()
  })
  @utf8.encode(lines.join("\n") + "\n")
}

///|
test "worker report: each event is a morphir/command-event line" {
  let line = @guest.WorkerEvent::Exited(code=0).to_json(sequence=3)
  guard line
    is {
      "profile": "morphir/command-event",
      "contractVersion": "0.1.0",
      "command": "extension worker",
      "event": "exited",
      "sequence": 3,
      "exitCode": 0,
      ..
    } else {
    fail("not a command event: \{line.stringify()}")
  }
}

///|
test "worker report: the host reads the last fault after the guest's output" {
  let stderr = report_of([
    Output(Stdout(b"a fault in the text: {\"event\":\"fault\"}")),
    Fault(Trap("unreachable")),
  ])
  assert_eq(
    @guest.WorkerEvent::ending_in(stderr),
    Some(GuestFailed(Trap("unreachable"))),
  )
  for
    fault in [
      @worker.GuestFault::MemoryLimit("grow"),
      CallDeadline,
      BudgetExhausted,
      Failure("handle returned -1"),
    ] {
    assert_eq(
      @guest.WorkerEvent::ending_in(report_of([Fault(fault)])),
      Some(GuestFailed(fault)),
    )
  }
}

///|
test "worker report: a refusal is read with its code" {
  let stderr = report_of([
    Refused(code=WorkerRuntimeMismatch, message="the worker is build b"),
  ])
  assert_eq(
    @guest.WorkerEvent::ending_in(stderr),
    Some(Refused(code=WorkerRuntimeMismatch, message="the worker is build b")),
  )
}

///|
test "worker report: a worker that exited or wrote no report gives nothing" {
  assert_eq(@guest.WorkerEvent::ending_in(report_of([Exited(code=0)])), None)
  assert_eq(@guest.WorkerEvent::ending_in(b"plain text\n"), None)
  // A truncated first line, as at the start of a stderr tail, is skipped.
  let stderr = b"ted\":\"x\"}\n" + report_of([Fault(CallDeadline)])
  assert_eq(
    @guest.WorkerEvent::ending_in(stderr),
    Some(GuestFailed(CallDeadline)),
  )
}

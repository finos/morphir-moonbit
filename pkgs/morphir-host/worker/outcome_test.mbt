///|
test "host limits default to the specified bounds" {
  let limits = @worker.Limits::host()
  assert_eq(limits.request_bytes, 4 * 1024 * 1024)
  assert_eq(limits.response_bytes, 16 * 1024 * 1024)
  assert_eq(limits.model.decoded_bytes, 2 * 1024 * 1024)
  assert_eq(limits.model.encoded_bytes, 2796204)
  assert_eq(limits.model.depth, 128)
  assert_eq(limits.model.nodes, 100000)
}

///|
test "limits must be positive" {
  let model = @worker.ModelLimits::new(
    encoded_bytes=10,
    decoded_bytes=8,
    depth=4,
    nodes=16,
  )
  assert_eq(model.nodes, 16)
  guard (Ok(
      @worker.ModelLimits::new(
        encoded_bytes=10,
        decoded_bytes=0,
        depth=4,
        nodes=16,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(InvalidLimit(_)) else {
    fail("accepted a zero limit")
  }
  guard (Ok(@worker.Limits::new(request_bytes=-1, response_bytes=1, model~)) catch {
      e => Err(e)
    })
    is Err(InvalidLimit(_)) else {
    fail("accepted a negative limit")
  }
}

///|
test "failure codes use the documented names" {
  assert_eq(
    @worker.FailureCode::IncompleteSession.to_string(),
    "extension.incomplete_session",
  )
  assert_eq(
    @worker.FailureCode::TreeTerminationFailed.to_string(),
    "execution.tree_termination_failed",
  )
}

///|
test "the stderr tail keeps the last 64 KiB" {
  let head = Bytes::make(10, b'a')
  let tail = Bytes::make(65536, b'b')
  let kept = @worker.StderrTail::of(head + tail)
  assert_eq(kept.bytes().length(), 65536)
  assert_true(kept.bytes() == tail)
  assert_eq(@worker.StderrTail::empty().bytes().length(), 0)
}

///|
test "every outcome class keeps diagnostics and the stderr tail" {
  let diagnostics : Array[Json] = [{ "code": "E1", "severity": "error" }]
  let stderr = @worker.StderrTail::of(b"warning")
  let outcome : @worker.Outcome[String] = @worker.Outcome::new(
    Refused(Host(code=ClaimsMismatch, message="version drift")),
    diagnostics~,
    stderr~,
  )
  guard outcome.class is Refused(Host(code=ClaimsMismatch, ..)) else {
    fail("lost the refusal")
  }
  assert_eq(outcome.diagnostics, diagnostics)
  assert_true(outcome.stderr.bytes() == b"warning")
  let failed : @worker.Outcome[String] = @worker.Outcome::new(
    Failed(Guest(code=-32600, message="bad request")),
    diagnostics=[],
    stderr=@worker.StderrTail::empty(),
  )
  assert_true(failed.class is Failed(Guest(code=-32600, ..)))
}

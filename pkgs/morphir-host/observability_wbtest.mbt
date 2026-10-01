///|
test "bounded telemetry queue counts dropped records while aggregating all stage completions" {
  let session = TelemetrySession::{
    sequence: Ref(0),
    metrics: Map([]),
    dimensions: Map([]),
    metrics_overflow: 0,
    records: [],
    path: Some("unused"),
    format: "ion-binary",
    run_id: "test",
    next: 0,
    dropped: 0,
    closed: false,
  }
  let observer = session.observer()
  let event : @observe.Observation = {
    context: {
      run_id: "test",
      span_id: "1",
      parent_id: "",
      trace_id: "11111111111111111111111111111111",
    },
    details: None,
    correlation: None,
    sequence: 1,
    stage: @observe.Invoke,
    signal: @observe.Succeeded,
    wall_seconds: 1.0,
    duration_seconds: 0.05,
  }
  for i = 0; i < 2050; i = i + 1 {
    ignore((observer.try_record)(event))
  }
  assert_eq(session.records.length(), 2048)
  assert_eq(session.dropped, 2)
  let (count, duration, buckets) = session.metrics["invoke"]
  assert_eq(count, 2050)
  assert_true(duration > 102.49 && duration < 102.51)
  assert_eq(buckets, [0, 0, 2050, 0, 0, 0, 0])
  session.closed = true
  assert_true((observer.try_record)(event) is Unavailable)
}

///|
test "metric descriptors bound cardinality and account for series overflow without call identities" {
  let session = TelemetrySession::{
    sequence: Ref(0),
    metrics: Map([]),
    dimensions: Map([]),
    metrics_overflow: 0,
    records: [],
    path: Some("unused"),
    format: "ion-binary",
    run_id: "test",
    next: 0,
    dropped: 0,
    closed: false,
  }
  let observer = session.observer()
  let mut emitted = 0
  for
    stage in [
      @observe.Plan,
      Decode,
      Generate,
      Build,
      Invoke,
      Call,
      Evaluate,
      Compare,
      Cleanup,
      Execute,
      Legacy,
    ] {
    for target in ["js", "wasm-gc", "native", "llvm", "arbitrary-target"] {
      for signal in [@observe.Succeeded, Failed, Cancelled] {
        emitted += 1
        ignore(
          (observer.try_record)({
            context: {
              run_id: "private-run",
              span_id: "private-span",
              parent_id: "private-parent",
              trace_id: "11111111111111111111111111111111",
            },
            details: Some({ entry: "private-entry", code: "execution.ok", }),
            correlation: Some({
              target,
              lease_id: "private-lease",
              call_id: "private-call-" + emitted.to_string(),
              attempt_id: "private-attempt",
            }),
            sequence: emitted,
            stage,
            signal,
            wall_seconds: 1.0,
            duration_seconds: 0.01,
          }),
        )
      }
    }
  }
  assert_eq(session.dimensions.length(), 128)
  assert_eq(session.metrics_overflow, emitted - 128)
  let metrics = session.metrics().stringify()
  assert_false(metrics.contains("private-"))
  assert_false(metrics.contains("arbitrary-target"))
  assert_true(metrics.contains("other"))
  session.closed = true
}

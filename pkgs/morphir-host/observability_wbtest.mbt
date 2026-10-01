///|
test "bounded telemetry queue counts dropped records while aggregating all stage completions" {
  let session = TelemetrySession::{
    sequence: Ref(0),
    metrics: Map([]),
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

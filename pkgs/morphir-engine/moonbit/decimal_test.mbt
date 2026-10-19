///|
test "checked Decimal engine profile preserves precision through Ion replay and rejects lossy JSON" {
  let snapshot = files()
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="language='moonbit'",
    new="language='moonbit'\nprofile='moonbit-model-library-2026-10-19-r4'",
  )
  snapshot["src/Main.mbt"] = "pub fn amount() -> @decimal.Decimal raise @decimal.DecimalError { let a = @decimal.from_string_exact(\"12.3400\"); @decimal.add(a, @decimal.from_string_exact(\"0.660\")) }\npub fn identity(v : @decimal.Decimal) -> @decimal.Decimal { v }"
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let descriptor = plan(engine, snapshot).source_frontends()[0]
  assert_eq(
    descriptor.dependencies["finos/morphir-sdk/decimal"],
    "0.1.0+tree:642fd13ea74bc46c3f5344844c9cca4ffbae368a",
  )
  let report = execute(engine, snapshot)
  assert_true(report.successful())
  let registry = @data.Registry::new()
  let unit = registry.decode("ion-binary", {
    unit_id: "Main",
    content: report.artifacts[0].content,
  })
  let suite = @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      { "id": "amount", "entry": "pricing:app/main#amount", "arguments": [] },
      {
        "id": "identity",
        "entry": "pricing:app/main#identity",
        "arguments": [
          { "type": "decimal", "coefficient": "1234", "exponent": -2 },
        ],
      },
    ],
  })
  for format in ["ion-text", "ion-binary"] {
    let replay = registry.decode(format, {
      unit_id: "Main",
      content: registry.encode(format, unit),
    })
    assert_eq(replay.distribution, unit.distribution)
    assert_eq(replay.metadata.length(), unit.metadata.length())
    for i = 0; i < unit.metadata.length(); i = i + 1 {
      assert_eq(replay.metadata[i].node_id, unit.metadata[i].node_id)
      assert_true(replay.metadata[i].data.equals(unit.metadata[i].data))
    }
    assert_eq(
      @execution.plan_scheme(replay, suite)
      .evaluate()
      .map(@protocol.Value::to_json),
      [
        { "type": "decimal", "coefficient": "13", "exponent": 0 },
        { "type": "decimal", "coefficient": "1234", "exponent": -2 },
      ],
    )
  }
  snapshot["morphir.toml"] = snapshot["morphir.toml"] +
    "\ncheckpoint_format='morphir-json'"
  let lossy = execute(engine, snapshot)
  assert_false(lossy.successful())
  assert_true(lossy.artifacts.is_empty())
  assert_true(lossy.diagnostics[0].message.contains("data.lossy_conversion"))
}

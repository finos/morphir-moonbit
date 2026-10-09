///|
fn named_input(rows : String) -> @generator.Input raise {
  {
    ..@generator.Input::new("sample", @metadata_fixtures.input()),
    metadata: [
      {
        node_id: "value:example:main#ready",
        data: @metadata_fixtures.adapter(rows),
      },
    ],
  }
}

///|
test "exact target request reserves name before automatic allocation and every reference agrees" {
  let input = named_input("[" + @metadata_fixtures.row("ready") + "]")
  let output = @generator.generate(
    input,
    metadata_capabilities=@metadata_fixtures.capabilities(),
  )
  let names = Map::from_array(
    output.symbols.map(s => (s.fqname, s.generated_name)),
  )
  assert_eq(names["example:main#ready"], "wanted")
  assert_eq(names["example:main#wanted"], "main_wanted")
  assert_true(source(output).contains("pub fn wanted()"))
  assert_true(source(output).contains("  wanted()"))
  let exact = output.naming_allocations.filter(a => {
      a.owner == "value:example:main#ready"
    })[0]
  assert_eq(exact.original, None)
  assert_eq(exact.requested, Some("wanted"))
  assert_eq(exact.allocated, "wanted")
  assert_eq(exact.reason, "explicit-request")
  let warning = output.warnings.filter(w => {
      w.code == "moonbit_backend.name_collision"
    })[0]
  assert_eq(warning.locations.length(), 2)
  let driver = @generator.invocation_driver(output, ["example:main#ready"])
  guard driver[2].content is Text(text) else { fail("driver") }
  assert_true(text.contains("@model.wanted()"))
  guard output.artifacts[3].content is Binary(bytes) else { fail("manifest") }
  let manifest = @ion_text.write_ion(@ion_binary.read_binary_value(bytes[:]))
  assert_true(manifest.contains("consumed_naming_facts"))
  assert_true(manifest.contains("morphir_linked_metadata_v1::"))
  assert_true(manifest.contains("requested"))
  assert_true(manifest.contains("example/annotations"))
}

///|
test "known exact requests fail clearly when invalid conflicting or unavailable" {
  for requested in ["if", "Ready", "not-valid", "_", "a.b", ""] {
    let input = named_input(
      "[" + @metadata_fixtures.row("ready", backend=requested) + "]",
    )
    try {
      ignore(
        @generator.generate(
          input,
          metadata_capabilities=@metadata_fixtures.capabilities(),
        ),
      )
      fail("invalid request")
    } catch {
      @generator.Invalid(code, owner, fix) => {
        assert_eq(code, "metadata.invalid_target_request")
        assert_eq(owner, "value:example:main#ready")
        assert_true(fix.contains("backend.moonbit"))
      }
      other => raise other
    }
  }
  let duplicate = named_input(
    "[" +
    @metadata_fixtures.row("ready") +
    "," +
    @metadata_fixtures.row("copy") +
    "]",
  )
  try {
    ignore(
      @generator.generate(
        duplicate,
        metadata_capabilities=@metadata_fixtures.capabilities(),
      ),
    )
    fail("conflicting requests")
  } catch {
    @generator.Invalid(code, owner, fix) => {
      assert_eq(code, "metadata.conflicting_target_request")
      assert_true(fix.contains("value:example:main#"))
      assert_true(owner.has_prefix("value:example:main#"))
    }
    other => raise other
  }
  try {
    ignore(
      @generator.generate(
        named_input("[" + @metadata_fixtures.row("ready") + "]"),
      ),
    )
    fail("missing admission")
  } catch {
    @generator.Invalid(code, _, _) =>
      assert_eq(code, "metadata.provider_unavailable")
    other => raise other
  }
}

///|
test "same-language frontend facts remain hints distinct from exact requests" {
  let input = named_input(
    "[" + @metadata_fixtures.row("ready", backend="chosen") + "]",
  )
  let marked = {
    ..input,
    provenance: [
      @ion_text.read_ion(
        "morphir_moonbit_frontend::{unit_id:\"sample\",language:\"moonbit\"}",
      ),
    ],
  }
  let output = @generator.generate(
    marked,
    metadata_capabilities=@metadata_fixtures.capabilities(),
  )
  let allocation = output.naming_allocations.filter(a => {
      a.owner == "value:example:main#ready"
    })[0]
  assert_eq(allocation.original, Some("isReady"))
  assert_eq(allocation.candidate, "isReady")
  assert_eq(allocation.requested, Some("chosen"))
  assert_eq(allocation.allocated, "chosen")
  let legacy = @generator.generate(
    marked,
    naming=@generator.LegacyHex,
    metadata_capabilities=@metadata_fixtures.capabilities(),
  )
  assert_eq(
    legacy.symbols.filter(s => s.fqname == "example:main#ready")[0].generated_name,
    "chosen",
  )
  assert_eq(
    legacy.symbols.filter(s => s.fqname == "example:main#wanted")[0].generated_name,
    @generator.value_name(@ir.FQName::parse("example:main#wanted")),
  )
}

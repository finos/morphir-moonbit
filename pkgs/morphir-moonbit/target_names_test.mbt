///|
fn source(output : @generator.Output) -> String raise {
  guard output.artifacts[2].content is Text(text) else { fail("source") }
  text
}

///|
test "readable names agree across source symbols invocation driver and manifest" {
  let output = @generator.generate(
    @generator.Input::new("scalars", @fixtures.library()),
  )
  let symbol = output.symbols.filter(s => s.fqname == "pricing:scalars#enabled")[0]
  assert_eq(symbol.generated_name, "enabled")
  assert_true(source(output).contains("pub fn enabled()"))
  assert_eq(
    output.invocations.filter(e => e.fqname == symbol.fqname)[0].generated_name,
    "enabled",
  )
  let driver = @generator.invocation_driver(output, [symbol.fqname])
  guard driver[2].content is Text(driver_source) else { fail("driver") }
  assert_true(driver_source.contains("@model.enabled()"))
  guard output.artifacts[3].content is Binary(bytes) else { fail("manifest") }
  let manifest = @ion_binary.read_binary_value(bytes[:])
  assert_true(
    @ion_text.write_ion(manifest).contains("moonbit-readable-targets-v1"),
  )
  assert_true(@ion_text.write_ion(manifest).contains("naming_allocations"))
}

///|
test "namespace keyword and occupied recovery candidates are deterministic" {
  let input = @generator.Input::new("naming", @fixtures.naming_library())
  let output = @generator.generate(input)
  let reversed = @generator.generate({
    ..input,
    ir: @fixtures.naming_library(reverse=true),
  })
  assert_eq(output.artifacts, reversed.artifacts)
  assert_eq(output.naming_allocations, reversed.naming_allocations)
  assert_eq(output.warnings, reversed.warnings)
  let names = Map::from_array(
    output.symbols.map(s => (s.fqname, s.generated_name)),
  )
  assert_eq(names["naming:main#copy"], "main_copy")
  assert_eq(
    output.warnings
    .filter(w => w.locations.any(l => l.owner == "value:naming:main#copy"))
    .length(),
    1,
  )
  assert_true(names["naming:other#copy"].has_prefix("other_copy_source_"))
  assert_eq(names["naming:main#other-copy"], "other_copy")
  assert_false(names["naming:main#if"] == names["naming:main#if-value"])
  let allocated = output.symbols.map(s => s.generated_name)
  assert_eq(
    Map::from_array(allocated.map(n => (n, true))).length(),
    allocated.length(),
  )
  assert_true(
    output.warnings.any(w => w.code == "moonbit_backend.name_collision"),
  )
  assert_true(output.warnings.all(w => w.stage == "backend" && w.fix != ""))
  for warning in output.warnings {
    for loc in warning.locations {
      let a = output.naming_allocations.filter(a => a.owner == loc.owner)[0]
      assert_eq(loc.allocated, a.allocated)
    }
  }
}

///|
test "locals reserve global values user spellings and generated-looking temporaries" {
  let output = @generator.generate(
    @generator.Input::new("naming", @fixtures.naming_library()),
  )
  let emitted = source(output)
  assert_true(emitted.contains("let argument_2 = argument_1"))
  assert_true(emitted.contains("let function_2 ="))
  assert_true(emitted.contains("let ready_local"))
  assert_true(emitted.contains("ready()"))
  assert_false(emitted.contains("x_617267756d656e74"))
}

///|
test "MoonBit original spelling is an automatic hint only with matching provenance" {
  let input = @generator.Input::new("scalars", @fixtures.library())
  let owner = "value:pricing:scalars#enabled"
  let data = @ion_text.read_ion(
    "unknown::{declaration:{name:\"isReady\",start_line:1,start_column:2,end_line:1,end_column:9}}",
  )
  let marked = {
    ..input,
    metadata: [{ node_id: owner, data, }],
    provenance: [
      @ion_text.read_ion(
        "morphir_moonbit_frontend::{unit_id:\"scalars\",language:\"moonbit\"}",
      ),
    ],
  }
  let output = @generator.generate(marked)
  assert_eq(
    output.symbols.filter(s => s.source_node == owner)[0].generated_name,
    "isReady",
  )
  let unmarked = @generator.generate({ ..marked, provenance: [], })
  assert_eq(
    unmarked.symbols.filter(s => s.source_node == owner)[0].generated_name,
    "enabled",
  )
  let stale = @generator.generate({
    ..marked,
    provenance: [
      @ion_text.read_ion(
        "morphir_moonbit_frontend::{unit_id:\"different\",language:\"moonbit\"}",
      ),
    ],
  })
  assert_eq(
    stale.symbols.filter(s => s.source_node == owner)[0].generated_name,
    "enabled",
  )
  guard output.artifacts[3].content is Binary(bytes) else { fail("manifest") }
  assert_true(
    @ion_text.write_ion(@ion_binary.read_binary_value(bytes[:])).contains(
      "unknown::",
    ),
  )
}

///|
test "legacy mode keeps old exported ABI without decoding old source identities" {
  let input = @generator.Input::new("naming", @fixtures.naming_library())
  let output = @generator.generate(input, naming=@generator.LegacyHex)
  for symbol in output.symbols {
    assert_eq(
      symbol.generated_name,
      @generator.value_name(@ir.FQName::parse(symbol.fqname)),
    )
  }
  assert_eq(output.naming_style, @generator.LegacyHex)
  assert_true(source(output).contains("x_"))
  assert_eq(output.warnings, [])
  let encoded = single(
    @fixtures.scalar("morphir/SDK:basics#bool"),
    @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::BoolLiteral(true)),
  )
  guard encoded.ir.distribution is Library(_, _, definition) else {
    fail("library")
  }
  let access = definition.modules[@ir.Path::parse("main")]
  let values = access.value.values
  let value = values[@ir.Name::parse("value")]
  values.remove(@ir.Name::parse("value"))
  values[@ir.Name::parse("source-69735265616479")] = value
  let readable = @generator.generate(encoded)
  assert_eq(readable.symbols[0].fqname, "sample:main#source-69735265616479")
  assert_eq(readable.symbols[0].generated_name, "source_69735265616479")
}

///|
test "unusable source hints warn with spans and underscore spellings remain usable" {
  let input = @generator.Input::new("scalars", @fixtures.library())
  let marked = {
    ..input,
    metadata: [
      {
        node_id: "value:pricing:scalars#enabled",
        data: @ion_text.read_ion(
          "{declaration:{name:\"invalid-name\",start_line:3,start_column:7,end_line:3,end_column:19}}",
        ),
      },
    ],
    provenance: [
      @ion_text.read_ion(
        "morphir_moonbit_frontend::{unit_id:\"scalars\",frontend:\"moonbit-model-bool-v1\"}",
      ),
    ],
  }
  let recovered = @generator.generate(marked)
  let warning = recovered.warnings.filter(w => {
      w.locations.any(l => l.owner == "value:pricing:scalars#enabled")
    })[0]
  assert_eq(warning.code, "moonbit_backend.name_recovery")
  assert_eq(warning.locations[0].original, "invalid-name")
  assert_eq(warning.locations[0].allocated, "enabled")
  assert_eq(warning.locations[0].source.unwrap().start_column, 7)
  let underscore = @generator.generate({
    ..marked,
    metadata: [
      {
        node_id: "value:pricing:scalars#enabled",
        data: @ion_text.read_ion("{declaration:{name:\"_ready\"}}"),
      },
    ],
  })
  assert_eq(
    underscore.symbols.filter(s => s.fqname == "pricing:scalars#enabled")[0].generated_name,
    "_ready",
  )
  assert_false(
    underscore.warnings.any(w => {
      w.locations.any(l => l.owner == "value:pricing:scalars#enabled")
    }),
  )
}

///|
test "function-local hint namespaces are independent and ambiguous origins are ignored" {
  let input = @generator.Input::new("naming", @fixtures.naming_library())
  let marked = {
    ..input,
    metadata: [
      {
        node_id: "value:naming:main#capture",
        data: @ion_text.read_ion(
          "{parameters:[{identity:\"argument-1\",name:\"firstInput\"},{identity:\"argument-1\",name:\"otherInput\"}]}",
        ),
      },
    ],
    provenance: [
      @ion_text.read_ion(
        "morphir_moonbit_frontend::{unit_id:\"naming\",language:\"moonbit\"}",
      ),
    ],
  }
  let output = @generator.generate(marked)
  let argument = output.naming_allocations.filter(a => {
      a.owner == "value:naming:main#capture/local/argument-1"
    })[0]
  assert_eq(argument.original, None)
  assert_eq(argument.allocated, "argument_1")
  let other = output.naming_allocations.filter(a => {
      a.owner == "value:naming:main#second-capture/local/argument-1"
    })[0]
  assert_eq(other.allocated, "argument_1")
  assert_true(source(output).contains("let record_2 ="))
  assert_false(source(output).contains("firstInput"))
  assert_false(source(output).contains("otherInput"))
}

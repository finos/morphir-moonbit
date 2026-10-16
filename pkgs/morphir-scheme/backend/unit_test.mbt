///|
fn ion_record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::new(
    @ion.Struct(fields.map(pair => @ion.Field::new(pair.0, pair.1))),
  )
}

///|
fn symbol_fields(value : @ion.IonValue) -> Map[String, @ion.IonValue] raise {
  guard value.kind() is @ion.Struct(fields) else {
    fail("Expected an Ion record")
  }
  let result = Map([])
  for field in fields {
    result[field.name().text().unwrap()] = field.value()
  }
  result
}

///|
fn sidecar(output : @backend.Output) -> Map[String, @ion.IonValue] raise {
  symbol_fields(@ion_binary.read_binary_value(output.symbols[:]))
}

///|
fn ion_strings(value : @ion.IonValue) -> Array[String] raise {
  guard value.kind() is @ion.List(items) else { fail("Expected an Ion list") }
  let result = []
  for item in items {
    guard item.kind() is @ion.String(text) else { fail("Expected Ion strings") }
    result.push(text)
  }
  result
}

///|
/// Ion values derive Debug but not Eq: a matcher value that uses `IonValue::equals`.
fn ion(expected : @ion.IonValue) -> @expect.Matcher[@ion.IonValue] {
  {
    describe: () => @debug.to_string(expected),
    check: value => {
      if value.equals(expected) {
        None
      } else {
        Some("differs from the expected Ion value")
      }
    },
  }
}

///|
/// Every symbol of the sidecar as (fqname, generated_name, scheme_symbol, public, source_node, generated_node, origins).
fn symbol_rows(
  output : @backend.Output,
) -> Array[(String, String, String, Bool, String, String, Array[String])] raise {
  guard sidecar(output)["symbols"].kind() is @ion.List(symbols) else {
    fail("Expected symbols")
  }
  let rows = []
  for symbol in symbols {
    let f = symbol_fields(symbol)
    guard f["fqname"].kind() is @ion.String(fqname) else { fail("fqname") }
    guard f["generated_name"].kind() is @ion.String(generated) else {
      fail("generated_name")
    }
    guard f["scheme_symbol"].kind() is @ion.String(scheme_symbol) else {
      fail("scheme_symbol")
    }
    guard f["public"].kind() is @ion.Bool(public) else { fail("public") }
    guard f["source_node"].kind() is @ion.String(source_node) else {
      fail("source_node")
    }
    guard f["generated_node"].kind() is @ion.String(generated_node) else {
      fail("generated_node")
    }
    rows.push(
      (
        fqname,
        generated,
        scheme_symbol,
        public,
        source_node,
        generated_node,
        ion_strings(f["origins"]),
      ),
    )
  }
  rows
}

///|
fn value_def(
  access : @ir.Access,
  body : @ir.Value,
) -> @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] {
  {
    access,
    value: {
      doc: None,
      value: @ir.ValueDefinition::ExpressionBody(
        [],
        @ir.Type::Unit(@ir.TypeAttributes::default()),
        body,
      ),
    },
  }
}

///|
/// `test:main#main` (public) then `test:main#helper` (private).
fn sample_package() -> @ir.PackageDefinition raise {
  {
    modules: Map::from_array([
      (
        @ir.Path::parse("main"),
        {
          access: @ir.Access::Public,
          value: {
            types: Map([]),
            doc: None,
            values: Map::from_array([
              (name("main"), value_def(@ir.Access::Public, int("42"))),
              (name("helper"), value_def(@ir.Access::Private, int("1"))),
            ]),
          },
        },
      ),
    ]),
  }
}

///|
fn sample_unit() -> @backend.Input raise {
  let ir = @ir.IRFile::new(
    @ir.Distribution::Library(
      @ir.Path::parse("test"),
      Map([]),
      sample_package(),
    ),
  )
  {
    unit_id: "Main",
    ir,
    metadata: [
      {
        node_id: "value:test:main#main",
        data: @ion.IonValue::string("origin"),
      },
      {
        node_id: "value:test:main#main/body",
        data: ion_record([("nodes", @ion.IonValue::list([]))]),
      },
    ],
    annotations: [@ion.SymbolToken::new("morphir_pipeline")],
    provenance: [
      ion_record([("frontend", @ion.IonValue::string("test-v1"))]).with_annotation(
        @ion.SymbolToken::new("morphir_test_frontend"),
      ),
    ],
  }
}

///|
test "emit_unit without metadata gives the emit_file text and an empty sidecar" {
  let ir = file(
    @ir.ValueDefinition::ExpressionBody(
      [],
      @ir.Type::Unit(@ir.TypeAttributes::default()),
      int("42"),
    ),
  )
  let output = @backend.emit_unit(@backend.Input::new("Main", ir))
  let stored = @ion_binary.read_binary_value(output.symbols[:])
  let fields = symbol_fields(stored)
  @expect.expect_all(s => {
    s.expect(output.source, label="source").to_equal(@backend.emit_file(ir))
    s
    .expect(stored.annotations().map(a => a.text()), label="annotations")
    .to_equal([Some("morphir_scheme_symbols")])
    s
    .expect(fields, label="sidecar")
    .value_at("profile")
    .to(ion(@ion.IonValue::string(@backend.SYMBOLS_PROFILE)))
    s
    .expect(fields, label="sidecar")
    .value_at("naming_policy")
    .to(ion(@ion.IonValue::string("scheme-canonical-identity-v1")))
    s
    .expect(fields, label="sidecar")
    .value_at("unit_id")
    .to(ion(@ion.IonValue::string("Main")))
    s
    .expect(fields, label="sidecar")
    .value_at("metadata")
    .to(ion(@ion.IonValue::list([])))
    s
    .expect(fields, label="sidecar")
    .value_at("source_provenance")
    .to(ion(@ion.IonValue::list([])))
    s
    .expect(fields, label="sidecar")
    .value_at("source_annotations")
    .to(ion(@ion.IonValue::list([])))
    s.expect(@backend.SYMBOLS_SUFFIX, label="suffix").to_equal(".symbols.10n")
  })
}

///|
test "the sidecar is byte-stable, reads back and keeps the unit's metadata unchanged" {
  let unit = sample_unit()
  let first = @backend.emit_unit(unit)
  let second = @backend.emit_unit(unit)
  let stored = @ion_binary.read_binary_value(first.symbols[:])
  let fields = symbol_fields(stored)
  guard fields["metadata"].kind() is @ion.List(entries) else {
    fail("Expected metadata entries")
  }
  @expect.expect_all(s => {
    s.expect(second.symbols, label="second run").to_equal(first.symbols)
    s
    .expect(@ion_binary.write_binary_value(stored), label="re-encoded")
    .to_equal(first.symbols)
    s
    .expect(fields, label="sidecar")
    .value_at("source_provenance")
    .to(ion(@ion.IonValue::list(unit.provenance)))
    s
    .expect(fields, label="sidecar")
    .value_at("source_annotations")
    .to(ion(@ion.IonValue::list([@ion.IonValue::symbol("morphir_pipeline")])))
    s.expect(entries, label="metadata").to_have_length(unit.metadata.length())
    for pair in entries.zip(unit.metadata) {
      let entry = symbol_fields(pair.0)
      s
      .expect(entry, label=pair.1.node_id)
      .value_at("node_id")
      .to(ion(@ion.IonValue::string(pair.1.node_id)))
      s
      .expect(entry, label=pair.1.node_id)
      .value_at("data")
      .to(ion(pair.1.data))
    }
    s
    .expect(ion_strings(fields["source_nodes"]), label="source_nodes")
    .to_contain_all([
      "unit:Main", "value:test:main#main", "value:test:main#helper",
    ])
  })
}

///|
test "the sidecar lists every define with identity names and access" {
  @expect.expect(symbol_rows(@backend.emit_unit(sample_unit()))).to_contain_exactly([
      (
        "test:main#main",
        "test:main#main",
        "r:test:main#main",
        true,
        "value:test:main#main",
        "scheme:define:test:main#main",
        ["value:test:main#main", "value:test:main#main/body"],
      ),
      (
        "test:main#helper",
        "test:main#helper",
        "r:test:main#helper",
        false,
        "value:test:main#helper",
        "scheme:define:test:main#helper",
        ["value:test:main#helper", "value:test:main#helper/body"],
      ),
    ],
  )
}

///|
test "an application lists its dependency defines first" {
  let ir = @ir.IRFile::new(
    @ir.Distribution::Application(
      @ir.Path::parse("app"),
      Map::from_array([(@ir.Path::parse("test"), sample_package())]),
      sample_package(),
      Map([]),
    ),
  )
  let output = @backend.emit_unit(@backend.Input::new("App", ir))
  @expect.expect_all(s => {
    s.expect(output.source, label="source").to_equal(@backend.emit_file(ir))
    s
    .expect(symbol_rows(output).map(row => row.0), label="fqnames")
    .to_contain_exactly([
      "test:main#main", "test:main#helper", "app:main#main", "app:main#helper",
    ])
  })
}

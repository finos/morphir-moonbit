///|
fn file(output : @elm.Output, path : String) -> String {
  match output.files.search_by(f => f.path == path) {
    Some(i) => output.files[i].content
    None => abort("no file " + path)
  }
}

///|
fn parses(source : String) -> Bool {
  @krueger.parse_module(@krueger.SourceText::new(source)).diagnostics.is_empty()
}

///|
test "rentals generate a package project" {
  let output = @elm.generate(
    "rentals",
    @fixtures.rentals(),
    @elm.Options::default(),
  )
  assert_eq(output.package_name, "morphir/example-app")
  assert_eq(output.files.map(f => f.path), [
    "src/Morphir/Example/App/Rentals.elm", "elm.json", "morphir.json",
  ])
  let source = file(output, "src/Morphir/Example/App/Rentals.elm")
  assert_true(source.contains("request : Int -> Int -> Result String Int"))
  assert_true(source.contains("if requestedQuantity <= availability then"))
  assert_true(source.contains("Ok requestedQuantity"))
  assert_true(parses(source))
  let elm_json = @json.parse(file(output, "elm.json")) catch { _ => panic() }
  assert_eq(elm_json.value("type").unwrap().as_string(), Some("package"))
  assert_eq(
    elm_json.value("name").unwrap().as_string(),
    Some("morphir/example-app"),
  )
  assert_eq(output.dependencies, [
    { name: "elm/core", range: "1.0.5 <= v < 2.0.0", },
  ])
  let morphir_json = @json.parse(file(output, "morphir.json")) catch {
    _ => panic()
  }
  assert_eq(
    morphir_json.value("name").unwrap().as_string(),
    Some("Morphir.Example.App"),
  )
  assert_eq(
    morphir_json.value("sourceDirectory").unwrap().as_string(),
    Some("src"),
  )
}

///|
test "both profiles parse back for every fixture" {
  for ir in [@fixtures.rentals(), @fixtures.shapes()] {
    for profile in [@elm.Profile::Model, Literal] {
      let output = @elm.generate("corpus", ir, {
        ..@elm.Options::default(),
        profile,
      })
      for f in output.files {
        if f.role is Source {
          assert_true(parses(f.content), msg=f.path)
        }
      }
    }
  }
}

///|
test "unmapped SDK references add the SDK Elm package" {
  let output = @elm.generate("rentals", @fixtures.rentals(), {
    ..@elm.Options::default(),
    profile: Literal,
  })
  assert_true(
    output.dependencies.contains({
      name: "finos/morphir-elm",
      range: "22.0.2 <= v < 23.0.0",
    }),
  )
}

///|
test "output is deterministic" {
  let first = @elm.generate(
    "shapes",
    @fixtures.shapes(),
    @elm.Options::default(),
  )
  let second = @elm.generate(
    "shapes",
    @fixtures.shapes(),
    @elm.Options::default(),
  )
  assert_eq(first.files, second.files)
}

///|
test "specifications need the debug-todo policy" {
  let refused = try {
    ignore(@elm.generate("specs", @fixtures.specs(), @elm.Options::default()))
    []
  } catch {
    Failed(problems) => problems.map(p => p.code)
    _ => ["other"]
  }
  assert_eq(refused, ["elm.placeholder"])
  let output = @elm.generate("specs", @fixtures.specs(), {
    ..@elm.Options::default(),
    placeholders: DebugTodo,
  })
  let source = file(output, "src/Acme/Api/Limits.elm")
  assert_true(
    source.contains("@morphir.annotation { fqname = \"acme/api:tags#stable\" }"),
  )
  assert_true(source.contains("type Token\n    = TokenOpaque"))
  assert_true(parses(source))
}

///|
test "every failing module is reported" {
  let refused = try {
    ignore(@elm.generate("rates", @fixtures.refused(), @elm.Options::default()))
    []
  } catch {
    Failed(problems) => problems.map(p => p.code + " " + p.node_path)
    _ => ["other"]
  }
  assert_eq(refused, [
    "elm.decimal_literal acme/rates:first#rate", "elm.decimal_literal acme/rates:second#rate",
  ])
}

///|
test "cancellation stops generation" {
  let refused = try {
    ignore(
      @elm.generate("shapes", @fixtures.shapes(), @elm.Options::default(), cancelled=fn() {
        true
      }),
    )
    ""
  } catch {
    Failed(problems) => problems[0].code
    _ => "other"
  }
  assert_eq(refused, "elm.cancelled")
}

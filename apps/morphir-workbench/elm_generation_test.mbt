///|
test "Elm target retains the full package and local Scheme execution" {
  let result = @pipeline.execute({
    "operation": "run",
    "source": "(+ 20 22)",
    "languageId": "scheme",
    "target": "elm",
  })
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_eq(@wire.field(result, "value"), @wire.text("42"))
  assert_true(@wire.field(result, "ir") != Json::null())
  let artifacts = @wire.array(@wire.field(result, "artifacts"))
  assert_eq(artifacts.length(), 3)
  let source = artifacts.filter(a => {
      @wire.string(@wire.field(a, "path")).has_suffix(".elm")
    })[0]
  assert_eq(@wire.field(source, "path"), @wire.text("src/User/Main.elm"))
  assert_true(
    @wire.string(@wire.field(source, "content")).contains("module User.Main"),
  )
  assert_true(@wire.string(@wire.field(source, "content")).contains("20 + 22"))
  assert_eq(@wire.field(source, "binary"), Json::boolean(false))
  let manifest = artifacts.filter(a => {
      @wire.field(a, "path") == @wire.text("elm.json")
    })[0]
  let elm = @json.parse(@wire.string(@wire.field(manifest, "content")))
  assert_eq(@wire.field(elm, "type"), @wire.text("package"))
  assert_eq(
    @wire.field(elm, "exposed-modules"),
    Json::array([@wire.text("User.Main")]),
  )
  assert_eq(
    artifacts
    .filter(a => @wire.field(a, "path") == @wire.text("morphir.json"))
    .length(),
    1,
  )
}

///|
test "Elm refusal preserves compiled IR and exact diagnostics" {
  let result = @pipeline.execute({
    "operation": "compile",
    "source": "18446744073709551616",
    "target": "elm",
  })
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_true(@wire.field(result, "ir") != Json::null())
  assert_true(
    @wire.string(@wire.field(result, "generationMessage")).contains(
      "elm.int_literal",
    ),
  )
  let diagnostics = @wire.array(@wire.field(result, "generationDiagnostics"))
  assert_eq(@wire.field(diagnostics[0], "code"), @wire.text("elm.int_literal"))
  assert_true(
    @wire.string(@wire.field(diagnostics[0], "nodePath")).has_prefix(
      "user:main#main",
    ),
  )
  assert_eq(@wire.field(result, "artifacts"), Json::array([]))
}

///|
test "unavailable local language and generation target never silently fall back" {
  let requests : Array[Json] = [
    {
      "operation": "compile",
      "source": "(+ 1 2)",
      "languageId": "elm",
      "target": "elm",
    },
    { "operation": "compile", "source": "(+ 1 2)", "target": "unavailable" },
  ]
  for request in requests {
    let result = @pipeline.execute(request)
    assert_eq(@wire.field(result, "success"), Json::boolean(false))
    assert_true(
      @wire.string(@wire.field(result, "message")).contains("unavailable"),
    )
  }
  let result = @pipeline.execute({
    "operation": "compile",
    "source": "(+ 1 2)",
    "target": "",
  })
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_true(@wire.optional(result, "generated") is None)
}

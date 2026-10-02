///|
fn elm_files(options : String) -> Map[String, String] raise {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Shapes'\n[frontend]\nlanguage='ir-json'\n[pipeline]\nbackend='elm'\n" +
      options,
    ),
    ("src/main.json", @ir_json.write(@elm_fixtures.shapes())),
  ])
}

///|
fn elm_report(options : String) -> @engine.ContentReport raise {
  let engine = @engine.Engine::new()
  let files = elm_files(options)
  let plan = engine.plan(
    @engine.Host::memory(files),
    @workspace.discover({ files, directories: ["", "src"], }),
    @engine.Request::new(),
  )
  engine.execute_content(plan, fn(_, _) { @data.Text(files["src/main.json"]) })
}

///|
fn error_text(e : Error) -> String {
  match e {
    @configuration.Invalid(message) => message
    @elm.ElmGenerationError::Refused(p) => p.code + ": " + p.detail
    @elm.ElmGenerationError::Failed(problems) =>
      problems.map(p => p.code + ": " + p.detail).join("\n")
    _ => e.to_string()
  }
}

///|
test "elm generation writes an Elm package project" {
  let report = elm_report("")
  if !report.successful() {
    fail(report.diagnostics[0].message)
  }
  let paths = report.artifacts.map(a => a.path)
  assert_true(paths.any(p => p.has_suffix("src/Acme/Shapes/Geometry.elm")))
  assert_true(paths.any(p => p.has_suffix("elm.json")))
  assert_eq(report.projects.length(), 1)
  assert_eq(report.projects[0].build_contract, "elm-package-v1")
  assert_eq(report.projects[0].policy, @engine.SourceOnly)
}

///|
test "backend options reach the generator" {
  let report = elm_report("[backends.elm]\nprofile='literal'\n")
  assert_true(report.successful())
  let geometry = report.artifacts
    .search_by(a => a.path.has_suffix("Geometry.elm"))
    .unwrap()
  guard report.artifacts[geometry].content is @data.Text(text) else {
    fail("text")
  }
  assert_true(text.contains("Morphir.SDK.Basics.multiply"))
}

///|
test "invalid elm options fail at planning" {
  let failed = try {
    ignore(elm_report("[backends.elm]\ncolour='red'\n"))
    ""
  } catch {
    e => error_text(e)
  }
  assert_true(failed.contains("elm.invalid_option"), msg=failed)
}

///|
test "elm generation refuses required validation" {
  let failed = try {
    ignore(elm_report("validation='required'\n"))
    ""
  } catch {
    e => error_text(e)
  }
  assert_true(failed.contains("build.unsupported_target"), msg=failed)
}

///|
test "the MoonBit fixture corpus generates Elm or names its refusals" {
  let allowed = [
    "elm.decimal_literal", "elm.document_literal", "elm.int_literal", "elm.literal_pattern",
    "elm.placeholder", "elm.tuple_arity", "elm.derived_type", "elm.unsupported_constraint",
    "elm.name_collision",
  ]
  for
    ir in [
      @fixtures.library(),
      @fixtures.pricing(),
      @fixtures.acceptance_library(),
      @fixtures.invocation_library(),
    ] {
    let result = Ok(@elm.generate("corpus", ir, @elm.Options::default())) catch {
      Failed(problems) => Err(problems)
      Refused(p) => Err([p])
    }
    match result {
      Ok(output) =>
        for f in output.files {
          if f.role is Source {
            assert_true(
              @krueger.parse_module(@krueger.SourceText::new(f.content)).diagnostics.is_empty(),
              msg=f.path,
            )
          }
        }
      Err(problems) =>
        for p in problems {
          assert_true(
            allowed.contains(p.code),
            msg=p.code + " " + p.node_path + ": " + p.detail,
          )
        }
    }
  }
}

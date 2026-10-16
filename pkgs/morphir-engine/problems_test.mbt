///|
fn location(line : Int32) -> @ir.SourceLocation {
  { start_line: line, start_column: 1, end_line: line, end_column: 6, }
}

///|
test "a project frontend rejection keeps each problem's code, path and range" {
  let engine = project_engine(
    project_profile(fn(_, _, _) raise {
      raise @engine.RejectedSources([
        {
          code: "x.first",
          detail: "first",
          path: "Api.model",
          location: Some(location(2)),
        },
        {
          code: "x.second",
          detail: "second",
          path: "Nested/Util.model",
          location: None,
        },
      ])
    }),
  )
  let files = project_files()
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
  )
  @expect.expect_all(s => {
    let diagnostics = s.expect(report.diagnostics, label="diagnostics")
    diagnostics.to_have_length(2)
    let first = diagnostics.first()
    first.get("path", d => d.path).to_equal("src/Api.model")
    first.get("code", d => d.code()).to_equal(Some("x.first"))
    first
    .get("start line", d => d.location().map(l => l.start_line))
    .to_equal(Some(2))
    first.to_satisfy(
      d => {
        d.problem is Some(Source({ detail, .. })) && detail.has_prefix("first")
      },
      description="a source problem whose detail starts with first",
    )
    let second = diagnostics.element(1)
    second.get("path", d => d.path).to_equal("src/Nested/Util.model")
    second.get("location", d => d.location()).to_be_none()
  })
}

///|
fn rich_report(
  compile : (@engine.Source, String, () -> Bool) -> @data.IRUnit raise,
) -> @engine.ContentReport raise {
  let engine = @engine.Engine::new()
  engine.register_unit_frontend("rich", [".model"], compile)
  let files = rich_files()
  engine.execute_content(rich_plan(engine, files), fn(path, _) {
    @data.Text(files[path])
  })
}

///|
test "a per-file rejection becomes a source problem of that file" {
  let report = rich_report(fn(_, _, _) raise {
    raise @engine.Rejected("x.bad", "bad input", Some(location(3)))
  })
  @expect.expect_all(s => {
    let diagnostic = s.expect(report.diagnostics, label="diagnostics").single()
    diagnostic.get("path", d => d.path).to_equal("src/Main.model")
    diagnostic.get("code", d => d.code()).to_equal(Some("x.bad"))
    diagnostic
    .get("start line", d => d.location().map(l => l.start_line))
    .to_equal(Some(3))
    diagnostic.to_satisfy(
      d => d.problem is Some(Source({ path: "Main.model", .. })),
      description="a source problem of Main.model",
    )
    diagnostic.get("message", d => d.message).to_start_with("x.bad: bad input")
  })
}

///|
test "a diagnostic without a known cause has no problem" {
  let report = rich_report(fn(_, _, _) raise { fail("plain failure") })
  @expect.expect_all(s => {
    let diagnostic = s.expect(report.diagnostics, label="diagnostics").single()
    diagnostic.to_satisfy(d => d.problem is None, description="no problem")
    diagnostic.get("code", d => d.code()).to_be_none()
  })
}

///|
/// Property: a project rejection with any list of problems gives one diagnostic per problem, in order, each with
/// that problem's code, file and range.
test "every rejected problem becomes one diagnostic, in order" {
  @expect.for_all(
    (shape : Array[(UInt32, Bool)]) => {
      // Each element is one problem: which file (of two), and whether it has a range.
      let problems : Array[@engine.SourceProblem] = shape.mapi((i, item) => {
        let (file, ranged) = item
        {
          code: "x.p" + i.to_string(),
          detail: "problem " + i.to_string(),
          path: if file % 2 == 0 {
            "Api.model"
          } else {
            "Nested/Util.model"
          },
          location: if ranged {
            Some(location(i + 1))
          } else {
            None
          },
        }
      })
      guard !problems.is_empty() else { return }
      let engine = project_engine(
        project_profile(fn(_, _, _) raise {
          raise @engine.RejectedSources(problems)
        }),
      )
      let files = project_files()
      let report = engine.execute_content(
        project_plan(engine, files),
        project_read(files),
      )
      @expect.expect(
        report.diagnostics.map(d => {
          (d.code(), d.path, d.location().map(l => l.start_line))
        }),
      ).to_equal(
        problems.map(p => {
          (Some(p.code), "src/" + p.path, p.location.map(l => l.start_line))
        }),
      )
    },
    count=25,
  )
}

///|
test "on_unit gets the compiled unit of each source before generation" {
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      {
        ..@data.IRUnit::new(id, @fixtures.pricing()),
        metadata: [
          {
            node_id: "value:pricing:scalars#rate/body",
            data: @ion.IonValue::string("hint"),
          },
        ],
      }
    }),
  )
  let files = project_files()
  let seen : Array[@engine.CompiledUnit] = []
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
    on_unit=compiled => seen.push(compiled),
  )
  @expect.expect_all(s => {
    s
    .expect(report.diagnostics.map(d => d.message), label="diagnostics")
    .to_be_empty()
    let unit = s.expect(seen, label="units").single()
    unit.get("source", c => c.source).to_equal("src")
    unit.get("metadata", c => c.unit.metadata.length()).to_equal(1)
  })
}

///|
test "on_unit is not called for a source that the frontend rejects" {
  let engine = project_engine(
    project_profile(fn(_, _, _) raise {
      raise @engine.Rejected("x.bad", "bad", None)
    }),
  )
  let files = project_files()
  let seen : Array[String] = []
  ignore(
    engine.execute_content(project_plan(engine, files), project_read(files), on_unit=c => {
      seen.push(c.source)
    }),
  )
  @expect.expect(seen, label="units").to_be_empty()
}

///|
test "on_unit gets a plain unit for a plain frontend and backend" {
  let engine = @engine.Engine::new()
  let files = generation_files("scheme", language="ir-json")
  let seen : Array[@engine.CompiledUnit] = []
  let report = engine.execute_content(
    generation_plan(engine, files),
    fn(path, _) { @data.Text(files[path]) },
    on_unit=c => seen.push(c),
  )
  @expect.expect_all(s => {
    s
    .expect(report.diagnostics.map(d => d.message), label="diagnostics")
    .to_be_empty()
    let unit = s.expect(seen, label="units").single()
    unit.get("source", c => c.source).to_equal("src/main.json")
    unit.get("metadata", c => c.unit.metadata.length()).to_equal(0)
  })
}

///|
fn scheme_files(backend : String, source : String) -> Map[String, String] {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='user'\n[frontend]\nlanguage='scheme'\n[pipeline]\nbackend='" +
      backend +
      "'\nvalidation='source-only'",
    ),
    ("src/main.scm", source),
  ])
}

///|
fn run_scheme(
  backend : String,
  source : String,
) -> (@engine.ContentReport, Array[@engine.CompiledUnit]) raise {
  let engine = @engine.Engine::new()
  let files = scheme_files(backend, source)
  let seen : Array[@engine.CompiledUnit] = []
  let report = engine.execute_content(
    generation_plan(engine, files),
    fn(path, _) { @data.Text(files[path]) },
    on_unit=c => seen.push(c),
  )
  (report, seen)
}

///|
fn generation_problem(d : @engine.Diagnostic) -> @engine.GenerationProblem? {
  match d.problem {
    Some(Generation(problem)) => Some(problem)
    _ => None
  }
}

///|
test "an Elm generation refusal gives a generation problem and keeps the unit" {
  let (report, seen) = run_scheme("elm", "18446744073709551616")
  @expect.expect_all(s => {
    s.expect(seen.length(), label="units").to_equal(1)
    s.expect(report.artifacts.length(), label="artifacts").to_equal(0)
    let diagnostic = s.expect(report.diagnostics, label="diagnostics").first()
    diagnostic.get("stage", d => d.stage).to_equal("backend")
    diagnostic.get("path", d => d.path).to_equal("src/main.scm")
    diagnostic.get("code", d => d.code()).to_equal(Some("elm.int_literal"))
    diagnostic
    .get("message", d => d.message)
    .to_start_with("elm.int_literal at ")
    diagnostic
    .get("node path", d => {
      generation_problem(d).map(p => p.node_path).unwrap_or("")
    })
    .to_start_with("user:main#main")
  })
}

///|
test "a MoonBit generation refusal gives a generation problem" {
  let (report, _) = run_scheme("moonbit", "(lambda (x) x)")
  @expect.expect_all(s => {
    let diagnostic = s.expect(report.diagnostics, label="diagnostics").first()
    diagnostic.get("stage", d => d.stage).to_equal("backend")
    diagnostic
    .get("code", d => d.code().unwrap_or(""))
    .to_start_with("moonbit.")
    diagnostic.to_satisfy(
      d => d.message.has_prefix(d.code().unwrap_or("?") + " at "),
      description="a message that starts with its code and node",
    )
  })
}

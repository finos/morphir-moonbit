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

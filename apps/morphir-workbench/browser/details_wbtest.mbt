///|
test "a failed compile keeps its job context on the log, the output and the report" {
  let model = { ..ready_model(), panel: @bottom_panel.State::new(), }
  let reply : Json = {
    "success": false,
    "message": "elm.parse: Unexpected token",
    "code": "elm.parse",
    "stage": "frontend",
    "frontendDiagnostics": [
      {
        "path": "src/Workbench/Main.elm",
        "problems": [
          {
            "code": "elm.parse",
            "coordinateProfile": "elm-source-position-v1",
            "detail": "Unexpected token",
            "source": {
              "startLine": 3,
              "startColumn": 7,
              "endLine": 3,
              "endColumn": 8,
            },
            "stage": "frontend",
          },
        ],
      },
    ],
    "irSource": "{\"secret\": \"model\"}",
  }
  let after = initialized_compile(model, reply)
  let failures = [
    after.panel.logs.last().bind(l => l.failure),
    after.panel.outcomes.last().bind(o => o.failure),
    after.panel.reports.last().bind(r => r.failure),
  ]
  @expect.expect_all(s => {
    for found in failures {
      match found {
        Some(failure) => {
          s.expect(failure.code, label="code").to_equal("elm.parse")
          s.expect(failure.stage, label="stage").to_equal("frontend")
          s.expect(failure.operation, label="operation").to_equal("Compile")
          s
          .expect(failure.context.map(pair => pair.0), label="context")
          .to_contain_all([
            "Language", "Profile", "Provider", "Target", "Project", "Source revision",
            "Duration",
          ])
          s
          .expect(
            failure.context
            .filter(pair => pair.0 == "Project")
            .map(pair => pair.1),
            label="project",
          )
          .to_equal(["Workbench (1 file)"])
          s
          .expect(failure.raw, label="raw keeps the code")
          .to_contain("elm.parse")
          s
          .expect(failure.raw, label="raw omits models")
          .not()
          .to_contain("secret")
          s
          .expect(failure.raw, label="raw says what it omitted")
          .to_contain("<omitted: ")
        }
        None =>
          s
          .expect(found is Some(_), label="every panel has the failure")
          .to_be_true()
      }
    }
  })
}

///|
test "redaction replaces source and models with their size" {
  let redacted_reply = redacted({
    "success": false,
    "project": { "files": [{ "path": "src/A.elm", "content": "module A" }] },
    "message": "kept",
    "frontendDiagnostic": { "source": { "startLine": 3 } },
  })
  @expect.expect(redacted_reply.stringify()).to_equal(
    (
      {
        "success": false,
        "project": {
          "files": [
            { "path": "src/A.elm", "content": "<omitted: 10 characters>" },
          ],
        },
        "message": "kept",
        "frontendDiagnostic": { "source": { "startLine": 3 } },
      } : Json).stringify(),
  )
}

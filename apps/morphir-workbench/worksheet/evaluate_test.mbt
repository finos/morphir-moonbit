///|
fn evaluate(source : String) -> Json raise {
  @worksheet.WorksheetRequest::decode(request(source)).evaluate().to_json()
}

///|
test "worksheet shares definitions and preserves exact expression spans" {
  let captured = @worksheet.WorksheetRequest::decode(
    request("(define x 40)\n(+ x 2)"),
  )
  let report = captured.evaluate().to_json()
  assert_eq(@wire.field(report, "observations"), [
    {
      "id": "form-0",
      "range": { "start": 0, "end": 13 },
      "expression": "(define x 40)",
      "preview": "#<unit>",
      "outcome": { "status": "returned", "value": { "type": "unit" } },
    },
    {
      "id": "form-1",
      "range": { "start": 14, "end": 21 },
      "expression": "(+ x 2)",
      "preview": "42",
      "outcome": {
        "status": "returned",
        "value": { "type": "int", "value": "42" },
      },
    },
  ])
  assert_eq(
    @worksheet.WorksheetReport::decode(captured, report.stringify()).to_json(),
    report,
  )
  assert_eq(@wire.field(evaluate("x"), "completion"), {
    "status": "failed",
    "failure": {
      "stage": "evaluate",
      "code": "worksheet.evaluation_failed",
      "message": "Unbound identifier: x",
    },
  })
}

///|
test "unavailable rational projection continues without fabricating text values" {
  let report = evaluate("1/3\n(+ 1 2)")
  let rows = @wire.array(@wire.field(report, "observations"))
  assert_eq(@wire.field(rows[0], "outcome"), {
    "status": "failed",
    "failure": {
      "stage": "evaluate",
      "code": "worksheet.value_unsupported",
      "message": "This Scheme value has no portable worksheet representation.",
    },
  })
  assert_eq(@wire.field(rows[0], "preview"), Json::string("1/3"))
  assert_eq(@wire.field(rows[1], "outcome"), {
    "status": "returned",
    "value": { "type": "int", "value": "3" },
  })
  assert_eq(@wire.field(report, "completion"), {
    "status": "returned",
    "value": { "type": "unit" },
  })
}

///|
test "parse failure wins before any valid or failing prefix can execute" {
  let report = evaluate("missing\n(+ 1")
  assert_eq(@wire.field(report, "observations"), Json::array([]))
  assert_eq(@wire.field(report, "completion"), {
    "status": "failed",
    "failure": {
      "stage": "evaluate",
      "code": "worksheet.read_failed",
      "message": "Syntax at character 12: Unclosed list",
    },
  })
  assert_eq(@wire.field(report, "diagnostic"), {
    "stage": "read",
    "range": { "start": 12, "end": 12 },
  })
}

///|
test "runtime failure retains the completed prefix and stops the suffix" {
  let report = evaluate("1\nmissing\n2")
  let rows = @wire.array(@wire.field(report, "observations"))
  assert_eq(rows.length(), 2)
  assert_eq(@wire.field(rows[1], "outcome"), @wire.field(report, "completion"))
  assert_eq(@wire.field(rows[1], "preview"), Json::string(""))
}

///|
test "supplied report rejects forged ranges before source reveal" {
  let captured = @worksheet.WorksheetRequest::decode(request("(+ 1 2)"))
  let report = captured.evaluate().to_json().stringify()
  let forged = report.replace(old="\"end\":7", new="\"end\":6")
  let code = try {
    @worksheet.WorksheetReport::decode(captured, forged) |> ignore
    "accepted"
  } catch {
    @execution.Invalid(code) => code
    _ => "unexpected"
  }
  assert_eq(code, "worksheet.invalid_range")
}

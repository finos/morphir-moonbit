///|
fn output_request(value : Json, expected : Json) -> Json {
  {
    "id": 1,
    "op": "validate-output",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.4",
    "format": "json",
    "input": { "value": value, "type": expected, "definitions": [] },
  }
}

///|
test "output admission distinguishes domain outcomes from typed Result Err" {
  let error : Json = { "type": "model-error", "code": "sdk.division_by_zero" }
  let request = output_request(error, { "type": "int" })
  assert_eq(@mck.handle(request), { "id": 1, "status": "ok", "value": error })
  let result : Json = {
    "type": "result",
    "case": "err",
    "value": { "type": "bool", "value": false },
  }
  assert_eq(
    @mck.handle(
      output_request(result, {
        "type": "result",
        "ok": { "type": "int" },
        "err": { "type": "bool" },
      }),
    ),
    { "id": 1, "status": "ok", "value": result },
  )
  assert_eq(@mck.handle(output_request(result, { "type": "int" })), {
    "id": 1,
    "status": "invalid",
    "code": "execution.wrong_type",
  })
}

///|
test "model outcomes cannot bypass declaration admission or nested typing" {
  let error : Json = { "type": "model-error", "code": "sdk.division_by_zero" }
  assert_eq(
    @mck.handle(output_request(error, { "type": "custom", "name": "missing" })),
    { "id": 1, "status": "invalid", "code": "execution.unresolved_custom_type" },
  )
  assert_eq(@mck.handle(output_request(error, { "type": "function" })), {
    "id": 1,
    "status": "invalid",
    "code": "execution.boundary_function",
  })
  assert_eq(
    @mck.handle(
      output_request({ "type": "list", "items": [error] }, {
        "type": "list",
        "item": { "type": "int" },
      }),
    ),
    { "id": 1, "status": "invalid", "code": "execution.wrong_type" },
  )
  assert_eq(
    @mck.handle(
      output_request({ "type": "model-error", "code": "provider.crash" }, {
        "type": "int",
      }),
    ),
    { "id": 1, "status": "invalid", "code": "execution.model_error_code" },
  )
}

///|
test "output operation is exact draft and retains input admission" {
  let error : Json = { "type": "model-error", "code": "sdk.out_of_range" }
  let request = output_request(error, { "type": "int" })
  guard request is Object(fields) else { fail("object") }
  fields["op"] = Json::string("validate-value")
  assert_eq(@mck.handle(request), {
    "id": 1,
    "status": "invalid",
    "code": "execution.model_error_argument",
  })
  fields["op"] = Json::string("validate-output")
  for version in ["0.1.0-draft.1", "0.1.0-draft.2", "0.1.0-draft.3"] {
    fields["contractVersion"] = Json::string(version)
    assert_eq(@mck.handle(request), {
      "id": 1,
      "status": "invalid",
      "code": "workbench.invalid_request",
    })
  }
}

///|
test "Ion output returns canonical exact values and model outcomes" {
  for
    (source, value) in [
      (
        "9007199254740993",
        ({ "type": "int", "value": "9007199254740993" } : Json),
      ),
      (
        "morphir_value::{type:\"model-error\",code:\"sdk.invalid_number\"}",
        ({ "type": "model-error", "code": "sdk.invalid_number" } : Json),
      ),
    ] {
    let request = output_request(value, { "type": "int" })
    guard request is Object(fields) else { fail("object") }
    fields["format"] = Json::string("ion-text")
    fields["input"] = {
      "value": source,
      "type": { "type": "int" },
      "definitions": [],
    }
    assert_eq(@mck.handle(request), { "id": 1, "status": "ok", "value": value })
  }
}

///|
test "draft4 capability and output input budgets are bounded" {
  assert_eq(
    @mck.handle({
      "id": 7,
      "op": "capabilities",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.4",
    }),
    {
      "id": 7,
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.4",
      "binding": "morphir-moonbit",
      "language": "moonbit",
      "operations": [
        "decode-value", "validate-value", "validate-invocations", "validate-output",
      ],
      "formats": ["json", "ion-text"],
    },
  )
  let value : Json = { "type": "model-error", "code": "sdk.division_by_zero" }
  let request = output_request(value, { "type": "int" })
  guard request is Object(fields) else { fail("object") }
  fields["format"] = Json::string("ion-text")
  fields["input"] = {
    "value": " ".repeat(1024 * 1024),
    "type": { "type": "int" },
    "definitions": [],
  }
  assert_eq(@mck.handle(request), {
    "id": 1,
    "status": "invalid",
    "code": "workbench.input_limit",
  })
  fields["input"] = {
    "value": "{",
    "type": { "type": "int" },
    "definitions": [],
  }
  assert_eq(@mck.handle(request), {
    "id": 1,
    "status": "invalid",
    "code": "workbench.invalid_ion",
  })
}

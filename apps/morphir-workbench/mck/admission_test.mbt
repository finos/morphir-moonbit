///|
fn admission_request(
  format : String,
  value : Json,
  expected : Json,
  definitions : Json,
) -> Json {
  {
    "id": 9,
    "op": "validate-value",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.2",
    "format": format,
    "input": { "value": value, "type": expected, "definitions": definitions },
  }
}

///|
test "draft 2 advertises decode and declared admission without changing draft 1" {
  assert_eq(
    @mck.handle({
      "id": 1,
      "op": "capabilities",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.2",
    }),
    {
      "id": 1,
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.2",
      "binding": "morphir-moonbit",
      "language": "moonbit",
      "operations": ["decode-value", "validate-value"],
      "formats": ["json", "ion-text"],
    },
  )
}

///|
test "declared arguments keep exact projections in JSON and Ion" {
  let expected : Json = { "type": "int" }
  let canonical : Json = { "type": "int", "value": "9007199254740993" }
  for
    (format, value) in [
      ("json", canonical),
      ("ion-text", Json::string("9007199254740993")),
    ] {
    assert_eq(@mck.handle(admission_request(format, value, expected, [])), {
      "id": 9,
      "status": "ok",
      "value": canonical,
    })
  }
}

///|
test "declaration admission closes dormant types and rejects ambiguous registries" {
  let cases : Array[(Json, Json, Json, String)] = [
    (
      { "type": "list", "items": [] },
      { "type": "list", "item": { "type": "custom", "name": "missing" } },
      [],
      "execution.unresolved_custom_type",
    ),
    (
      { "type": "maybe", "case": "nothing" },
      { "type": "maybe", "item": { "type": "function" } },
      [],
      "execution.boundary_function",
    ),
    (
      { "type": "unit" },
      { "type": "unit", "extra": true },
      [],
      "workbench.invalid_type",
    ),
    (
      { "type": "record", "fields": [] },
      {
        "type": "record",
        "fields": [
          { "name": "x", "type": { "type": "int" } },
          { "name": "x", "type": { "type": "bool" } },
        ],
      },
      [],
      "workbench.invalid_type",
    ),
    (
      { "type": "unit" },
      { "type": "unit" },
      [{ "name": "x", "constructors": [] }, { "name": "x", "constructors": [] }],
      "workbench.invalid_definitions",
    ),
    (
      { "type": "unit" },
      { "type": "unit" },
      [
        {
          "name": "x",
          "constructors": [
            { "name": "c", "inputs": [] },
            { "name": "c", "inputs": [] },
          ],
        },
      ],
      "workbench.invalid_definitions",
    ),
    (
      { "type": "unit" },
      { "type": "unit" },
      [
        {
          "name": "unused",
          "constructors": [
            { "name": "c", "inputs": [{ "type": "custom", "name": "missing" }] },
          ],
        },
      ],
      "execution.unresolved_custom_type",
    ),
    (
      { "type": "unit" },
      { "type": "unit" },
      [
        {
          "name": "unused",
          "constructors": [{ "name": "c", "inputs": [{ "type": "function" }] }],
        },
      ],
      "execution.boundary_function",
    ),
    ({ "type": "unit" }, { "type": "int" }, [], "execution.wrong_type"),
    (
      { "type": "model-error", "code": "sdk.division_by_zero" },
      { "type": "int" },
      [],
      "execution.model_error_argument",
    ),
  ]
  for (value, expected, definitions, code) in cases {
    assert_eq(
      @mck.handle(admission_request("json", value, expected, definitions)),
      { "id": 9, "status": "invalid", "code": code },
    )
  }
}

///|
test "recursive constructors and ordinary Result Err are admitted" {
  let definitions : Json = [
    {
      "name": "list",
      "constructors": [
        { "name": "nil", "inputs": [] },
        {
          "name": "cons",
          "inputs": [{ "type": "int" }, { "type": "custom", "name": "list" }],
        },
      ],
    },
  ]
  let value : Json = {
    "type": "custom",
    "owner": "list",
    "tag": "cons",
    "items": [
      { "type": "int", "value": "1" },
      { "type": "custom", "owner": "list", "tag": "nil", "items": [] },
    ],
  }
  assert_eq(
    @mck.handle(
      admission_request(
        "json",
        value,
        { "type": "custom", "name": "list" },
        definitions,
      ),
    ),
    { "id": 9, "status": "ok", "value": value },
  )
  let err : Json = {
    "type": "result",
    "case": "err",
    "value": { "type": "bool", "value": false },
  }
  assert_eq(
    @mck.handle(
      admission_request(
        "json",
        err,
        { "type": "result", "ok": { "type": "int" }, "err": { "type": "bool" } },
        [],
      ),
    ),
    { "id": 9, "status": "ok", "value": err },
  )
}

///|
test "admission limits apply before dormant declaration validation" {
  let mut expected : Json = { "type": "int" }
  for _ in 0..<65 {
    expected = { "type": "list", "item": expected }
  }
  assert_eq(
    @mck.handle(
      admission_request("json", { "type": "list", "items": [] }, expected, []),
    ),
    { "id": 9, "status": "invalid", "code": "workbench.type_limit" },
  )
  let fields : Array[Json] = []
  for i in 0..<1025 {
    fields.push({ "name": i.to_string(), "type": { "type": "unit" } })
  }
  assert_eq(
    @mck.handle(
      admission_request(
        "json",
        { "type": "unit" },
        { "type": "record", "fields": fields },
        [],
      ),
    ),
    { "id": 9, "status": "invalid", "code": "workbench.type_limit" },
  )
  assert_eq(
    @mck.handle(
      admission_request(
        "ion-text",
        Json::string("0".repeat(1024 * 1024)),
        { "type": "int" },
        [],
      ),
    ),
    { "id": 9, "status": "invalid", "code": "workbench.input_limit" },
  )
}

///|
test "old draft cannot claim admission and new declarations keep duplicate framing guards" {
  let old = admission_request("json", { "type": "unit" }, { "type": "unit" }, [])
  guard old is Object(fields) else { fail("request object") }
  fields["contractVersion"] = Json::string("0.1.0-draft.1")
  assert_eq(@mck.handle(Json::object(fields)), {
    "id": 9,
    "status": "invalid",
    "code": "workbench.invalid_request",
  })
  assert_eq(
    @mck.handle_line(
      "{\"id\":9,\"op\":\"validate-value\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.2\",\"format\":\"json\",\"input\":{\"value\":{\"type\":\"unit\"},\"type\":{\"type\":\"unit\",\"type\":\"int\"},\"definitions\":[]}}",
    ),
    Some({ "id": 9, "status": "invalid", "code": "workbench.invalid_request" }),
  )
}

///|
test "type aggregate and inline depth boundaries are finite across every target" {
  let mut expected : Json = { "type": "int" }
  for _ in 0..<64 {
    expected = { "type": "list", "item": expected }
  }
  assert_eq(
    @mck.handle(
      admission_request("json", { "type": "list", "items": [] }, expected, []),
    ),
    { "id": 9, "status": "ok", "value": { "type": "list", "items": [] } },
  )
  let items : Array[Json] = []
  let group : Json = {
    "type": "tuple",
    "items": Array::make(9, Json::object({ "type": "unit" })),
  }
  for _ in 0..<999 {
    items.push(group)
  }
  // The declared graph passes at 9,991 nodes; the actual value then fails its type.
  assert_eq(
    @mck.handle(
      admission_request(
        "json",
        { "type": "unit" },
        { "type": "tuple", "items": items },
        [],
      ),
    ),
    { "id": 9, "status": "invalid", "code": "execution.wrong_type" },
  )
  items.push(group)
  assert_eq(
    @mck.handle(
      admission_request(
        "json",
        { "type": "unit" },
        { "type": "tuple", "items": items },
        [],
      ),
    ),
    { "id": 9, "status": "invalid", "code": "workbench.type_limit" },
  )
}

///|
test "all declaration identities use the UTF16 budget diagnostic" {
  let long_name = "\u{1F600}".repeat(513)
  let cases : Array[(Json, Json)] = [
    ({ "type": "custom", "name": long_name }, []),
    (
      {
        "type": "record",
        "fields": [{ "name": long_name, "type": { "type": "unit" } }],
      },
      [],
    ),
    ({ "type": "unit" }, [{ "name": long_name, "constructors": [] }]),
    (
      { "type": "unit" },
      [{ "name": "x", "constructors": [{ "name": long_name, "inputs": [] }] }],
    ),
    (
      { "type": "unit" },
      [
        {
          "name": "x",
          "constructors": [
            { "name": "c", "inputs": [{ "type": "custom", "name": long_name }] },
          ],
        },
      ],
    ),
  ]
  for (expected, definitions) in cases {
    assert_eq(
      @mck.handle(
        admission_request("json", { "type": "unit" }, expected, definitions),
      ),
      { "id": 9, "status": "invalid", "code": "workbench.type_limit" },
    )
  }
  let name = "\u{1F600}".repeat(512)
  let value : Json = {
    "type": "custom",
    "owner": name,
    "tag": name,
    "items": [],
  }
  assert_eq(
    @mck.handle(
      admission_request("json", value, { "type": "custom", "name": name }, [
        { "name": name, "constructors": [{ "name": name, "inputs": [] }] },
      ]),
    ),
    { "id": 9, "status": "ok", "value": value },
  )
}

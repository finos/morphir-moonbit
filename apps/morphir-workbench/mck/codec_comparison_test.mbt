///|
fn codec_request(operation : String, input : Json) -> Json {
  @mck.handle({
    "id": 1,
    "op": operation,
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.26",
    "format": "json",
    "input": input,
  })
}

///|
test "codec kit transcodes actual invocation bytes across all destinations" {
  let suite : Json = {
    "profile": "morphir-invocations-v1",
    "calls": [
      {
        "id": "exact",
        "entry": "codec:main#identity",
        "arguments": [{ "type": "int", "value": "9007199254740993" }],
      },
    ],
  }
  for target in ["json", "ion-text", "ion-binary"] {
    assert_eq(
      codec_request("transcode-invocations", {
        "sourceFormat": "json",
        "source": { "utf8": suite.stringify() },
        "targetFormat": target,
      }),
      {
        "id": 1,
        "status": "ok",
        "value": { "targetFormat": target, "invocations": suite },
      },
    )
  }
}

///|
test "codec kit rejects duplicate raw suite members before projection" {
  assert_eq(
    codec_request("transcode-invocations", {
      "sourceFormat": "json",
      "source": {
        "utf8": "{\"profile\":\"morphir-invocations-v1\",\"calls\":[],\"calls\":[]}",
      },
      "targetFormat": "ion-binary",
    }),
    { "id": 1, "status": "invalid", "code": "execution.invalid_field" },
  )
}

///|
test "comparison kit uses normalized Decimal and escaped mismatch pointers" {
  assert_eq(
    codec_request("compare-values", {
      "actual": { "type": "decimal", "coefficient": "1250", "exponent": -2 },
      "expected": { "type": "decimal", "coefficient": "125", "exponent": -1 },
      "comparison": { "profile": "morphir-comparison-exact-v1" },
    }),
    {
      "id": 1,
      "status": "ok",
      "value": { "matches": true, "mismatchPath": Json::null() },
    },
  )
  assert_eq(
    codec_request("compare-values", {
      "actual": {
        "type": "record",
        "fields": [
          { "name": "a/b~c", "value": { "type": "bool", "value": true } },
        ],
      },
      "expected": {
        "type": "record",
        "fields": [
          { "name": "a/b~c", "value": { "type": "bool", "value": false } },
        ],
      },
      "comparison": { "profile": "morphir-comparison-exact-v1" },
    }),
    {
      "id": 1,
      "status": "ok",
      "value": { "matches": false, "mismatchPath": "/a~1b~0c" },
    },
  )
}

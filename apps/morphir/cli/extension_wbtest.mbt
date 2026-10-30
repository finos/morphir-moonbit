///|
let extension_test_digest : String = "a".repeat(64)

///|
fn extension_test_pin(
  runtime~ : Json = {
    "kind": "process",
    "platform": "aarch64-apple-darwin",
    "args": ["--serve", ""],
  },
) -> Map[String, Json] {
  {
    "contractVersion": "0.2.0",
    "artifact": { "path": "/opt/guest/morphir-extension", "sha256": extension_test_digest },
    "runtime": runtime,
    "origin": "finos/morphir-moonbit apps/morphir-extension",
  }
}

///|
fn extension_test_refusal(value : Json) -> (String, String, Int32) {
  try {
    ignore(ExtensionPin::decode(value, Posix))
    ("decoded", "", 0)
  } catch {
    ExtensionError(status~, code~, message~) =>
      (code.name(), message, status.exit_code())
  }
}

///|
test "a contract 0.2.0 pin decodes into a worker specification" {
  let pin = ExtensionPin::decode(Json::object(extension_test_pin()), Posix)
  assert_eq(
    pin.spec.runtime,
    Process(platform=Aarch64AppleDarwin, args=["--serve", ""]),
  )
  assert_eq(pin.spec.artifact.sha256.to_string(), extension_test_digest)
  assert_eq(pin.descriptor, None)
  assert_eq(pin.origin, "finos/morphir-moonbit apps/morphir-extension")
  let described = extension_test_pin()
  described["descriptor"] = {
    "path": "/opt/guest/release.json",
    "sha256": "b".repeat(64),
  }
  let pin = ExtensionPin::decode(Json::object(described), Posix)
  assert_true(pin.descriptor is Some(_))
  let wasm = extension_test_pin(runtime={
    "kind": "wasm",
    "abi": "extism-kernel-v1",
  })
  assert_eq(
    ExtensionPin::decode(Json::object(wasm), Posix).spec.runtime,
    Wasm(abi=Some(ExtismKernelV1)),
  )
}

///|
test "a pin with an unknown field, a relative path or no digest is refused" {
  let host = extension_test_pin()
  host["host"] = { "root": "/tools" }
  let (code, message, status) = extension_test_refusal(Json::object(host))
  assert_eq(code, "extension.pin_invalid")
  assert_eq(status, 2)
  assert_true(message.contains("host"), msg=message)
  let relative = extension_test_pin()
  relative["artifact"] = { "path": "guest/morphir-extension", "sha256": extension_test_digest }
  assert_eq(extension_test_refusal(Json::object(relative)).0, "extension.pin_invalid")
  let undigested = extension_test_pin()
  undigested["artifact"] = { "path": "/opt/guest/morphir-extension" }
  assert_eq(extension_test_refusal(Json::object(undigested)).0, "extension.pin_invalid")
  let no_origin = extension_test_pin()
  no_origin.remove("origin")
  assert_eq(extension_test_refusal(Json::object(no_origin)).0, "extension.pin_invalid")
  let mixed = extension_test_pin(runtime={
    "kind": "process",
    "platform": "aarch64-apple-darwin",
    "args": [],
    "abi": "extism-kernel-v1",
  })
  assert_eq(extension_test_refusal(Json::object(mixed)).0, "extension.pin_invalid")
  assert_eq(extension_test_refusal([1, 2]).0, "extension.pin_invalid")
}

///|
test "old pin contracts are retired with a pointer to the migration" {
  for contract in ["0.1.0", "0.1.0-draft.1"] {
    let old : Json = {
      "contractVersion": contract,
      "binding": "core-wasm-process",
      "origin": "old",
    }
    let (code, message, status) = extension_test_refusal(old)
    assert_eq(code, "extension.pin_retired")
    assert_eq(status, 2)
    assert_true(message.contains("0.2.0"), msg=message)
    assert_true(message.contains(extension_migration), msg=message)
  }
  let future : Json = { "contractVersion": "0.3.0" }
  assert_eq(extension_test_refusal(future).0, "extension.pin_invalid")
}

///|
test "retired helper options are refused before a pin is read" {
  for option in ["--extension-helper", "--node"] {
    let cli = parse_cli([
      "extension", "describe", option, "/tools/helper", "--extension-pin", "pin.json",
    ])
    let refusal = try {
      extension_retired_options(cli)
      None
    } catch {
      ExtensionError(status~, code~, message~) => Some((status, code, message))
    }
    guard refusal is Some((status, code, message)) else {
      fail("\{option} was accepted")
    }
    assert_eq(status.exit_code(), 2)
    assert_eq(code.name(), "extension.option_retired")
    assert_true(message.contains(option), msg=message)
    assert_true(message.contains(extension_migration), msg=message)
  }
  extension_retired_options(
    parse_cli(["extension", "describe", "--extension-pin", "pin.json"]),
  )
}

///|
test "the exit table maps each status in both output modes" {
  assert_eq(Refused.exit_code(), 2)
  assert_eq(Failed.exit_code(), 1)
  assert_eq(TimedOut.exit_code(), 124)
  assert_eq(Cancelled.exit_code(), 130)
  let report = ExtensionReport::failure(
    Compile,
    refused(Worker(ClaimsMismatch), "the descriptor claims differ"),
  )
  assert_eq(report.exit_code(), 2)
  assert_eq(
    report.to_json().stringify(),
    "{\"profile\":\"morphir/command-result\",\"contractVersion\":\"0.1.0\",\"command\":\"extension.compile\",\"state\":\"failed\",\"exitCode\":2,\"diagnostics\":[],\"error\":{\"code\":\"extension.claims_mismatch\",\"message\":\"the descriptor claims differ\"}}",
  )
}

///|
fn extension_test_claims(
  frontend~ : Json = {
    "languages": [{ "id": "gleam", "fileExtensions": [".gleam"] }],
    "irVersions": ["4"],
    "compile": true,
  },
  backend? : Json,
  tuples~ : Array[Json] = [],
  protocol? : String,
) -> Json {
  let capabilities : Map[String, Json] = { "frontend": frontend }
  if backend is Some(backend) {
    capabilities["backend"] = backend
  }
  if !tuples.is_empty() {
    capabilities["modelTransport"] = {
      "tuples": Json::array(tuples),
      "limits": {
        "maxEncodedBytes": 5592408,
        "maxDecodedBytes": 4194304,
        "maxDepth": 128,
        "maxNodes": 100000,
      },
      "guarantees": [],
    }
  }
  let result : Map[String, Json] = {
    "extension": { "id": "fixture-gleam", "version": "1.0.0" },
    "capabilities": Json::object(capabilities),
  }
  match protocol {
    Some(line) => result["protocolVersion"] = Json::string(line)
    None =>
      result["protocolVersions"] = if tuples.is_empty() {
        ["0.1"]
      } else {
        ["0.2.0-draft.1", "0.1"]
      }
  }
  Json::object(result)
}

///|
fn extension_test_tuple(operation : String, codec : String) -> Json {
  {
    "operation": operation,
    "profile": if codec == "ion-binary" { "morphir-model" } else { "morphir-ir" },
    "codec": codec,
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  }
}

///|
test "compile selects sources by the claimed file extensions and sends the claimed language" {
  let claims = @worker.Claims::from_describe(extension_test_claims())
  let documents = [
    ExtensionSource::{ uri: "src/app.gleam", text: "pub fn main() { 1 }" },
    ExtensionSource::{ uri: "src/lib.gleam", text: "pub fn lib() { 2 }" },
  ]
  let (language, selected) = extension_language(claims, documents)
  assert_eq(language.to_string(), "gleam")
  assert_eq(selected.map(document => document.uri), [
    "src/app.gleam", "src/lib.gleam",
  ])
  assert_eq(extension_claimed_extensions(claims), [".gleam"])
  let refusal = try {
    ignore(extension_language(claims, []))
    ""
  } catch {
    ExtensionError(code~, ..) => code.name()
  }
  assert_eq(refusal, "extension.input_invalid")
}

///|
test "an operation that the extension does not claim is refused before any call" {
  let claims = @worker.Claims::from_describe(extension_test_claims())
  let refusal = try {
    ignore(extension_generate_offer(claims, None))
    None
  } catch {
    ExtensionError(status~, code~, ..) => Some((status.exit_code(), code.name()))
  }
  assert_eq(refusal, Some((2, "extension.capability_unavailable")))
  // A frontend with model tuples compiles on the model line; one without
  // compiles on MEP 0.1.
  assert_eq(extension_compile_offer(claims, None), Legacy)
  let model = @worker.Claims::from_describe(
    extension_test_claims(
      frontend={
        "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
        "compile": false,
      },
      tuples=[
        extension_test_tuple("morphir.frontend.compileModel", "morphir-json"),
        extension_test_tuple("morphir.frontend.compileModel", "ion-binary"),
      ],
    ),
  )
  guard extension_compile_offer(model, None) is Model(tuple) else {
    fail("no model offer")
  }
  assert_eq(tuple.codec, IonBinary)
  guard extension_compile_offer(model, Some(MorphirJson)) is Model(tuple) else {
    fail("no model offer")
  }
  assert_eq(tuple.codec, MorphirJson)
}

///|
test "document identities keep relative nesting and never expose absolute host paths" {
  assert_eq(extension_document_uri("src/main.mbt"), "src/main.mbt")
  assert_eq(extension_document_uri("/home/user/src/main.mbt"), "main.mbt")
  assert_eq(extension_document_uri("../src/main.mbt"), "main.mbt")
  assert_eq(extension_document_uri("C:\\work\\main.mbt"), "main.mbt")
  assert_eq(extension_document_uri("./main.mbt"), "main.mbt")
}

///|
test "extension results publish only intact models and confined artifacts" {
  let bytes = b"\xe0\x01\x00\xea"
  let tuple = @worker.ModelTuple::new(
    CompileModel,
    MorphirModel,
    IonBinary,
    V0_1_0Draft1,
    V4_0_0,
  )
  let result : Json = {
    "success": true,
    "model": {
      "envelopeVersion": "0.1.0-draft.1",
      "irVersion": "4.0.0",
      "profile": "morphir-model",
      "payload": {
        "codec": "ion-binary",
        "decodedByteLength": 4,
        "sha256": extension_sha256(bytes),
        "content": @base64.encode(bytes[:]),
      },
    },
  }
  assert_eq(extension_model_bytes(result, tuple).1, bytes)
  let json_tuple = @worker.ModelTuple::new(
    CompileModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    V4_0_0,
  )
  assert_true(
    try {
      ignore(extension_model_bytes(result, json_tuple))
      false
    } catch {
      _ => true
    },
  )
  let tampered = result
    .stringify()
    .replace(old="\"decodedByteLength\":4", new="\"decodedByteLength\":5")
  assert_eq(
    try {
      ignore(extension_model_bytes(@json.parse(tampered), tuple))
      ""
    } catch {
      ExtensionError(code~, ..) => code.name()
      _ => "other"
    },
    "extension.result_invalid",
  )
  let artifact = fn(path : String) -> Json {
    {
      "success": true,
      "artifacts": [{ "path": path, "content": "x", "binary": false }],
    }
  }
  assert_eq(
    extension_artifacts(artifact("mep/source.json"))[0].0,
    "mep/source.json",
  )
  for path in ["../escape", "/abs", "a//b", "a\\b", "c:x", "./a"] {
    assert_true(
      try {
        ignore(extension_artifacts(artifact(path)))
        false
      } catch {
        _ => true
      },
      msg=path,
    )
  }
  let collision : Json = {
    "artifacts": [
      { "path": "a", "content": "x", "binary": false },
      { "path": "a/b", "content": "y", "binary": false },
    ],
  }
  assert_true(
    try {
      ignore(extension_artifacts(collision))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "extension command syntax keeps its own options" {
  let cli = parse_cli([
    "extension", "compile", "src/main.mbt", "--extension-pin", "pin.json", "--package",
    "my/pkg", "--output", "out", "--ir-version", "4", "--model-format", "json", "--json",
  ])
  assert_eq(cli.command, "extension compile")
  assert_eq(value(cli, "path"), "src/main.mbt")
  assert_eq(value(cli, "ir-version"), "4")
  assert_true(flag(cli, "json"))
  for
    args in [
      ["extension", "describe", "--package", "x"],
      ["extension"],
      ["extension", "describe", "--services-pin", "pin.json"],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
      msg=args.join(" "),
    )
  }
}

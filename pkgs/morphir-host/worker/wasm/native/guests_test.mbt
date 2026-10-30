///|
/// The source that both MoonBit guests compile.
let moonbit_source : String =
  #|///|
  #|pub fn add(a : Int, b : Int) -> Int {
  #|  a + b
  #|}

///|
fn compile_params(tuple : @worker.ModelTuple) -> Map[String, Json] {
  let options : Json = { "typesOnly": false, "irVersion": "4.0.0" }
  let context : Json = { "package": "acme/math", "options": options }
  {
    "languageId": "moonbit",
    "sources": {
      "documents": [
        {
          "uri": "math.mbt",
          "languageId": "moonbit",
          "version": 0,
          "text": moonbit_source,
        },
      ],
    },
    "package": { "name": "acme/math" },
    "options": options,
    "contextDigest": @worker.Sha256::of(@utf8.encode(context.stringify())).to_string(),
    "output": tuple.to_json(),
  }
}

///|
fn generate_params(
  envelope : Json,
  tuple : @worker.ModelTuple,
) -> Map[String, Json] {
  let identity : Json = match envelope {
    Object(fields) =>
      {
        "target": "moonbit",
        "modelId": fields.get("modelId").unwrap_or(Json::null()),
        "revision": fields.get("revision").unwrap_or(Json::null()),
      }
    _ => Json::null()
  }
  {
    "model": envelope,
    "input": tuple.to_json(),
    "target": "moonbit",
    "contextDigest": @worker.Sha256::of(@utf8.encode(identity.stringify())).to_string(),
  }
}

///|
/// Describes, compiles and generates with one guest, each in its own
/// session. Returns the compile result and the generate result.
async fn describe_compile_generate(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
) -> (@worker.Claims, Json, Json) {
  let claims = host.probe(spec).claims
  let compile_offer = @worker.Offer::select(
    claims,
    CompileModel,
    profile=MorphirModel,
    codec=IonBinary,
  )
  guard compile_offer is Model(compile_tuple) else { fail("not a model offer") }
  let compiled = host.with_session(spec, expected=claims, offer=compile_offer, session => {
    session.compile(@worker.CompileRequest::new(compile_params(compile_tuple)))
  })
  guard compiled.class is Completed(compiled) else {
    fail("the compile did not complete: \{@debug.to_string(compiled)}")
  }
  guard compiled.result is { "model": envelope, .. } else {
    fail("the compile result has no model: \{compiled.result.stringify()}")
  }
  let generate_offer = @worker.Offer::select(
    claims,
    GenerateModel,
    profile=MorphirModel,
    codec=IonBinary,
  )
  guard generate_offer is Model(generate_tuple) else {
    fail("not a model offer")
  }
  let generated = host.with_session(
    spec,
    expected=claims,
    offer=generate_offer,
    session => {
      session.generate(
        @worker.GenerateRequest::new(generate_params(envelope, generate_tuple)),
      )
    },
  )
  guard generated.class is Completed(generated) else {
    fail("the generate did not complete: \{@debug.to_string(generated)}")
  }
  (claims, compiled.result, generated.result)
}

///|
async test "byte callback adapter: the portable guest returns the same envelopes as the native guest" {
  guard cli() is Some(path) &&
    @env.get_env_var("MORPHIR_PORTABLE_GUEST") is Some(portable) &&
    @env.get_env_var("MORPHIR_NATIVE_GUEST") is Some(native) else {
    return
  }
  let platform = @process.host_platform().unwrap()
  let wasm_bytes = @fs.read_file(portable).binary()
  let native_bytes = @fs.read_file(native).binary()
  let wasm_host = host(path)
  let process_host = @worker.Host::new(
    @process.ProcessLauncher::new(),
    Native(platform),
  )
  let (wasm_claims, wasm_compiled, wasm_generated) = describe_compile_generate(
    wasm_host,
    wasm_spec(wasm_bytes, abi=MorphirBytesV1),
  )
  let (native_claims, native_compiled, native_generated) = describe_compile_generate(
    process_host,
    @worker.WorkerSpec::new(
      @worker.ArtifactRef::new(
        File(@worker.ArtifactPath::parse(native, Posix)),
        @worker.Sha256::of(native_bytes),
      ),
      Process(platform~, args=[]),
    ),
  )
  assert_eq(wasm_claims, native_claims)
  assert_eq(wasm_compiled, native_compiled)
  assert_eq(wasm_generated, native_generated)
  assert_true(wasm_generated.stringify().contains("add"))
}

///|
async test "Python from the native CLI: compile runs in a worker process that is gone afterwards" {
  guard cli() is Some(path) &&
    @env.get_env_var("MORPHIR_PYTHON_EXTENSIONS") is Some(root) else {
    return
  }
  for version in ["0.4.1", "0.4.2"] {
    let bytes = @fs.read_file(
      "\{root}/\{version}/morphir-python-binding-\{version}.wasm",
    ).binary()
    let spec = wasm_spec(bytes, abi=ExtismKernelV1)
    let wasm_host = host(path)
    let claims = wasm_host.probe(spec).claims
    let session = wasm_host.activate(spec, expected=claims, offer=Legacy)
    let outcome = session.compile(
      @worker.CompileRequest::new({
        "languageId": "python",
        "sources": {
          "documents": [
            {
              "uri": "file:///work/acme/models.py",
              "languageId": "python",
              "version": 1,
              "text": "from dataclasses import dataclass\n\n@dataclass(frozen=True)\nclass Approved:\n    amount: float\n",
            },
          ],
        },
        "package": { "name": "acme" },
        "dependencies": [],
        "options": { "irVersion": "4", "typesOnly": false },
      }),
    )
    guard outcome.class is Completed(compiled) else {
      fail("Python \{version} did not compile: \{@debug.to_string(outcome)}")
    }
    assert_true(compiled.result.stringify().contains("\"amount\""))
    let report = session.close()
    guard report.stop is Some(stop) else { fail("no worker stop") }
    // The worker exited after `exit`; the launcher confirmed its group gone.
    assert_eq(stop.status, Exited(code=0))
    assert_eq(report.extism, Some(@worker.ExtismProfile::restricted()))
  }
}

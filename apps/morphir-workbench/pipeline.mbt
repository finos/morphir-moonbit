///|
/// Local adapter envelopes are private to the worker, not Morphir RPC methods.
/// Decode/migrate imports explicitly; the inspector uses the current semantic model.
pub fn execute_with(engine : @engine.Engine, request : Json) -> Json {
  // Where a failure happened, for its reply: reading the request, compiling, building the reply, or reading a model.
  let mut stage = "request"
  try {
    let operation = @wire.string(@wire.field(request, "operation"))
    if operation == "catalog" {
      return catalog(engine)
    }
    if operation == "import-folder" {
      return import_folder(request)
    }
    if operation == "decode-ion" {
      stage = "decode"
      return decode_ion(request)
    }
    if operation == "compile" || operation == "run" {
      let project = project_request(request, engine.languages())
      if operation == "run" && project.language.to_string() != "scheme" {
        raise @scheme.Invalid(
          "Compile, then evaluate a public function in Model Explorer",
        )
      }
      let target = optional_text(request, "target").unwrap_or("scheme")
      stage = "compile"
      let engine_run = run_engine(engine, project, target)
      stage = "reply"
      let result = compile_reply(engine_run, project, target) catch {
        CompileFailed(reply) => return reply
        error => raise error
      }
      if operation == "run" && engine_run.unit is Some(unit) {
        result.push(
          (
            "value",
            @wire.text(
              @scheme.value_to_string(
                @backend.run_file(
                  unit.distribution,
                  @ir.FQName::parse("user:main#main"),
                  [],
                ),
              ),
            ),
          ),
        )
      }
      return @wire.obj(result)
    }
    let source = @wire.string(@wire.field(request, "source"))
    let language = match @wire.optional(request, "languageId") {
      None => "scheme"
      Some(String(language)) => language
      _ => raise @scheme.Invalid("This local input language is unavailable")
    }
    if operation == "worksheet" {
      if language != "scheme" {
        raise @scheme.Invalid("The local worksheet supports Scheme only")
      }
      let runtime = @scheme.Runtime::new()
      let results = @scheme.parse_program(source).map(form => {
        @wire.obj([
          ("expression", @wire.text(form.to_source())),
          (
            "value",
            @wire.text(@scheme.value_to_string(runtime.eval(form.to_source()))),
          ),
        ])
      })
      return @wire.obj([
        ("success", Json::boolean(true)),
        ("results", Json::array(results)),
      ])
    }
    let imported = if operation == "inspect" &&
      @wire.optional(request, "sourceCodec") != None {
      let codec = @wire.string(@wire.field(request, "sourceCodec"))
      guard ["morphir-json", "ion-text", "ion-binary"].contains(codec) else {
        raise @scheme.Invalid("Unsupported model codec")
      }
      let encoded = @wire.string(@wire.field(request, "sourceBase64"))
      guard encoded.length() <= 22369624 else {
        raise @scheme.Invalid("Model import exceeds the 16-MiB limit")
      }
      let bytes = @base64.decode(encoded[:])
      guard bytes.length() <= 16 * 1024 * 1024 else {
        raise @scheme.Invalid("Model import exceeds the 16-MiB limit")
      }
      let registry = @data.Registry::new(limits={
        max_bytes: 16 * 1024 * 1024,
        max_depth: 128,
        max_values: 100000,
      })
      Some(
        registry.open_checkpoint(
          codec,
          if codec == "ion-binary" {
            @data.Binary(bytes)
          } else {
            @data.Text(@utf8.decode(bytes))
          },
        ),
      )
    } else {
      None
    }
    stage = "model"
    let file = if imported is Some(unit) {
      unit.distribution
    } else if operation == "inspect" || operation == "evaluate" {
      @migration.to_current(@versioned.read(source))
    } else {
      raise @scheme.Invalid("Unknown operation: " + operation)
    }
    if operation == "evaluate" {
      stage = "evaluate"
      if @wire.optional(request, "executionMode") == Some(@wire.text("typed")) {
        return evaluate_typed(file, request)
      }
      return evaluate_model(file, request)
    }
    let (package_name, distribution_kind) = match file.distribution {
      Library(name, _, _) => (name, "Library")
      Specs(name, _, _) => (name, "Specification")
      Application(name, _, _, _) => (name, "Application")
    }
    let result = [
      ("success", Json::boolean(true)),
      ("ir", @codec.to_json(file)),
      ("irSource", @wire.text(@codec.to_json(file).stringify())),
      ("nodes", Json::array(describe(file))),
      ("evaluations", evaluation_profiles(file)),
      ("typedEvaluations", typed_profiles(file)),
      ("package", @wire.text(package_name.to_canonical())),
      ("distributionKind", @wire.text(distribution_kind)),
      ("formatVersion", @wire.text(file.format_version.to_release_string())),
    ]
    if imported is Some(unit) {
      source_ui(result, unit.metadata)
      let registry = @data.Registry::new(limits={
        max_bytes: 16 * 1024 * 1024,
        max_depth: 128,
        max_values: 100000,
      })
      match registry.encode("ion-text", unit) {
        Text(source) => result.push(("sourceUnitIon", @wire.text(source)))
        Binary(_) => ()
      }
    }
    @wire.obj(result)
  } catch {
    @ion.Syntax(message) => failure("Ion: " + message, "ion.syntax", stage)
    @ion.DataModel(message) =>
      failure("Ion: " + message, "ion.data_model", stage)
    @ion.Unsupported(message) =>
      failure("Ion: " + message, "ion.unsupported", stage)
    CompileFailed(reply) => reply
    @config.Invalid(message) =>
      failure(message, leading_code(message, "workbench.invalid_input"), stage)
    @protocol.Invalid(code) => failure(code, code, stage)
    @wire.Invalid(code, detail) => codec_failure(stage, code, detail)
    error => failure(@scheme.error_message(error), scheme_code(error), stage)
  }
}

///|
/// The largest binary Ion file the workbench decodes to text: 4 MiB.
pub let ion_input_limit : Int32 = 4 * 1024 * 1024

///|
/// The longest Ion text a decode returns: 4 Mi characters.
pub let ion_text_limit : Int32 = 4 * 1024 * 1024

///|
/// Decodes a binary Ion file (`source`: its bytes in base64) to pretty Ion text. A file that does not start with
/// the Ion binary version marker `E0 01 00 EA` is refused, as are files and texts past their limits. Ion errors
/// reach the caller with their `ion.*` codes.
fn decode_ion(request : Json) -> Json raise {
  let path = optional_text(request, "path").unwrap_or("")
  let encoded = @wire.string(@wire.field(request, "source"))
  let too_large = fn() {
    failure(
      "The file is larger than the 4 MiB that the workbench decodes to Ion text",
      "workbench.ion_input_too_large", "decode",
    )
  }
  if encoded.length() > (ion_input_limit + 2) / 3 * 4 {
    return too_large()
  }
  let bytes = @base64.decode(encoded[:]) catch {
    _ =>
      return failure(
        "The file's content is not valid base64", "workbench.invalid_encoding", "decode",
      )
  }
  if bytes.length() > ion_input_limit {
    return too_large()
  }
  if !@ion_binary.has_binary_version_marker(bytes[:]) {
    return failure(
      "This file is not binary Ion: it does not start with the version marker E0 01 00 EA",
      "workbench.not_binary_ion", "decode",
    )
  }
  let values = @ion_binary.read_binary(bytes[:])
  let text = @ion_text.write_all_pretty(values)
  if text.length() > ion_text_limit {
    return failure(
      "The Ion text of this file is longer than the 4 Mi characters the workbench shows",
      "workbench.ion_text_too_large", "decode",
    )
  }
  @wire.obj([
    ("success", Json::boolean(true)),
    ("operation", @wire.text("decode-ion")),
    ("path", @wire.text(path)),
    ("text", @wire.text(text)),
    ("values", Json::number(values.length().to_double())),
    ("bytes", Json::number(bytes.length().to_double())),
  ])
}

///|
/// A failure reply: the message for a person, a stable code and the stage where it happened.
fn failure(message : String, code : String, stage : String) -> Json {
  @wire.obj([
    ("success", Json::boolean(false)),
    ("message", @wire.text(if message == "" { code } else { message })),
    ("code", @wire.text(code)),
    ("stage", @wire.text(stage)),
  ])
}

///|
/// The code a message starts with, as in `frontend.invalid_source_path: src/../x`, else `fallback`.
fn leading_code(message : String, fallback : String) -> String {
  match message.find(": ") {
    Some(colon) => {
      let head = message.unsafe_substring(start=0, end=colon)
      let code_like = head.contains(".") &&
        head
        .to_array()
        .all(c => {
          (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '.' ||
          c == '_' ||
          c == '-'
        })
      if code_like {
        head
      } else {
        fallback
      }
    }
    None => fallback
  }
}

///|
fn scheme_code(error : Error) -> String {
  match error {
    @scheme.Syntax(_, _) => "scheme.syntax"
    @scheme.Unbound(_) => "scheme.unbound"
    @scheme.Invalid(_) => "scheme.invalid"
    @scheme.Domain(code, _) => if code == "" { "scheme.domain" } else { code }
    @scheme.Unsupported(_) => "scheme.unsupported"
    @scheme.Limit(_) => "scheme.limit"
    @scheme.Stage(_, _) => "scheme.stage"
    _ => "workbench.error"
  }
}

///|
/// A codec error, such as a missing member. In a request or a model it is invalid input; anywhere else the workbench
/// read its own data wrongly, so it is an internal error. The reply never shows a bare key name: it names the stage
/// and keeps the codec's code and detail.
fn codec_failure(stage : String, code : String, detail : String) -> Json {
  let (failure_code, summary) = match stage {
    "request" => ("workbench.invalid_request", "The request is not valid")
    "model" => ("workbench.invalid_model", "The model is not valid")
    "compile" =>
      ("workbench.internal_error", "The workbench failed while compiling")
    "reply" =>
      (
        "workbench.internal_error", "The workbench failed while preparing the compile result",
      )
    _ =>
      (
        "workbench.internal_error",
        "The workbench failed in the " + stage + " stage",
      )
  }
  @wire.obj([
    ("success", Json::boolean(false)),
    ("message", @wire.text(summary + " (" + code + ": " + detail + ")")),
    ("code", @wire.text(failure_code)),
    ("stage", @wire.text(stage)),
    (
      "cause",
      @wire.obj([("code", @wire.text(code)), ("detail", @wire.text(detail))]),
    ),
  ])
}

///|
/// The local worker's entry: one engine with the built-in providers for each request.
pub fn execute(request : Json) -> Json {
  let engine = workbench_engine() catch {
    error =>
      return @wire.obj([
        ("success", Json::boolean(false)),
        (
          "message",
          @wire.text("Engine setup failed: " + @scheme.error_message(error)),
        ),
      ])
  }
  execute_with(engine, request)
}

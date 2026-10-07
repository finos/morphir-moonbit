///|
/// Local adapter envelopes are private to the worker, not Morphir RPC methods.
/// Decode/migrate imports explicitly; the inspector uses the current semantic model.
pub fn execute(request : Json) -> Json {
  try {
    let operation = @wire.string(@wire.field(request, "operation"))
    let source = @wire.string(@wire.field(request, "source"))
    let target = if operation == "compile" || operation == "run" {
      if @wire.optional(request, "languageId") is Some(language) &&
        language != @wire.text("scheme") {
        raise @scheme.Invalid("This local input language is unavailable")
      }
      let target = match @wire.optional(request, "target") {
        None => "scheme"
        Some(String(target)) => target
        _ => raise @scheme.Invalid("This generation target is unavailable")
      }
      if !["", "scheme", "elm"].contains(target) {
        raise @scheme.Invalid(
          "This generation target is unavailable: " + target,
        )
      }
      target
    } else {
      ""
    }
    if operation == "worksheet" {
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
    let file = if operation == "inspect" || operation == "evaluate" {
      @migration.to_current(@versioned.read(source))
    } else if operation == "compile" || operation == "run" {
      @frontend.compile_file(source)
    } else {
      raise @scheme.Invalid("Unknown operation: " + operation)
    }
    if operation == "evaluate" {
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
    if target == "scheme" {
      result.push(("generated", @wire.text(@backend.emit_file(file))))
    } else if target == "elm" {
      let generated = elm_output(file)
      match generated {
        Object(fields) =>
          for key, value in fields {
            result.push((key, value))
          }
        _ => ()
      }
    }
    if operation == "run" {
      result.push(
        (
          "value",
          @wire.text(
            @scheme.value_to_string(
              @backend.run_file(file, @ir.FQName::parse("user:main#main"), []),
            ),
          ),
        ),
      )
    }
    @wire.obj(result)
  } catch {
    @ion.Syntax(message)
    | @ion.DataModel(message)
    | @ion.Unsupported(message) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text("Ion: " + message)),
      ])
    @protocol.Invalid(code) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(code)),
      ])
    @moonbit.Invalid(code, _, detail) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(code + ": " + detail)),
      ])
    @wire.Invalid(_, message) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(message)),
      ])
    error =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(@scheme.error_message(error))),
      ])
  }
}

///|
fn elm_problem(problem : @elm.Problem) -> Json {
  @wire.obj([
    ("code", @wire.text(problem.code)),
    ("nodePath", @wire.text(problem.node_path)),
    ("detail", @wire.text(problem.detail)),
  ])
}

///|
/// A generation refusal must not discard the successfully compiled model.
fn elm_output(file : @ir.IRFile) -> Json {
  try {
    let output = @elm.generate("workbench", file, @elm.Options::default())
    @wire.obj([
      (
        "artifacts",
        Json::array(
          output.files.map(file => {
            @wire.obj([
              ("path", @wire.text(file.path)),
              ("content", @wire.text(file.content)),
              ("binary", Json::boolean(false)),
            ])
          }),
        ),
      ),
      (
        "generated",
        @wire.text(
          output.files
          .filter(f => f.role == @elm.Source)
          .get(0)
          .map(f => f.content)
          .unwrap_or(""),
        ),
      ),
      ("generationWarnings", Json::array(output.warnings.map(@wire.text))),
    ])
  } catch {
    @elm.Refused(problem) => elm_refusal([problem])
    @elm.Failed(problems) => elm_refusal(problems)
  }
}

///|
fn elm_refusal(problems : Array[@elm.Problem]) -> Json {
  @wire.obj([
    ("artifacts", Json::array([])),
    ("generationDiagnostics", Json::array(problems.map(elm_problem))),
    (
      "generationMessage",
      @wire.text(
        "Elm generation failed: " +
        problems
        .map(p => p.code + " at " + p.node_path + ": " + p.detail)
        .join("; "),
      ),
    ),
  ])
}

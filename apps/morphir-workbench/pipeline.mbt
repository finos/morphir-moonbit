///|
/// Local adapter envelopes are private to the worker, not Morphir RPC methods.
/// Decode/migrate imports explicitly; the inspector uses the current semantic model.
pub fn execute(request : Json) -> Json {
  try {
    let operation = @wire.string(@wire.field(request, "operation"))
    let source = @wire.string(@wire.field(request, "source"))
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
    let generate = match @wire.optional(request, "target") {
      None => true
      Some(String(target)) => target == "scheme"
      _ => false
    }
    if operation != "inspect" && generate {
      result.push(("generated", @wire.text(@backend.emit_file(file))))
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

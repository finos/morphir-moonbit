///|
priv struct CompiledSource {
  unit : @data.IRUnit
  profile : String
  provider : String
}

///|
fn source_constraint(request : Json, key : String) -> String? raise {
  match @wire.optional(request, key) {
    None => None
    Some(String(value)) => Some(value)
    _ => raise @scheme.Invalid("frontend.invalid_selection: " + key)
  }
}

///|
/// In-process selection uses the registered provider's defaults and callbacks.
fn compile_source(request : Json, source : String) -> CompiledSource raise {
  let provider = @moonbit_adapter.provider()
  if source_constraint(request, "frontendProvider") is Some(wanted) &&
    wanted != provider.id.to_string() {
    raise @scheme.Invalid("frontend.unknown_provider: " + wanted)
  }
  let language = provider.languages[0]
  let wanted = source_constraint(request, "frontendProfile").unwrap_or(
    language.default_profile.to_string(),
  )
  let offered = language.profiles.filter(profile => {
    profile.id.to_string() == wanted
  })
  if offered.is_empty() {
    raise @scheme.Invalid("frontend.unknown_profile: " + wanted)
  }
  let profile = offered[0]
  let run = match profile.compile {
    @engine.PerFile(run) => run
    @engine.PerProject(_) =>
      raise @scheme.Invalid(
        "frontend.unsupported_profile: " + profile.id.to_string(),
      )
  }
  let unit = run(
    {
      path: "main.mbt",
      relative_path: "main.mbt",
      content: source,
      package_name: "user",
      module_name: "main",
    },
    "main",
    fn() { false },
  )
  unit.validate(limits=profile.unit_limits)
  { unit, profile: profile.id.to_string(), provider: provider.id.to_string(), }
}

///|
pub const PROVIDER : String = "finos/morphir-moonbit-frontend"

///|
fn input(source : @engine.Source, unit_id : String) -> @frontend.Input {
  {
    unit_id,
    package_name: source.package_name,
    module_name: source.module_name,
    source: source.content,
  }
}

///|
/// Descriptors and callbacks for in-process clients and engine registration.
/// The original single-function profile remains the default.
pub fn provider(
  limits~ : @frontend.Limits = @frontend.Limits::default(),
  library_limits~ : @frontend.LibraryLimits = @frontend.LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  unit_limits~ : @data.Limits = @data.Limits::default(),
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> @engine.SourceProvider raise {
  try {
    limits.validate()
    library_limits.validate()
  } catch {
    @frontend.Invalid(diagnostic) =>
      raise @engine.Rejected(
        diagnostic.code,
        diagnostic.detail,
        diagnostic.source,
      )
  }
  if max_string_code_units < 0 || max_string_code_units > 1048576 {
    raise @engine.Rejected(
      "moonbit_frontend.invalid_limits",
      "String code-unit limit must be between 0 and 1048576",
      None,
    )
  }
  let dependencies = Map::from_array([
    ("moonbitlang/parser", @frontend.PARSER_VERSION),
    ("moonbitlang/lexer", "0.4.3"),
  ])
  let seed : @engine.SourceProfile = {
    id: @ids.ProfileId::parse(@frontend.PROFILE),
    dependencies,
    evidence: @engine.LocalAcceptance,
    unit_limits,
    capabilities: {
      summary: "Single Boolean function",
      max_documents: Some(1),
      incremental: false,
      supported: [
        "One function with explicit Bool signature", "Boolean literals and parameters",
        "Negation, Boolean operators and conditionals",
      ],
      excluded: [
        "Function calls", "Local bindings", "Cross-file imports", "Other source types",
      ],
      limits: {
        "bytes": limits.max_bytes,
        "functions": 1,
        "parameters": limits.max_parameters,
        "expressions": limits.max_expressions,
        "expressionDepth": limits.max_depth,
      },
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile(
        input(source, unit_id),
        limits~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let library_dependencies = dependencies.copy()
  for
    package_name in [
      "finos/morphir-sdk", "finos/morphir-sdk/basics", "finos/morphir-sdk/int", "finos/morphir-sdk/integer",
    ] {
    library_dependencies[package_name] = "0.1.0+tree:9c83a100383570236b3d781362524008f76dd56d"
  }
  library_dependencies["finos/morphir-sdk/decimal"] = "0.1.0+tree:" +
    @frontend.DECIMAL_SDK_TREE
  let bindings = @frontend.PinnedSourceBindings::sdk_decimal(
    "finos/morphir-sdk/decimal",
    "0.1.0",
    @frontend.DECIMAL_SDK_TREE,
    "decimal",
  ) catch {
    @frontend.Invalid(d) => raise @engine.Rejected(d.code, d.detail, d.source)
  }
  let library : @engine.SourceProfile = {
    id: @ids.ProfileId::parse(@frontend.LIBRARY_PROFILE),
    dependencies: library_dependencies,
    evidence: @engine.LocalAcceptance,
    unit_limits,
    capabilities: {
      summary: "Typed MoonBit library",
      max_documents: Some(1),
      incremental: false,
      supported: [
        "Public and unexported functions with explicit concrete signatures", "Immutable bindings, lexical shadowing, conditionals and direct same-file calls",
        "Bool, fixed-width signed and unsigned integers, BigInt, Float and Double",
        "Numeric literals, qualified arithmetic, comparisons and IEEE operation rounding",
        "Bounded well-formed UTF-16 Strings, concatenation, equality and shortlex ordering",
        "String.length() and owned slices with qualified UTF-16 index semantics",
        "Pinned @basics Boolean and binary64 math calls", "SDK Integer boundaries, classic rounding and explicit optional conversions",
        "Checked Decimal construction, arithmetic, comparisons, half-even rounding and division",
        "Declared SDK error propagation without general source effects",
      ],
      excluded: [
        "Recursion, cross-file imports, mutation and indirect calls", "Integer division, source numeric casts and Float32 SDK carrier conversions",
        "General source effects, error handlers, Maybe patterns and constructors",
        "Unowned String slices, single-index access, interpolation and multiline strings",
        "Unlisted SDK calls and full MoonBit language conformance",
      ],
      limits: {
        "bytes": library_limits.max_bytes,
        "functions": library_limits.max_functions,
        "parameters": library_limits.max_parameters,
        "lets": library_limits.max_lets,
        "expressions": library_limits.max_expressions,
        "calls": library_limits.max_calls,
        "expressionDepth": library_limits.max_depth,
        "callGraphDepth": library_limits.max_call_depth,
        "stringCodeUnits": max_string_code_units,
      },
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_library(
        input(source, unit_id),
        bindings=Some(bindings),
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(d) =>
          raise @engine.Rejected(d.code, d.detail, d.source)
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  {
    id: @ids.ProviderId::parse(PROVIDER),
    languages: [
      {
        id: @ids.LanguageId::parse("moonbit"),
        extensions: [@ids.FileExtension::parse(".mbt")],
        default_profile: @ids.ProfileId::parse(@frontend.PROFILE),
        profiles: [seed, library],
      },
    ],
  }
}

///|
/// Register the same descriptors exposed to in-process clients.
pub fn register(
  engine : @engine.Engine,
  limits~ : @frontend.Limits = @frontend.Limits::default(),
  library_limits~ : @frontend.LibraryLimits = @frontend.LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  unit_limits~ : @data.Limits = @data.Limits::default(),
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> Unit raise {
  engine.register_source_provider(
    provider(
      limits~,
      library_limits~,
      max_string_code_units~,
      unit_limits~,
      observer~,
    ),
  )
}

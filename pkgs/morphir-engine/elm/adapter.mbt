///|
pub const PROVIDER : String = "finos/morphir-elm"

///|
pub const PROFILE : String = "library"

///|
/// Parses a constant that cannot fail, because `provider()` does not raise.
fn[T, E : Error] constant(parse : (String) -> T raise E, text : String) -> T {
  parse(text) catch {
    _ => abort("invalid constant: " + text)
  }
}

///|
/// The unit limits of the Elm provider. One unit holds a whole project, so the byte budget is larger than the
/// default of `@data.Limits`. The depth and value budgets are the identity limits of `@identities.nodes` (depth
/// 128, 100000 nodes): `IRUnit::validate` applies them whatever the unit limits are, so a larger budget here would
/// not be reachable (`morphir-ukvn.5.22.3.24`). The checkpoint backend encodes with the limits of its codec registry.
pub fn default_unit_limits() -> @data.Limits {
  { max_bytes: 16 * 1024 * 1024, max_depth: 128, max_values: 100000, }
}

///|
/// The Elm provider: language `elm`, extension `.elm`, profile `library`. The profile compiles every Elm module of
/// a project to one unit with `@frontend.compile_project`, keeping every module that the output names
/// (`Referenced`), so that generated code builds. The project name is the dotted package name and
/// `exposed_modules` holds the exposed modules relative to the package, as in `morphir.json`.
/// With `origins`, each unit carries one metadata entry per value declaration (the Elm name, file and range, and
/// the lifted parameters) and a provenance record, which the Scheme backend turns into source comments and
/// keeps in its sidecar. It is off by default because a Morphir JSON checkpoint, the default output of a
/// `morphir.json` project, cannot carry unit metadata and would be refused.
pub fn provider(
  unit_limits~ : @data.Limits = default_unit_limits(),
  origins~ : Bool = false,
) -> @engine.SourceProvider {
  let library : @engine.SourceProfile = {
    id: constant(@ids.ProfileId::parse, PROFILE),
    dependencies: { "moonrockz/krueger": KRUEGER_VERSION },
    evidence: @engine.LocalAcceptance,
    unit_limits,
    capabilities: {
      summary: "Elm 0.19.1 project",
      max_documents: None,
      incremental: false,
      supported: [
        "Elm 0.19.1 modules of one package", "elm/core modules that the Morphir SDK covers",
        "Morphir.SDK modules", "Type inference of every value and pattern",
      ],
      excluded: [
        "Ports, effect modules and GLSL", "Debug and infix declarations", "Third-party Elm packages",
        "morphir.json dependencies",
      ],
      limits: {
        "unitBytes": unit_limits.max_bytes,
        "unitDepth": unit_limits.max_depth,
        "unitValues": unit_limits.max_values,
      },
    },
    compile: @engine.PerProject(fn(project, unit_id, cancelled) raise {
      if cancelled() {
        raise @engine.Rejected("elm.cancelled", "Cancelled", None)
      }
      let sources = project.sources.map(s => {
        ({ path: s.relative_path, content: s.content, } : @frontend.ElmSource)
      })
      let output = @frontend.compile_project_output(
        sources,
        project.package_name.to_string(),
        project.exposed_modules.map(m => m.to_string()),
        output=Referenced,
      ) catch {
        @frontend.ElmFailed(problems) =>
          raise @engine.RejectedSources(
            problems.map(p => {
              (
                {
                  code: p.code,
                  detail: p.message,
                  path: p.path,
                  location: p.location,
                } : @engine.SourceProblem)
            }),
          )
      }
      if !origins {
        return @data.IRUnit::new(unit_id, output.ir)
      }
      guard output.ir.distribution is Library(package_name, _, _) else {
        raise @engine.Rejected(
          "elm.internal",
          "the Elm frontend returns a library",
          None,
        )
      }
      @data.IRUnit::{
        id: unit_id,
        distribution: output.ir,
        metadata: output.origins.map(o => origin_metadata(package_name, o)),
        annotations: [@ion.SymbolToken::new("morphir_pipeline")],
        provenance: [provenance(unit_id)],
      }
    }),
  }
  {
    id: constant(@ids.ProviderId::parse, PROVIDER),
    languages: [
      {
        id: constant(@ids.LanguageId::parse, "elm"),
        extensions: [constant(@ids.FileExtension::parse, ".elm")],
        default_profile: constant(@ids.ProfileId::parse, PROFILE),
        profiles: [library],
      },
    ],
  }
}

///|
/// Registers the Elm provider. The engine core does not register it by default.
pub fn register(
  engine : @engine.Engine,
  unit_limits~ : @data.Limits = default_unit_limits(),
  origins~ : Bool = false,
) -> Unit raise {
  engine.register_source_provider(provider(unit_limits~, origins~))
}

///|
const KRUEGER_VERSION : String = "0.8.0"

///|
fn record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::new(
    @ion.Struct(fields.map(pair => @ion.Field::new(pair.0, pair.1))),
  )
}

///|
/// A source position hint: the Elm spelling, the file (relative to the source directory) and the elm-syntax range
/// (rows and columns from 1, the end just after the last character).
fn position(
  path : String,
  name : String,
  span : @ir.SourceLocation,
) -> @ion.IonValue {
  record([
    ("name", @ion.IonValue::string(name)),
    ("path", @ion.IonValue::string(path)),
    ("coordinate_profile", @ion.IonValue::string("elm-syntax-position-v1")),
    ("start_line", @ion.IonValue::int(span.start_line)),
    ("start_column", @ion.IonValue::int(span.start_column)),
    ("end_line", @ion.IonValue::int(span.end_line)),
    ("end_column", @ion.IonValue::int(span.end_column)),
  ])
}

///|
/// The metadata entry `value:<fqname>` of a declaration: its `declaration` hint and its `parameters`.
fn origin_metadata(
  package_name : @ir.Path,
  origin : @frontend.DeclarationOrigin,
) -> @data.NodeMetadata {
  let fqname : @ir.FQName = {
    package_name,
    module_name: origin.module_name,
    local_name: origin.name,
  }
  {
    node_id: "value:" + fqname.to_canonical(),
    data: record([
      ("declaration", position(origin.path, origin.source_name, origin.span)),
      (
        "parameters",
        @ion.IonValue::list(
          origin.parameters.map(p => position(origin.path, p.0, p.1)),
        ),
      ),
    ]),
  }
}

///|
fn provenance(unit_id : String) -> @ion.IonValue {
  record([
    ("language", @ion.IonValue::string("elm")),
    ("profile", @ion.IonValue::string(PROFILE)),
    ("parser", @ion.IonValue::string("moonrockz/krueger")),
    ("parser_version", @ion.IonValue::string(KRUEGER_VERSION)),
    ("unit_id", @ion.IonValue::string(unit_id)),
  ]).with_annotation(@ion.SymbolToken::new("morphir_elm_frontend"))
}

///|
fn failed(code : String, message : String) -> @mep.Compilation {
  @mep.CompilationFailed([
    { "severity": "error", "code": code, "message": message },
  ])
}

///|
fn diagnostic(
  code : String,
  message : String,
  uri : String,
  source : @ir.SourceLocation?,
) -> Json {
  let value : Json = { "severity": "error", "code": code, "message": message }
  if source is Some(location) && value is Object(fields) {
    fields["location"] = {
      "uri": uri,
      "range": {
        "start": {
          "line": location.start_line - 1,
          "character": location.start_column,
        },
        "end": {
          "line": location.end_line - 1,
          "character": location.end_column,
        },
      },
    }
  }
  value
}

///|
fn module_name(input : @mep.CompileInput) -> String raise {
  for identity in [input.uri, ..input.root.iter().to_array()] {
    guard !identity.contains("\\") &&
      !identity.contains("%") &&
      !identity.contains("?") &&
      !identity.contains("#") &&
      !identity.split("/").any(p => p == "." || p == "..") else {
      fail("Ambiguous source identity")
    }
  }
  let absolute = input.uri.has_prefix("/") || input.uri.contains(":")
  let relative = match (absolute, input.root) {
    (true, Some(root)) => {
      let prefix = if root.has_suffix("/") { root } else { root + "/" }
      guard input.uri.has_prefix(prefix) else {
        fail("Document URI must be beneath the declared source root")
      }
      input.uri[prefix.length():].to_owned()
    }
    (true, None) =>
      fail("An absolute document URI requires an explicit source root")
    (false, _) => input.uri
  }
  guard relative.has_suffix(".mbt") &&
    !relative.contains(":") &&
    !relative.contains("\\") &&
    !relative.contains("%") &&
    !relative.contains("?") &&
    !relative.contains("#") else {
    fail("Use a relative .mbt path or a URI beneath an explicit source root")
  }
  let name = relative[:relative.length() - 4].to_owned()
  guard !name.is_empty() &&
    name.split("/").all(p => p != "" && p != "." && p != "..") else {
    fail(
      "Source module path must contain nonempty logical segments without traversal",
    )
  }
  name
}

///|
fn compile(
  input : @mep.CompileInput,
  cancelled : () -> Bool,
) -> @mep.Compilation raise {
  @wire.fields(input.options, ["typesOnly", "irVersion", "profile"]) catch {
    _ =>
      return failed(
        "moonbit_frontend.unsupported_options", "Supported options are typesOnly=false, irVersion=4.0.0 and the Boolean library profile",
      )
  }
  guard @wire.optional(input.options, "typesOnly") == Some(Json::boolean(false)) else {
    return failed(
      "moonbit_frontend.unsupported_options", "typesOnly must be false",
    )
  }
  let profile = @wire.optional(input.options, "profile").unwrap_or(
    Json::string(@source_frontend.LIBRARY_PROFILE),
  )
  guard profile == Json::string(@source_frontend.LIBRARY_PROFILE) else {
    return failed(
      "moonbit_frontend.unsupported_profile",
      "Select " + @source_frontend.LIBRARY_PROFILE,
    )
  }
  let module_name = module_name(input) catch {
    _ =>
      return failed(
        "moonbit_frontend.invalid_source_identity", "Document URI must identify a .mbt module beneath its source root, without traversal or encoded path segments",
      )
  }
  // The qualified frontend exposes its one module. Other visibility modes
  // require a distinct lowering path and cannot be silently ignored.
  if input.exposed_modules is Some(exposed) && exposed != [module_name] {
    return failed(
      "moonbit_frontend.unsupported_exposed_modules",
      "Omit exposedModules or select exactly " + module_name,
    )
  }
  let compiled = @source_frontend.compile_library(
    {
      unit_id: input.uri,
      package_name: input.package_name,
      module_name,
      source: input.text,
    },
    cancelled~,
  ) catch {
    @source_frontend.Invalid(problem) =>
      return @mep.CompilationFailed([
        diagnostic(problem.code, problem.detail, input.uri, problem.source),
      ])
    _ => return failed("moonbit_frontend.failed", "Source compilation failed")
  }
  @mep.Compiled(
    {
      unit_id: compiled.unit_id,
      ir: compiled.ir,
      metadata: compiled.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: compiled.annotations,
      provenance: compiled.provenance,
    },
    [module_name],
    compiled.warnings.map(w => {
      "severity": "warning",
      "code": w.code,
      "message": w.message + " Fix: " + w.fix,
    }),
  )
}

///|
/// Application composition; only this layer knows both pure components.
pub fn provider() -> @mep.Frontend {
  {
    language_id: "moonbit",
    file_extensions: [".mbt"],
    profiles: [
      {
        "id": @source_frontend.LIBRARY_PROFILE,
        "summary": "Boolean library",
        "maxDocuments": 1,
        "imports": false,
        "dependencies": false,
      },
    ],
    compile,
  }
}

///|
/// Paths are relative to a host-owned root. list recursively returns file paths.
pub(all) struct Host {
  read : (String) -> String raise
  exists : (String) -> Bool raise
  list : (String) -> Array[String] raise
}

///|
/// An immutable snapshot is useful for editors, tests, WASM and remote hosts.
pub fn Host::memory(files : Map[String, String]) -> Host raise {
  let snapshot : Map[String, String] = Map([])
  for path, content in files {
    let normalized = normalize(path)
    if snapshot.contains(normalized) {
      raise @scheme.Invalid("Duplicate host path: " + normalized)
    }
    snapshot[normalized] = content
  }
  {
    read: fn(path) raise {
      match snapshot.get(path) {
        Some(content) => content
        None => raise @scheme.Invalid("File not found: " + path)
      }
    },
    exists: fn(path) { snapshot.contains(path) },
    list: fn(root) {
      snapshot.keys().filter(path => within(root, path)).collect()
    },
  }
}

///|
pub(all) enum Input {
  File(String)
  Directory(String)
  Project(String)
  Workspace(String)
}

///|
pub(all) struct Source {
  path : String
  relative_path : String
  content : String
  package_name : String
  module_name : String
}

///|
/// One backend output per input. Hosts decide when and where to persist artifacts.
pub(all) struct Artifact {
  path : String
  source : String
  content : String
}

///|
pub(all) struct Diagnostic {
  path : String
  stage : String
  message : String
}

///|
pub(all) struct Report {
  artifacts : Array[Artifact]
  diagnostics : Array[Diagnostic]
  processed : Int
}

///|
pub fn Report::successful(self : Report) -> Bool {
  self.diagnostics.is_empty()
}

///|
struct Frontend {
  extensions : Array[String]
  compile : (Source) -> @ir.IRFile raise
}

///|
struct Backend {
  extension : String
  emit : (@ir.IRFile) -> String raise
}

///|
/// Registries are explicit; every run creates isolated script sessions.
pub struct Engine {
  priv frontends : Map[String, Frontend]
  priv backends : Map[String, Backend]
  priv limits : @scheme.Limits
}

///|
pub fn Engine::new(
  limits? : @scheme.Limits = @scheme.Limits::default(),
) -> Engine {
  let engine = { frontends: Map([]), backends: Map([]), limits, }
  engine.register_frontend("scheme", [".scm", ".ss"], fn(source) raise {
    @frontend.compile_file(
      source.content,
      package_name=source.package_name,
      module_name=source.module_name,
    )
  })
  engine.register_frontend("ir-json", [".json"], fn(source) raise {
    @migration.to_current(@versioned_json.read(source.content))
  })
  engine.register_backend("scheme", ".scm", @backend.emit_file)
  engine.register_backend("ir-json", ".ir.json", @ir_json.write)
  engine
}

///|
pub fn Engine::register_frontend(
  self : Engine,
  name : String,
  extensions : Array[String],
  compile : (Source) -> @ir.IRFile raise,
) -> Unit {
  self.frontends[name] = { extensions: extensions.copy(), compile, }
}

///|
pub fn Engine::register_backend(
  self : Engine,
  name : String,
  extension : String,
  emit : (@ir.IRFile) -> String raise,
) -> Unit {
  self.backends[name] = { extension, emit, }
}

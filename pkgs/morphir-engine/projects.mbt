///|
pub(all) struct ProjectInfo {
  name : String
  relative_path : String
  frontend : String?
  target : String?
  error : String?
}

///|
pub fn ProjectInfo::to_json(self : ProjectInfo) -> Json {
  fn optional(value : String?) -> Json {
    match value {
      Some(value) => Json::string(value)
      None => Json::null()
    }
  }
  Json::object(
    Map::from_array([
      ("name", Json::string(self.name)),
      ("relativePath", Json::string(self.relative_path)),
      ("frontend", optional(self.frontend)),
      ("target", optional(self.target)),
      ("error", optional(self.error)),
    ]),
  )
}

///|
fn Engine::resolve_project_config(
  self : Engine,
  host : Host,
  workspace : @workspace.Workspace,
  project : @workspace.Project,
  script : String,
  overlay : @configuration.Document,
  cancelled : () -> Bool,
  bind_runtime : (@scheme.Runtime) -> Unit raise,
) -> (Config, @scheme.Runtime) raise {
  if project.error is Some(message) {
    raise @configuration.Invalid(message)
  }
  project.document.validate()
  let runtime = config_runtime(self.limits)
  bind_runtime(runtime)
  runtime.set_cancelled(cancelled)
  let settings = Config::{
    frontend: "scheme",
    backend: "ir-json",
    output: "",
    package_name: project.name,
    source: if project.anchor == "" {
      ""
    } else {
      "src"
    },
    transforms: [],
  }
  settings.overlay(project.document)
  if project.anchor == "" &&
    project.document.provenance.get("project.source_directory") ==
    Some("defaults") {
    settings.source = ""
  }
  let root_script = join(workspace.root, "morphir.config.scm")
  let project_script = join(project.root, "morphir.config.scm")
  for
    path in (if root_script == project_script {
      [root_script]
    } else {
      [root_script, project_script]
    }) {
    if (host.exists)(path) {
      settings.apply(runtime, (host.read)(path))
    }
  }
  if script != "" {
    settings.apply(runtime, script)
  }
  settings.overlay(overlay)
  (settings, runtime)
}

///|
/// Resolve language choices through the host without compiling or reading sources.
/// Unknown frontend/backend names remain visible for external tooling.
pub fn Engine::list_projects(
  self : Engine,
  host : Host,
  workspace : @workspace.Workspace,
  script? : String = "",
  cancelled? : () -> Bool = fn() { false },
  bind_runtime? : (@scheme.Runtime) -> Unit raise = fn(_) { () },
) -> Array[ProjectInfo] {
  workspace.projects.map(project => {
    let path = if project.root == "" { "." } else { project.root }
    try {
      let (settings, _) = self.resolve_project_config(
        host,
        workspace,
        project,
        script,
        @configuration.empty(),
        cancelled,
        bind_runtime,
      )
      {
        name: project.name,
        relative_path: path,
        frontend: Some(settings.frontend),
        target: Some(settings.backend),
        error: None,
      }
    } catch {
      error =>
        {
          name: project.name,
          relative_path: path,
          frontend: None,
          target: None,
          error: Some(error.to_string()),
        }
    }
  })
}

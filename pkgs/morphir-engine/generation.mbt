///|
pub(all) enum BuildPolicy {
  SourceOnly
  Required(String)
} derive(Eq, Debug)

///|
pub(all) struct ProjectDependency {
  module_name : String
  version : String
  api_profile : String
  semantic_pin : String
}

///|
pub(all) struct GeneratedFile {
  path : String
  content : @data.Content
  format : String
}

///|
pub(all) struct GeneratedProject {
  id : String
  root : String
  members : Array[String]
  dependencies : Array[ProjectDependency]
  build_contract : String
}

///|
pub(all) struct GenerationBatch {
  files : Array[GeneratedFile]
  projects : Array[GeneratedProject]
}

///|
pub(all) struct GenerationBackend {
  generate : (@data.IRUnit, () -> Bool) -> GenerationBatch raise
  write_bytes : Bool
}

///|
pub(all) struct LibraryProject {
  id : String
  source : String
  root : String
  members : Array[String]
  dependencies : Array[ProjectDependency]
  build_contract : String
  policy : BuildPolicy
}

///|
pub fn Engine::register_generation_backend(
  self : Engine,
  name : String,
  backend : GenerationBackend,
) -> Unit raise {
  if name == "" ||
    name == "checkpoint" ||
    self.backends.contains(name) ||
    self.generators.contains(name) {
    raise @configuration.Invalid("generation.backend_conflict: " + name)
  }
  self.generators[name] = backend
}

///|
fn moonbit_generation(
  unit : @data.IRUnit,
  cancelled : () -> Bool,
) -> GenerationBatch raise {
  let result = @moonbit.generate(
    {
      unit_id: unit.id,
      ir: unit.distribution,
      metadata: unit.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: unit.annotations,
      provenance: unit.provenance,
    },
    cancelled~,
  )
  {
    files: result.artifacts.map(a => {
      path: a.path,
      content: match a.content {
        Text(t) => @data.Text(t)
        Binary(b) => @data.Binary(b)
      },
      format: match a.role {
        Source => "moonbit-source"
        ModuleManifest | PackageManifest => "moonbit-manifest"
        Metadata => "ion-binary"
      },
    }),
    projects: [
      {
        id: result.project.module_name,
        root: result.project.root,
        members: result.project.members,
        dependencies: result.project.dependencies.map(d => {
          module_name: d.module_name,
          version: d.version,
          api_profile: d.api_profile,
          semantic_pin: d.semantic_pin,
        }),
        build_contract: "moonbit-library-v1",
      },
    ],
  }
}

///|
fn portable_path(path : String, allow_empty? : Bool = false) -> Unit raise {
  if (path == "" && !allow_empty) ||
    normalize(path) != path ||
    path.contains(":") ||
    path.contains("\\") ||
    path.contains("\u0000") {
    raise @configuration.Invalid("generation.invalid_path: " + path)
  }
  for part in path.split("/") {
    if part.has_suffix(".") ||
      part.has_suffix(" ") ||
      part.to_owned().to_array().any(c => c.to_int() < 32 || c.to_int() > 126) {
      raise @configuration.Invalid("generation.nonportable_path: " + path)
    }
  }
}

///|
fn validate_batch(
  batch : GenerationBatch,
  base : String,
  source : String,
  policy : BuildPolicy,
  artifacts : Array[ContentArtifact],
  projects : Array[LibraryProject],
) -> Unit raise {
  let seen = Map([])
  for file in batch.files {
    portable_path(file.path)
    let key = file.path.to_lower()
    if seen.contains(key) ||
      seen
      .keys()
      .any(existing => {
        @workspace.within(existing, key) || @workspace.within(key, existing)
      }) {
      raise @configuration.Invalid("generation.path_collision: " + file.path)
    }
    seen[key] = true
  }
  let roots = []
  let members = Map([])
  let ids = Map([])
  for project in batch.projects {
    portable_path(project.root, allow_empty=true)
    if project.id == "" ||
      ids.contains(project.id) ||
      project.build_contract == "" {
      raise @configuration.Invalid("generation.invalid_project: " + project.id)
    }
    ids[project.id] = true
    let key = project.root.to_lower()
    if roots.any(r => @workspace.within(r, key) || @workspace.within(key, r)) {
      raise @configuration.Invalid(
        "generation.project_overlap: " + project.root,
      )
    }
    roots.push(key)
    if project.members.is_empty() {
      raise @configuration.Invalid("generation.empty_project: " + project.id)
    }
    for member in project.members {
      portable_path(member)
      let path = join(project.root, member)
      if !batch.files.any(f => f.path == path) || members.contains(path) {
        raise @configuration.Invalid("generation.invalid_membership: " + path)
      }
      members[path] = true
    }
  }
  if members.length() != batch.files.length() || batch.projects.is_empty() {
    raise @configuration.Invalid("generation.unclaimed_artifact")
  }
  for file in batch.files {
    artifacts.push({
      path: join(base, file.path),
      source,
      content: file.content,
      format: file.format,
    })
  }
  for project in batch.projects {
    projects.push({
      id: project.id,
      source,
      root: join(base, project.root),
      members: project.members.map(m => join(join(base, project.root), m)),
      dependencies: project.dependencies.copy(),
      build_contract: project.build_contract,
      policy,
    })
  }
}

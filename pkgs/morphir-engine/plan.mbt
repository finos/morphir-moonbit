///|
pub(all) struct Request {
  selector : String
  all : Bool
  invocation : String
  file : String?
  directory : String?
  script : String
  overlay : @configuration.Document
}

///|
pub fn Request::new() -> Request {
  {
    selector: "",
    all: false,
    invocation: "",
    file: None,
    directory: None,
    script: "",
    overlay: @configuration.empty(),
  }
}

///|
priv struct Job {
  root : String
  source_root : String
  destination : String
  paths : Array[String]
  settings : Config
  module_prefix : String
  exposed : Array[String]?
  runtime : @scheme.Runtime
  frontend : Frontend
  backend : Backend
}

///|
pub struct Plan {
  priv jobs : Array[Job]
  priv mut consumed : Bool
  priv sources : Array[String]
  priv destinations : Array[String]
  output_root : String
}

///|
fn Config::overlay(
  self : Config,
  values : @configuration.Document,
) -> Unit raise {
  self.frontend = values.text("frontend.language", self.frontend)
  self.backend = values.text("pipeline.backend", self.backend)
  self.source = normalize(values.text("project.source_directory", self.source))
  self.package_name = values.text("project.name", self.package_name)
}

///|
pub fn Engine::plan(
  self : Engine,
  host : Host,
  workspace : @workspace.Workspace,
  request : Request,
  cancelled? : () -> Bool = fn() { false },
) -> Plan raise {
  let jobs = []
  let sources = []
  let destinations = []
  let out_dir = normalize(
    workspace.document.text("workspace.out_dir", ".morphir/out"),
  )
  if out_dir == "" {
    raise @configuration.Invalid("workspace.out_dir must be nonempty")
  }
  let output_root = join(workspace.root, out_dir)
  let selection = workspace.select(
    selector=request.selector,
    all=request.all,
    invocation=request.invocation,
  )
  for selected in selection {
    if selected.error is Some(message) {
      raise @configuration.Invalid(message)
    }
    let effective = selected.document
    effective.validate()
    if effective.boolean("ir.strict_mode", false) &&
      !workspace.warnings.is_empty() {
      raise @configuration.Invalid(
        "Strict configuration rejects warnings: " +
        workspace.warnings.join("; "),
      )
    }
    if effective.get("ir.mode") is Some(_) &&
      effective.provenance.get("ir.layout") == Some("defaults") {
      if effective.text("ir.mode", "classic") != "classic" {
        raise @configuration.Invalid(
          "Only ir.mode = classic is supported; prefer ir.layout = single-file",
        )
      }
    }
    if effective.text("ir.layout", "single-file") != "single-file" ||
      effective.text("ir.format", "json") != "json" {
      raise @configuration.Invalid(
        "Only single-file JSON IR output is currently supported",
      )
    }
    let version = match effective.get("ir.format_version") {
      Some(@toml.TomlInteger(n)) if n >= 1 && n <= 4 =>
        @version.FormatVersion::baseline(n.to_int().reinterpret_as_uint())
      None => @version.FormatVersion::baseline(4U)
      _ =>
        raise @configuration.Invalid(
          "Supported IR format versions are integers 1 through 4",
        )
    }
    let module_prefix = effective.text("project.module_prefix", "")
    let exposed = match effective.get("project.exposed_modules") {
      Some(_) =>
        Some(effective.strings("project.exposed_modules").map(canonical_path))
      None => None
    }
    let runtime = config_runtime(self.limits)
    runtime.set_cancelled(cancelled)
    let settings = Config::{
      frontend: "scheme",
      backend: "ir-json",
      output: "",
      package_name: selected.name,
      source: if selected.anchor == "" {
        ""
      } else {
        "src"
      },
      transforms: [],
    }
    settings.overlay(effective)
    // Defaults in discovery must not narrow an ad hoc directory to a nonexistent src.
    if selected.anchor == "" &&
      effective.provenance.get("project.source_directory") == Some("defaults") {
      settings.source = ""
    }
    let root_script = join(workspace.root, "morphir.config.scm")
    let project_script = join(selected.root, "morphir.config.scm")
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
    if request.script != "" {
      settings.apply(runtime, request.script)
    }
    settings.overlay(request.overlay)
    let frontend = match self.frontends.get(settings.frontend) {
      Some(f) => f
      None =>
        raise @configuration.Invalid("Unknown frontend: " + settings.frontend)
    }
    let registered_backend = match self.backends.get(settings.backend) {
      Some(b) => b
      None =>
        raise @configuration.Invalid("Unknown backend: " + settings.backend)
    }
    let backend = if settings.backend == "ir-json" {
      Backend::{
        extension: registered_backend.extension,
        emit: fn(ir) raise {
          @versioned_json.write(@migration.migrate(@versioned.V4(ir), version))
        },
      }
    } else {
      registered_backend
    }
    if !backend.extension.has_prefix(".") ||
      backend.extension.contains("/") ||
      backend.extension.contains("\\") {
      raise @configuration.Invalid("Invalid backend file suffix")
    }
    let source_root = match request.directory {
      Some(directory) => normalize(directory)
      None => join(selected.root, settings.source)
    }
    if !@workspace.within(selected.root, source_root) {
      raise @configuration.Invalid(
        "Input directory is outside selected project",
      )
    }
    if @workspace.within(output_root, source_root) {
      raise @configuration.Invalid(
        "Source directory is inside output directory",
      )
    }
    let relative_project = if selected.root == workspace.root {
      ""
    } else if workspace.root == "" {
      selected.root
    } else {
      selected.root[workspace.root.length() + 1:].to_owned()
    }
    let destination = join(join(output_root, relative_project), "compile.dest")
    let output = join(destination, settings.output)
    let paths = match request.file {
      Some(file) => {
        let path = normalize(file)
        if !@workspace.within(source_root, path) || path == source_root {
          raise @configuration.Invalid(
            "File is outside selected source directory: " + path,
          )
        }
        [path]
      }
      None =>
        (host.list)(source_root).filter(fn(path) {
          !@workspace.within(output_root, path) &&
          path != root_script &&
          path != project_script &&
          !["morphir.json", "morphir-workspace.json"].contains(
            path.split("/").last().unwrap_or("").to_owned(),
          ) &&
          frontend.extensions.any(extension => path.has_suffix(extension))
        })
    }
    paths.sort()
    let unique = []
    let seen = Map([])
    for path in paths {
      let path = normalize(path)
      if !@workspace.within(source_root, path) || path == source_root {
        raise @configuration.Invalid(
          "Host listed a path outside source root: " + path,
        )
      }
      let rel = relative(source_root, path)
      let target = join(output, stem(rel) + backend.extension)
      if seen.contains(target) {
        raise @configuration.Invalid("Duplicate output path: " + target)
      }
      seen[target] = true
      unique.push(path)
      sources.push(path)
    }
    if destinations.any(existing => {
        @workspace.within(existing, destination) ||
        @workspace.within(destination, existing)
      }) {
      raise @configuration.Invalid(
        "Task output destinations overlap: " + destination,
      )
    }
    destinations.push(destination)
    jobs.push({
      root: selected.root,
      source_root,
      destination: output,
      paths: unique,
      settings,
      module_prefix,
      exposed,
      runtime,
      frontend,
      backend,
    })
  }
  { jobs, consumed: false, sources, destinations, output_root, }
}

///|
pub fn Engine::execute(
  _self : Engine,
  plan : Plan,
  host : Host,
  cancelled? : () -> Bool = fn() { false },
) -> Report {
  let artifacts = []
  let diagnostics = []
  if plan.consumed {
    return {
      artifacts,
      processed: 0,
      diagnostics: [
        {
          path: "",
          stage: "plan",
          message: "Execution plans are single-use; prepare a fresh plan",
        },
      ],
    }
  }
  plan.consumed = true
  for job in plan.jobs {
    job.runtime.set_cancelled(cancelled)
    for path in job.paths {
      let mut stage = "read"
      try {
        if cancelled() {
          raise @configuration.Invalid("Cancelled")
        }
        let relative_path = relative(job.source_root, path)
        let source = Source::{
          path,
          relative_path,
          content: (host.read)(path),
          package_name: job.settings.package_name,
          module_name: if job.module_prefix == "" {
            stem(relative_path)
          } else {
            job.module_prefix + "/" + stem(relative_path)
          },
        }
        stage = "frontend"
        let mut ir = (job.frontend.compile)(source)
        if job.exposed is Some(exposed) {
          match ir.distribution {
            Library(name, dependencies, package_def) => {
              let modules = package_def.modules.map(fn(module_name, access) {
                {
                  ..access,
                  access: if exposed.contains(module_name.to_canonical()) {
                    @ir.Access::Public
                  } else {
                    @ir.Access::Private
                  },
                }
              })
              ir = @ir.IRFile::new(
                @ir.Distribution::Library(name, dependencies, { modules, }),
              )
            }
            _ =>
              raise @configuration.Invalid(
                "exposed_modules requires a library distribution",
              )
          }
        }
        stage = "transform"
        job.runtime.set_global("source-path", @scheme.Text(path))
        job.runtime.set_global("project-root", @scheme.Text(job.root))
        for transform in job.settings.transforms {
          if cancelled() {
            raise @configuration.Invalid("Cancelled")
          }
          ir = job.runtime.call(transform, [@scheme.IRFile(ir)]).as_file()
        }
        stage = "backend"
        if cancelled() {
          raise @configuration.Invalid("Cancelled")
        }
        let content = (job.backend.emit)(ir)
        artifacts.push({
          path: join(
            job.destination,
            stem(relative_path) + job.backend.extension,
          ),
          source: path,
          content,
        })
      } catch {
        e => diagnostics.push({ path, stage, message: diagnostic_message(e), })
      }
    }
  }
  { processed: artifacts.length(), artifacts, diagnostics, }
}

///|
pub fn Plan::sources(self : Plan) -> Array[String] {
  self.sources.copy()
}

///|
pub fn Plan::destinations(self : Plan) -> Array[String] {
  self.destinations.copy()
}

///|
fn usage(mode : OutputMode) -> Unit {
  if !(mode is Human) {
    let help = Json::object(
      Map::from_array([
        (
          "commands",
          Json::array(
            [
              "run", "workspace", "project list", "toolchain info", "toolchain setup",
              "toolchain build", "toolchain run", "toolchain exec",
            ].map(Json::string),
          ),
        ),
        (
          "options",
          Json::array(
            [
              "--project", "--all", "--frontend", "--backend", "--target", "--output",
              "--config", "--file", "--directory", "--json", "--json-lines", "--dry-run",
              "--checkpoint-format", "--validation", "--build-provider", "--build-helper",
              "--sdk", "--build-node", "--help", "--home", "--yes", "--package",
              "--timeout",
            ].map(Json::string),
          ),
        ),
      ]),
    )
    if mode is JSONLines {
      emit_record("help", help)
    } else {
      println(help.stringify())
    }
    return
  }
  println("Morphir CLI")
  println("Usage: morphir <run|workspace> [path] [options]")
  println(
    "       morphir project list [path] [--frontend <language>] [--target <language>]",
  )
  println("  --project <name-or-path> | --all")
  println("  --frontend <name> --backend <name> --output <directory>")
  println("  --config <scheme-file> --file | --directory --dry-run")
  println(
    "  --backend checkpoint --checkpoint-format <ion-binary|ion-text|morphir-json>",
  )
  println(
    "  --backend moonbit --validation <required|source-only> --target <native|js|wasm|wasm-gc>",
  )
  println("  --json | --json-lines")
  println(
    "       morphir toolchain <info|setup|build|run|exec> [path] [options]",
  )
  println(
    "  --home <toolchain-directory> --yes --target <target> --timeout <milliseconds>",
  )
  println("  run --package <package> -- <program arguments>")
}

///|
fn main {
  let args = @platform.arguments()
  let options = option_args(args)
  let mode = if options.contains("--json-lines") {
    JSONLines
  } else if options.contains("--json") {
    JSON
  } else {
    Human
  }
  let mut status = 0
  try {
    status = command(args, mode)
  } catch {
    error => {
      let message = match error {
        @toolchain.ToolchainError(message) => message
        _ => @host.error_message(error)
      }
      @platform.stderr(message + "\n")
      print_error(message, mode)
      status = if message == "Cancelled" { 130 } else { 2 }
    }
  }
  @platform.exit(status)
}

///|
fn command(raw_args : Array[String], mode : OutputMode) -> Int raise {
  let options = option_args(raw_args)
  if options.contains("--json") && options.contains("--json-lines") {
    raise @config.Invalid("--json and --json-lines cannot be combined")
  }
  let args = options.filter(arg => arg != "--json" && arg != "--json-lines") +
    raw_args[options.length():].to_owned()
  if args.is_empty() || options.contains("--help") || options.contains("-h") {
    usage(mode)
    return 0
  }
  if args[0] == "toolchain" {
    return toolchain_command(args, mode)
  }
  let project_list = args[0] == "project"
  if project_list && (args.length() < 2 || args[1] != "list") {
    raise @config.Invalid("Expected: morphir project list [path] [options]")
  }
  if args[0] != "run" && args[0] != "workspace" && !project_list {
    raise @config.Invalid("Unknown command: " + args[0])
  }
  let mut path = "."
  let mut has_path = false
  let mut selector = ""
  let mut all = false
  let frontends : Array[String] = []
  let targets : Array[String] = []
  let mut dry_run = false
  let mut directory = false
  let mut file = false
  let mut script_path = ""
  let overlay_fields : Map[String, Json] = Map([])
  let mut i = if project_list { 2 } else { 1 }
  while i < args.length() {
    let option = args[i]
    if project_list {
      match option {
        "--frontend" | "--target" | "--config" => {
          i = i + 1
          if i == args.length() || args[i] == "" || args[i].has_prefix("-") {
            raise @config.Invalid("Missing value for " + option)
          }
          match option {
            "--frontend" => frontends.push(args[i])
            "--target" => targets.push(args[i])
            _ => script_path = args[i]
          }
        }
        _ => {
          if option.has_prefix("-") || has_path {
            raise @config.Invalid("Unexpected argument: " + option)
          }
          path = option
          has_path = true
        }
      }
      i = i + 1
      continue
    }
    match option {
      "--all" => all = true
      "--dry-run" => dry_run = true
      "--directory" => directory = true
      "--file" => file = true
      "--project"
      | "--frontend"
      | "--backend"
      | "--output"
      | "--config"
      | "--checkpoint-format"
      | "--validation"
      | "--target"
      | "--build-provider"
      | "--build-helper"
      | "--build-node"
      | "--sdk"
      | "--home"
      | "--timeout" => {
        i = i + 1
        if i == args.length() {
          raise @config.Invalid("Missing value for " + option)
        }
        let value = args[i]
        match option {
          "--project" => selector = value
          "--config" => script_path = value
          _ => {
            let (table, key) = match option {
              "--frontend" => ("frontend", "language")
              "--backend" => ("pipeline", "backend")
              "--checkpoint-format" => ("pipeline", "checkpoint_format")
              "--validation" => ("pipeline", "validation")
              "--target" => ("pipeline", "target")
              "--build-provider" => ("pipeline", "build_provider")
              "--build-helper" => ("pipeline", "build_helper")
              "--build-node" => ("pipeline", "build_node")
              "--sdk" => ("pipeline", "sdk")
              "--home" => ("pipeline", "compiler_home")
              "--timeout" => ("pipeline", "build_timeout")
              _ => ("workspace", "out_dir")
            }
            let fields = match overlay_fields.get(table) {
              Some(Object(fields)) => fields
              _ => Map([])
            }
            fields[key] = Json::string(value)
            overlay_fields[table] = Json::object(fields)
          }
        }
      }
      _ => {
        if option.has_prefix("-") || has_path {
          raise @config.Invalid("Unexpected argument: " + option)
        }
        path = option
        has_path = true
      }
    }
    i = i + 1
  }
  if file && directory {
    raise @config.Invalid("--file and --directory cannot be combined")
  }
  let location = @host.locate(path)
  if file && location.file is None {
    raise @config.Invalid("--file requires a file path")
  }
  if directory && location.file is Some(_) {
    raise @config.Invalid("--directory requires a directory path")
  }
  let mount = @host.Mount::filesystem(location.root)
  let environment = @platform.environment()
  let (system, global) = @host.configuration(environment)
  let host = @host.Host::new(mount, environment~, system~, global~)
  let snapshot = host.snapshot()
  let overlay = @config.from_json(Json::object(overlay_fields), origin="CLI")
  let workspace = @workspace.discover(
    snapshot.tree,
    system~,
    global~,
    environment~,
    overlay~,
  )
  for warning in workspace.warnings {
    @platform.stderr("warning: " + warning + "\n")
  }
  if args[0] == "workspace" {
    if !(mode is Human) {
      emit_workspace(workspace.to_json(), mode)
    } else {
      for project in workspace.projects {
        println(
          project.name +
          "\t" +
          (if project.root == "" { "." } else { project.root }),
        )
      }
    }
    return if workspace.projects.any(p => p.error is Some(_)) { 2 } else { 0 }
  }
  let engine = @engine.Engine::new()
  let script = if script_path == "" { "" } else { @platform.read(script_path) }
  if project_list {
    return print_projects(
      engine.list_projects(snapshot.engine_host(), workspace, script~),
      frontends,
      targets,
      mode,
    )
  }
  let request = @engine.Request::{
    selector,
    all,
    invocation: location.invocation,
    file: location.file,
    directory: if directory ||
      (
        location.file is None &&
        location.invocation != "" &&
        !workspace.projects.any(p => p.root == location.invocation)
      ) {
      Some(location.invocation)
    } else {
      None
    },
    script,
    overlay,
  }
  let plan = engine.plan(snapshot.engine_host(), workspace, request)
  if dry_run {
    emit_plan(plan.sources(), plan.destinations(), plan.boundaries(), mode)
    return 0
  }
  let publisher = @host.ContentPublisher::filesystem(
    location.root,
    plan.output_root,
  )
  let build_config = @config.merge(workspace.document, overlay)
  let provider = match build_config.text("pipeline.build_provider", "") {
    "" => None
    "process" =>
      Some(
        @host.LibraryBuildProvider::process(
          build_config.text("pipeline.build_node", "node"),
          build_config.text("pipeline.build_helper", ""),
          build_config.text("pipeline.compiler_home", ""),
          Map::from_array([
            ("finos/morphir-sdk", build_config.text("pipeline.sdk", "")),
          ]),
          timeout=build_timeout(
            build_config.text("pipeline.build_timeout", "120000"),
          ),
        ),
      )
    other => raise @config.Invalid("build.unsupported_provider: " + other)
  }
  let host = @host.Host::new(
    mount,
    environment~,
    system~,
    global~,
    library_build=provider,
  )
  let boundaries = plan.boundaries()
  let result = host.run_content(
    engine,
    plan,
    publisher,
    read_bytes=if plan.requires_byte_read() {
      Some(@host.Mount::filesystem_bytes(location.root))
    } else {
      None
    },
  ) catch {
    error => {
      let message = @host.error_message(error)
      @platform.stderr(message + "\n")
      print_error(message, mode)
      return if message == "Cancelled" { 130 } else { 1 }
    }
  }
  for diagnostic in result.report.diagnostics {
    @platform.stderr(
      diagnostic.path +
      " [" +
      diagnostic.stage +
      "]: " +
      diagnostic.message +
      "\n",
    )
  }
  if result.publication_error is Some(error) {
    @platform.stderr(error + "\n")
  }
  if !(mode is Human) {
    emit_result(
      Json::object(
        Map::from_array([
          ("boundaries", Json::array(boundaries.map(boundary_json))),
          (
            "artifactDetails",
            Json::array(result.report.artifacts.map(artifact_json)),
          ),
          ("projects", Json::array(result.report.projects.map(project_json))),
          ("validated", Json::array(result.validated.map(validated_json))),
          ("successful", Json::boolean(result.successful())),
          ("processed", Json::number(result.report.processed.to_double())),
          ("committed", Json::array(result.committed.map(Json::string))),
          (
            "diagnostics",
            Json::array(
              result.report.diagnostics.map(d => {
                Json::object(
                  Map::from_array([
                    ("path", Json::string(d.path)),
                    ("stage", Json::string(d.stage)),
                    ("message", Json::string(d.message)),
                  ]),
                )
              }),
            ),
          ),
          (
            "publicationError",
            match result.publication_error {
              Some(s) => Json::string(s)
              None => Json::null()
            },
          ),
          (
            "artifacts",
            Json::array(result.report.artifacts.map(a => Json::string(a.path))),
          ),
        ]),
      ),
      mode,
    )
  } else {
    for boundary in boundaries {
      println(
        boundary.source +
        ": " +
        boundary.input_format +
        " -> " +
        boundary.output_format,
      )
    }
    for artifact in result.report.artifacts {
      println("Accepted " + artifact.path + " (" + artifact.format + ")")
    }
    for validation in result.validated {
      println("Validated " + validation.root + " for " + validation.target)
    }
    for destination in result.committed {
      println("Published " + destination)
    }
    if result.successful() {
      println(
        "Published " + result.report.processed.to_string() + " artifact(s)",
      )
    }
  }
  if result.cancelled {
    130
  } else if result.successful() {
    0
  } else {
    1
  }
}

///|
fn option_args(args : Array[String]) -> Array[String] {
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == "--" {
      return args[:i].to_owned()
    }
  }
  args
}

///|
fn build_timeout(text : String) -> Int raise {
  match @json.parse(text) {
    Number(n, ..) if n >= 1.0 && n <= 600000.0 && n == n.to_int().to_double() =>
      n.to_int()
    _ => raise @config.Invalid("build.invalid_timeout")
  }
}

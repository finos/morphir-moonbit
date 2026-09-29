///|
fn usage() -> Unit {
  println("Morphir CLI")
  println("Usage: morphir <run|workspace> [path] [options]")
  println("  --project <name-or-path> | --all")
  println("  --frontend <name> --backend <name> --output <directory>")
  println("  --config <scheme-file> --file | --directory --json --dry-run")
}

///|
fn main {
  let args = @platform.arguments()
  let mut status = 0
  try {
    status = command(args)
  } catch {
    error => {
      let message = @host.error_message(error)
      @platform.stderr(message + "\n")
      if args.contains("--json") {
        print_error(message)
      }
      status = if message == "Cancelled" { 130 } else { 2 }
    }
  }
  @platform.exit(status)
}

///|
fn command(args : Array[String]) -> Int raise {
  if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
    usage()
    return 0
  }
  if args[0] != "run" && args[0] != "workspace" {
    raise @config.Invalid("Unknown command: " + args[0])
  }
  let mut path = "."
  let mut has_path = false
  let mut selector = ""
  let mut all = false
  let mut json = false
  let mut dry_run = false
  let mut directory = false
  let mut file = false
  let mut script_path = ""
  let overlay_fields : Map[String, Json] = Map([])
  let mut i = 1
  while i < args.length() {
    let option = args[i]
    match option {
      "--all" => all = true
      "--json" => json = true
      "--dry-run" => dry_run = true
      "--directory" => directory = true
      "--file" => file = true
      "--project" | "--frontend" | "--backend" | "--output" | "--config" => {
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
              _ => ("workspace", "out_dir")
            }
            overlay_fields[table] = Json::object(
              Map::from_array([(key, Json::string(value))]),
            )
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
    if json {
      println(workspace.to_json().stringify())
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
    println(
      Json::object(
        Map::from_array([
          ("sources", Json::array(plan.sources().map(Json::string))),
          ("destinations", Json::array(plan.destinations().map(Json::string))),
        ]),
      ).stringify(),
    )
    return 0
  }
  let publisher = @host.Publisher::filesystem(location.root, plan.output_root)
  let host = @host.Host::new(
    mount,
    publisher=Some(publisher),
    environment~,
    system~,
    global~,
  )
  let result = host.run(engine, plan) catch {
    error => {
      let message = @host.error_message(error)
      @platform.stderr(message + "\n")
      if json {
        print_error(message)
      }
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
  if json {
    println(
      Json::object(
        Map::from_array([
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
      ).stringify(),
    )
  } else if result.successful() {
    println("Published " + result.report.processed.to_string() + " artifact(s)")
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
fn print_error(message : String) -> Unit {
  println(
    Json::object(
      Map::from_array([
        ("successful", Json::boolean(false)),
        ("error", Json::string(message)),
        ("committed", Json::array([])),
      ]),
    ).stringify(),
  )
}

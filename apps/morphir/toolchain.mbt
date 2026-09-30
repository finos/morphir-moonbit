///|
fn toolchain_command(args : Array[String], mode : OutputMode) -> Int raise {
  if args.length() < 2 {
    raise @config.Invalid(
      "Expected: morphir toolchain <info|setup|build|run|exec>",
    )
  }
  let operation = args[1]
  if !["info", "setup", "build", "run", "exec"].contains(operation) {
    raise @config.Invalid("Unknown toolchain command: " + operation)
  }
  let fields : Map[String, Json] = Map::from_array([
    ("operation", Json::string(operation)),
  ])
  let mut path = false
  let mut i = 2
  while i < args.length() {
    let arg = args[i]
    match arg {
      "--" => {
        if operation != "run" && operation != "exec" {
          raise @config.Invalid(
            "Program arguments require toolchain run or exec",
          )
        }
        fields["args"] = Json::array(args[i + 1:].to_owned().map(Json::string))
        break
      }
      "--yes" => {
        if operation != "setup" {
          raise @config.Invalid("--yes requires toolchain setup")
        }
        fields["consent"] = Json::boolean(true)
      }
      "--home" | "--target" | "--package" | "--timeout" => {
        if (arg == "--target" && operation != "build" && operation != "run") ||
          (arg == "--package" && operation != "run") {
          raise @config.Invalid("Unexpected option: " + arg)
        }
        i = i + 1
        if i == args.length() || args[i] == "" || args[i].has_prefix("-") {
          raise @config.Invalid("Missing value for " + arg)
        }
        let key = arg[2:].to_owned()
        if fields.contains(key) {
          raise @config.Invalid("Repeated option: " + arg)
        }
        fields[key] = if key == "timeout" {
          @json.parse(args[i])
        } else {
          Json::string(args[i])
        }
      }
      _ => {
        if arg.has_prefix("-") ||
          path ||
          operation == "info" ||
          operation == "setup" {
          raise @config.Invalid("Unexpected argument: " + arg)
        }
        path = true
        fields[if operation == "exec" { "script" } else { "directory" }] = Json::string(
          arg,
        )
      }
    }
    i = i + 1
  }
  let result = @toolchain.Host::platform().request(Json::object(fields))
  if mode is JSONLines {
    emit_record("toolchain", result)
  } else if mode is JSON {
    println(result.stringify())
  } else if result is Object(fields) {
    if fields.get("process") is Some(Object(process)) {
      if process.get("stdout") is Some(String(text)) {
        if text != "" {
          println(text)
        }
      }
      if process.get("stderr") is Some(String(text)) {
        @platform.stderr(text)
      }
    } else if fields.get("home") is Some(String(home)) {
      println("MoonBit " + @toolchain.compiler_version + "\nHome: " + home)
    } else if fields.get("supported") is Some(False) {
      println("Process tooling is unavailable on this host.")
    } else {
      println("No toolchain found. Run morphir toolchain setup --yes.")
    }
  }
  if result is Object(fields) {
    if fields.get("process") is Some(Object(process)) {
      if process.get("exitCode") is Some(Number(code, ..)) {
        return if code < 0.0 { 1 } else { code.to_int() }
      }
    }
  }
  0
}

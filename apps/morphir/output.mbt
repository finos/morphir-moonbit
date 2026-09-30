///|
priv enum OutputMode {
  Human
  JSON
  JSONLines
}

///|
fn emit_record(kind : String, data : Json) -> Unit {
  println(
    Json::object(
      Map::from_array([("type", Json::string(kind)), ("data", data)]),
    ).stringify(),
  )
}

///|
fn emit_workspace(value : Json, mode : OutputMode) -> Unit {
  match mode {
    JSON => println(value.stringify())
    JSONLines => {
      guard value is Object(fields) else { return }
      let metadata : Map[String, Json] = Map([])
      for key, item in fields {
        if key != "projects" {
          metadata[key] = item
        }
      }
      emit_record("workspace", Json::object(metadata))
      if fields.get("projects") is Some(Array(projects)) {
        for project in projects {
          emit_record("project", project)
        }
      }
    }
    Human => ()
  }
}

///|
fn emit_plan(
  sources : Array[String],
  destinations : Array[String],
  mode : OutputMode,
) -> Unit {
  if mode is JSONLines {
    for path in sources {
      emit_record("source", Json::string(path))
    }
    for path in destinations {
      emit_record("destination", Json::string(path))
    }
    emit_record(
      "plan",
      Json::object(
        Map::from_array([
          ("sourceCount", Json::number(sources.length().to_double())),
          ("destinationCount", Json::number(destinations.length().to_double())),
        ]),
      ),
    )
  } else {
    // Retain the existing dry-run JSON output in human mode.
    println(
      Json::object(
        Map::from_array([
          ("sources", Json::array(sources.map(Json::string))),
          ("destinations", Json::array(destinations.map(Json::string))),
        ]),
      ).stringify(),
    )
  }
}

///|
fn emit_result(value : Json, mode : OutputMode) -> Unit {
  if mode is JSONLines {
    guard value is Object(fields) else { return }
    for
      (key, kind) in [
        ("diagnostics", "diagnostic"),
        ("artifacts", "artifact"),
        ("committed", "committed"),
      ] {
      if fields.get(key) is Some(Array(items)) {
        for item in items {
          emit_record(kind, item)
        }
      }
    }
    let summary : Map[String, Json] = Map([])
    for key, item in fields {
      if key != "diagnostics" && key != "artifacts" && key != "committed" {
        summary[key] = item
      }
    }
    emit_record("result", Json::object(summary))
  } else {
    println(value.stringify())
  }
}

///|
fn print_error(message : String, mode : OutputMode) -> Unit {
  let value = Json::object(
    Map::from_array([
      ("successful", Json::boolean(false)),
      ("error", Json::string(message)),
      ("committed", Json::array([])),
    ]),
  )
  match mode {
    JSON => println(value.stringify())
    JSONLines => emit_record("error", value)
    Human => ()
  }
}

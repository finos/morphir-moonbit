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
        if key != "projects" && key != "validated" {
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
  boundaries : Array[@engine.BoundarySelection],
  mode : OutputMode,
  components? : Array[@engine.ComponentBoundary] = [],
) -> Unit {
  if mode is JSONLines {
    for component in components {
      emit_record("component", component_json(component))
    }
    for boundary in boundaries {
      emit_record("boundary", boundary_json(boundary))
    }
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
          ("boundaries", Json::array(boundaries.map(boundary_json))),
          ("components", Json::array(components.map(component_json))),
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
        ("boundaries", "boundary"),
        ("components", "component"),
        ("artifactDetails", "accepted"),
        ("projects", "generated"),
        ("validated", "validated"),
        ("diagnostics", "diagnostic"),
        ("artifacts", "artifact"),
        ("committed", "committed"),
        ("publicationDetails", "published"),
      ] {
      if fields.get(key) is Some(Array(items)) {
        for item in items {
          emit_record(kind, item)
        }
      }
    }
    let summary : Map[String, Json] = Map([])
    for key, item in fields {
      if key != "diagnostics" &&
        key != "artifacts" &&
        key != "committed" &&
        key != "publicationDetails" &&
        key != "boundaries" &&
        key != "components" &&
        key != "artifactDetails" &&
        key != "projects" &&
        key != "validated" {
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

///|
fn boundary_json(boundary : @engine.BoundarySelection) -> Json {
  Json::object(
    Map::from_array([
      ("source", Json::string(boundary.source)),
      ("unitId", Json::string(boundary.unit_id)),
      ("inputFormat", Json::string(boundary.input_format)),
      ("outputFormat", Json::string(boundary.output_format)),
      (
        "profile",
        match boundary.profile {
          Some(p) => Json::string(p)
          None => Json::null()
        },
      ),
      ("readBytes", Json::boolean(boundary.read_bytes)),
      ("writeBytes", Json::boolean(boundary.write_bytes)),
    ]),
  )
}

///|
fn artifact_json(artifact : @engine.ContentArtifact) -> Json {
  let (encoding, size) = match artifact.content {
    Text(text) => ("text", @utf8.encode(text).length())
    Binary(bytes) => ("binary", bytes.length())
  }
  Json::object(
    Map::from_array([
      ("path", Json::string(artifact.path)),
      ("source", Json::string(artifact.source)),
      ("format", Json::string(artifact.format)),
      ("encoding", Json::string(encoding)),
      ("bytes", Json::number(size.to_double())),
      ("status", Json::string("accepted")),
    ]),
  )
}

///|
fn project_json(project : @engine.LibraryProject) -> Json {
  Json::object(
    Map::from_array([
      ("id", Json::string(project.id)),
      ("source", Json::string(project.source)),
      ("root", Json::string(project.root)),
      ("members", Json::array(project.members.map(Json::string))),
      ("buildContract", Json::string(project.build_contract)),
      (
        "validation",
        Json::string(
          match project.policy {
            SourceOnly => "source-only"
            Required(_) => "required"
          },
        ),
      ),
      ("status", Json::string("generated")),
    ]),
  )
}

///|
fn validated_json(value : @host.ValidatedProject) -> Json {
  Json::object(
    Map::from_array([
      ("projectId", Json::string(value.project_id)),
      ("root", Json::string(value.root)),
      ("target", Json::string(value.target)),
      ("sourceIdentity", Json::string(value.source_identity)),
      ("receipt", Json::string(value.receipt)),
      ("status", Json::string("validated")),
      ("evidence", value.evidence),
    ]),
  )
}

///|
fn component_json(value : @engine.ComponentBoundary) -> Json {
  Json::object(
    Map::from_array([
      ("name", Json::string(value.name)),
      ("transport", Json::string(value.transport)),
      ("metadataPolicy", Json::string(value.metadata_policy)),
    ]),
  )
}

///|
fn tree(files : Array[(String, String)]) -> @workspace.Tree {
  let directories = [""]
  for file in files {
    let parts = file.0.split("/").map(StringView::to_owned).collect()
    for i in 1..<parts.length() {
      let directory = parts[:i].to_owned().join("/")
      if !directories.contains(directory) {
        directories.push(directory)
      }
    }
  }
  { files: Map::from_array(files), directories }
}

///|
fn failure(files : Array[(String, String)]) -> String {
  try {
    ignore(@workspace.discover(tree(files)))
    "accepted"
  } catch {
    @config.Invalid(message) => message
    error => "unexpected: " + error.to_string()
  }
}

///|
test "morphir.json is an Elm project with a Morphir IR JSON checkpoint" {
  let workspace = @workspace.discover(
    tree([
      (
        "morphir.json",
        "{\"name\":\"My.Pkg\",\"sourceDirectory\":\"lib\",\"exposedModules\":[\"Api\",\"Sub.Util\"]}",
      ),
    ]),
  )
  let project = workspace.projects[0]
  assert_eq(project.name, "My.Pkg")
  assert_eq(project.anchor, "morphir.json")
  let document = project.document
  assert_eq(document.text("frontend.language", ""), "elm")
  assert_eq(document.text("project.source_directory", ""), "lib")
  assert_eq(document.strings("project.exposed_modules"), ["Api", "Sub.Util"])
  assert_eq(document.text("pipeline.backend", ""), "checkpoint")
  assert_eq(document.text("pipeline.checkpoint_format", ""), "morphir-json")
  assert_eq(workspace.warnings, [])
}

///|
test "sourceDirectory defaults to src" {
  let document = @workspace.discover(
    tree([("morphir.json", "{\"name\":\"P\",\"exposedModules\":[\"A\"]}")]),
  ).projects[0].document
  assert_eq(document.text("project.source_directory", ""), "src")
}

///|
test "a bad morphir.json is a config error that names the file" {
  for
    text in [
      "{\"name\":\"P\"}", "{\"name\":\"P\",\"exposedModules\":\"A\"}", "{\"name\":\"P\",\"exposedModules\":[1]}",
      "{\"name\":\"P\",\"exposedModules\":[\"A B\"]}", "{\"name\":7,\"exposedModules\":[\"A\"]}",
      "{\"name\":\"\",\"exposedModules\":[\"A\"]}", "{\"name\":\"P\",\"sourceDirectory\":3,\"exposedModules\":[\"A\"]}",
      "[]",
    ] {
    let message = failure([("morphir.json", text)])
    assert_true(message.contains("morphir.json"), msg=text + " -> " + message)
  }
}

///|
test "ignored morphir.json fields give warnings" {
  let workspace = @workspace.discover(
    tree([
      (
        "morphir.json",
        "{\"name\":\"P\",\"exposedModules\":[\"A\"],\"dependencies\":[\"x\"],\"localDependencies\":[\"../y\"],\"decorations\":{\"d\":{}}}",
      ),
    ]),
  )
  assert_eq(workspace.warnings.length(), 3)
  for key in ["dependencies", "localDependencies", "decorations"] {
    assert_true(workspace.warnings.any(w => w.contains(key)))
  }
  let quiet = @workspace.discover(
    tree([
      (
        "morphir.json",
        "{\"name\":\"P\",\"exposedModules\":[\"A\"],\"dependencies\":[],\"localDependencies\":[],\"decorations\":{}}",
      ),
    ]),
  )
  assert_eq(quiet.warnings, [])
}

///|
test "morphir.toml beside morphir.json wins and keeps its language" {
  let workspace = @workspace.discover(
    tree([
      ("morphir.toml", "[project]\nname='Toml'\n"),
      ("morphir.json", "{\"name\":\"Json\",\"exposedModules\":[\"A\"]}"),
    ]),
  )
  let project = workspace.projects[0]
  assert_eq(project.name, "Toml")
  assert_eq(project.document.text("frontend.language", ""), "scheme")
  assert_true(workspace.warnings.any(w => w.contains("legacy manifest")))
}

///|
test "members of morphir-workspace.json are Elm projects" {
  let workspace = @workspace.discover(
    tree([
      ("morphir-workspace.json", "{\"projects\":[\"one\",\"two\"]}"),
      ("one/morphir.json", "{\"name\":\"One\",\"exposedModules\":[\"A\"]}"),
      ("two/morphir.json", "{\"name\":\"Two\",\"exposedModules\":[\"B\"]}"),
    ]),
  )
  assert_eq(
    workspace.projects.map(p => (p.name, p.document.text("frontend.language", ""))),
    [("One", "elm"), ("Two", "elm")],
  )
}

///|
test "an overlay can still choose another language" {
  let workspace = @workspace.discover(
    tree([("morphir.json", "{\"name\":\"P\",\"exposedModules\":[\"A\"]}")]),
    overlay=@config.parse("[frontend]\nlanguage='scheme'"),
  )
  assert_eq(
    workspace.projects[0].document.text("frontend.language", ""),
    "scheme",
  )
}

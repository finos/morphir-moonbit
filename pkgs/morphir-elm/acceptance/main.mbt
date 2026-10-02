///|
fn project(
  name : String,
  ir : @ir.IRFile,
  options : @elm.Options,
) -> Json raise {
  let output = @elm.generate(name, ir, options)
  Json::object(
    Map::from_array([
      ("name", Json::string(name)),
      (
        "files",
        Json::array(
          output.files.map(f => {
            Json::object(
              Map::from_array([
                ("path", Json::string(f.path)),
                ("content", Json::string(f.content)),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
}

///|
fn main raise {
  let model = @elm.Options::default()
  let todo = { ..model, placeholders: DebugTodo, }
  let projects = [
    project("rentals", @fixtures.rentals(), model),
    project("shapes", @fixtures.shapes(), model),
    project("specs", @fixtures.specs(), todo),
  ]
  println(
    Json::object(Map::from_array([("projects", Json::array(projects))])).stringify(),
  )
}

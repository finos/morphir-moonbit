///|
fn receive_workspace(
  model : Model,
  request_id : Int32,
  revision : Int32,
  reply : Json,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let projects = items(field(reply, "projects"))
  let selected = current_project_path(model).to_string()
  let current = projects
    .iter()
    .find_first(p => {
      text(p, "path") == (if selected == "" { "." } else { selected })
    })
    .unwrap_or(projects.get(0).unwrap_or(Json::null()))
  let result = project_model_result(model, field(current, "result"))
  let fields = match result {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields["artifacts"] = field(reply, "artifacts")
  fields["workspaceProjects"] = Json::array(projects)
  let combined = Json::object(fields)
  let (next, command) = if projects.is_empty() {
    ({ ..model, busy: false, output: combined, }, @cmd.none)
  } else {
    update_core(
      model,
      Receive(request_id, revision, "compile", combined.stringify()),
      emit,
    )
  }
  let mut next = { ..next, output: combined, output_revision: revision, }
  let mut passed = 0
  for project in projects {
    let result = field(project, "result")
    next = reported(
      next,
      "Compile " + text(project, "name"),
      "source",
      revision,
      @bottom_panel.reply_diagnostics(result),
    )
    if field(result, "success") == Json::boolean(true) {
      passed += 1
    } else {
      next = note(
        next,
        "Compile " + text(project, "name"),
        @bottom_panel.Error,
        text(result, "message"),
      )
    }
  }
  (
    {
      ..next,
      busy: false,
      status: "Compiled " +
      passed.to_string() +
      "/" +
      projects.length().to_string() +
      " projects",
    },
    command,
  )
}

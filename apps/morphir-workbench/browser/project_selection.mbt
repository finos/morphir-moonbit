///|
fn project_model_result(model : Model, result : Json) -> Json {
  items(field(result, "units"))
  .iter()
  .find_first(unit => {
    model.workspace_files.opened() == Some(text(unit, "source"))
  })
  .unwrap_or(result)
}

///|
/// Cached results belong to project paths. A file in another project changes the model used by evaluation.
fn follow_current_project(before : Model, next : Model) -> Model {
  let same_project = (before.workspace_files.current() catch { _ => None }) ==
    (next.workspace_files.current() catch { _ => None })
  if host_execution_blocks_replacement(next) ||
    (
      same_project &&
      before.workspace_files.opened() == next.workspace_files.opened()
    ) {
    return next
  }
  let projects = items(field(next.output, "workspaceProjects"))
  let current = next.workspace_files.current() catch { _ => None }
  let path = current.map(p => p.to_string()).unwrap_or("")
  let found = projects
    .iter()
    .find_first(p => {
      current is Some(_) &&
      text(p, "path") == (if path == "" { "." } else { path })
    })
  let result = found
    .map(project => field(project, "result"))
    .unwrap_or(Json::null())
  let selected = project_model_result(next, result)
  // Workspace-level notes keep the last source model within the current project.
  if same_project && selected == result {
    return next
  }
  let result = selected
  let document = if field(result, "success") == Json::boolean(true) &&
    next.output_revision == next.revision {
    next.document.replace(result) catch {
      _ => @document.State::new()
    }
  } else {
    @document.State::new()
  }
  {
    ..next,
    document,
    selected: "",
    query: "",
    collapsed_modules: [],
    evaluation_result: Json::null(),
    evaluation_entry: "",
    model_revision: next.model_revision + 1,
    evaluation_revision: next.evaluation_revision + 1,
  }
}

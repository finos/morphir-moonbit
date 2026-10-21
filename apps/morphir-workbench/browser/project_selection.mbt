///|
/// Cached results belong to project paths. A file in another project changes the model used by evaluation.
fn follow_current_project(before : Model, next : Model) -> Model {
  if current_project_path(before) == current_project_path(next) ||
    host_execution_blocks_replacement(next) {
    return next
  }
  let projects = items(field(next.output, "workspaceProjects"))
  if projects.is_empty() || next.document.original() is Some(_) {
    return next
  }
  let path = current_project_path(next).to_string()
  let found = projects
    .iter()
    .find_first(p => text(p, "path") == (if path == "" { "." } else { path }))
  let result = found
    .map(project => field(project, "result"))
    .unwrap_or(Json::null())
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

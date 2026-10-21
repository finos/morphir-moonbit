///|
/// Cached results belong to project paths. A file in another project changes the model used by evaluation.
fn follow_current_project(before : Model, next : Model) -> Model {
  if (before.workspace_files.current() catch { _ => None }) ==
    (next.workspace_files.current() catch { _ => None }) ||
    host_execution_blocks_replacement(next) {
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

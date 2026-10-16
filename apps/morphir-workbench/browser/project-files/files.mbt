///|
/// The inline edit in progress: nothing, a new path, a rename draft or a delete waiting for its answer.
pub(all) enum Edit {
  Idle
  Adding(String)
  Renaming(@ids.SourcePath, String)
  Deleting(@ids.SourcePath)
} derive(Eq)

///|
pub(all) struct State {
  edit : Edit
  error : String
} derive(Eq)

///|
pub fn State::new() -> State {
  { edit: Idle, error: "", }
}

///|
pub(all) enum Action {
  Open(String)
  StartAdd
  AddDraft(String)
  ConfirmAdd
  StartRename(String)
  RenameDraft(String)
  ConfirmRename
  StartDelete(String)
  ConfirmDelete
  Cancel
  PackageName(String)
  Exposed(String, Bool)
}

///|
pub(all) struct Props {
  project : @project.Project
  rules : @project.FileRules
  state : State
  counts : Map[String, Int32]
  busy : Bool
}

///|
/// A path from the page; a path no file has (a stale entry) is refused with a message, never a crash.
fn known_path(
  project : @project.Project,
  text : String,
) -> @ids.SourcePath raise @project.ProjectError {
  let parsed = @ids.SourcePath::parse(text) catch {
    _ =>
      raise @project.ProjectError(
        "workbench.invalid_path",
        "Use a relative path with / between folders: " + text,
      )
  }
  if !project.files.iter().any(f => f.path == parsed) {
    raise @project.ProjectError(
      "workbench.missing_file",
      "No file has this path: " + text,
    )
  }
  parsed
}

///|
/// The edit machine: one action moves the inline edit and the project. A refused edit keeps the project and
/// reports the refusal in `error`.
pub fn apply(
  state : State,
  project : @project.Project,
  rules : @project.FileRules,
  action : Action,
) -> (State, @project.Project) {
  try {
    match (action, state.edit) {
      (Open(text), _) =>
        (
          { edit: state.edit, error: "", },
          project.set_active(known_path(project, text)),
        )
      (StartAdd, _) => {
        if rules.add_reason() is Some(reason) {
          raise @project.ProjectError("workbench.one_file_language", reason)
        }
        ({ edit: Adding("src/"), error: "", }, project)
      }
      (AddDraft(text), Adding(_)) =>
        ({ edit: Adding(text), error: "", }, project)
      (ConfirmAdd, Adding(text)) =>
        (State::new(), project.add_file(rules, text))
      (StartRename(text), _) => {
        let from = known_path(project, text)
        ({ edit: Renaming(from, text), error: "", }, project)
      }
      (RenameDraft(text), Renaming(from, _)) =>
        ({ edit: Renaming(from, text), error: "", }, project)
      (ConfirmRename, Renaming(from, text)) =>
        (State::new(), project.rename_file(rules, from, text))
      (StartDelete(text), _) =>
        ({ edit: Deleting(known_path(project, text)), error: "", }, project)
      (ConfirmDelete, Deleting(path)) =>
        (State::new(), project.delete_file(path))
      (Cancel, _) => (State::new(), project)
      (PackageName(text), _) =>
        ({ edit: state.edit, error: "", }, project.set_name(text))
      (Exposed(module_name, exposed), _) => {
        let parsed = @ids.SourceModuleName::parse(module_name) catch {
          _ =>
            raise @project.ProjectError(
              "workbench.invalid_module",
              "Not a module name: " + module_name,
            )
        }
        ({ edit: state.edit, error: "", }, project.set_exposed(parsed, exposed))
      }
      // An answer with no question open, such as a double click: nothing to do.
      _ => (state, project)
    }
  } catch {
    @project.ProjectError(_, message) => {
      // A refused delete closes its question; a refused add or rename stays open so the path can be corrected.
      let edit = match state.edit {
        Deleting(_) => Idle
        other => other
      }
      ({ edit, error: message, }, project)
    }
  }
}

///|
fn button(
  label : String,
  on_click : @cmd.Cmd,
  name~ : String = label,
  disabled~ : Bool = false,
  title~ : String = "",
  class~ : String = "secondary small",
) -> @html.Html {
  @html.button(
    class~,
    disabled~,
    title~,
    attrs=@html.Attrs::build().aria_label(name),
    on_click~,
    label,
  )
}

///|
fn file_row(
  props : Props,
  emit : @cmd.Emit[Action],
  file : @project.ProjectFile,
) -> @html.Html {
  let path = file.path.to_string()
  let active = file.path == props.project.active
  match props.state.edit {
    Renaming(from, draft) if from == file.path =>
      @html.li(class="file-row editing", [
        @html.input(
          value=draft,
          attrs=@html.Attrs::build().aria_label("New path of " + path),
          on_input=emit.map(value => RenameDraft(value)),
        ),
        button("Rename", emit(ConfirmRename), name="Confirm rename"),
        button("Cancel", emit(Cancel), name="Cancel rename"),
      ])
    Deleting(target) if target == file.path =>
      @html.li(class="file-row editing", [
        @html.span("Delete " + path + "?"),
        button(
          "Delete",
          emit(ConfirmDelete),
          name="Delete",
          class="danger small",
        ),
        button("Keep", emit(Cancel)),
      ])
    _ => {
      let count = props.counts.get(path).unwrap_or(0)
      let open : Array[@html.Html] = [@html.span(class="file-path", path)]
      if count > 0 {
        open.push(
          @html.span(
            class="file-count",
            title=count.to_string() + " problems",
            count.to_string(),
          ),
        )
      }
      @html.li(class="file-row", [
        @html.button(
          class=if active { "file-open active" } else { "file-open" },
          attrs=@html.Attrs::build()
            .aria_label(path)
            .aria_current(if active { "true" } else { "false" }),
          on_click=emit(Open(path)),
          open,
        ),
        button(
          "Rename",
          emit(StartRename(path)),
          name="Rename " + path,
          disabled=props.busy,
        ),
        button(
          "Delete",
          emit(StartDelete(path)),
          name="Delete " + path,
          disabled=props.busy,
        ),
      ])
    }
  }
}

///|
fn settings(props : Props, emit : @cmd.Emit[Action]) -> @html.Html {
  @html.div(class="project-settings", [
    @html.label([
      @html.span(class="small muted", "Package name"),
      @html.input(
        value=props.project.name.to_string(),
        attrs=@html.Attrs::build()
          .aria_label("Package name")
          .value_prop(props.project.name.to_string()),
        on_change=emit.map(value => PackageName(value)),
      ),
    ]),
    @html.div(
      props.project
      .modules()
      .map(entry => {
        let (module_name, exposed) = entry
        let name = module_name.to_string()
        @html.label(class="small", [
          @html.input(
            input_type=Checkbox,
            checked=exposed,
            attrs=@html.Attrs::build()
              .aria_label("Expose " + name)
              .on_click(_ => emit(Exposed(name, !exposed))),
          ),
          @html.span(" exposed: " + name),
        ])
      }),
    ),
  ])
}

///|
pub fn view(props : Props, emit : @cmd.Emit[Action]) -> @html.Html {
  let reason = props.rules.add_reason()
  let adding : Array[@html.Html] = match props.state.edit {
    Adding(draft) =>
      [
        @html.input(
          value=draft,
          attrs=@html.Attrs::build()
            .aria_label("New file path")
            .value_prop(draft),
          on_input=emit.map(value => AddDraft(value)),
        ),
        button("Add", emit(ConfirmAdd), name="Confirm add"),
        button("Cancel", emit(Cancel), name="Cancel add"),
      ]
    _ =>
      [
        button(
          "Add file",
          emit(StartAdd),
          disabled=props.busy || reason is Some(_),
          title=reason.unwrap_or(""),
        ),
      ]
  }
  let children : Array[@html.Html] = [
    @html.ul(
      class="file-list",
      props.project.files.map(file => file_row(props, emit, file)),
    ),
    @html.div(class="file-add", adding),
    @html.p(
      class="file-error small",
      hidden=props.state.error == "",
      attrs=@html.Attrs::build().role("alert"),
      props.state.error,
    ),
  ]
  if reason is None {
    children.push(settings(props, emit))
  }
  @html.nav(
    class="project-files",
    attrs=@html.Attrs::build().aria_label("Project files"),
    children,
  )
}

///|
pub extend Edit with Eq::{not_equal, equal}

///|
pub extend State with Eq::{not_equal, equal}

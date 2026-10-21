///|
fn multiple_projects() -> Model {
  let files = known(() => {
    @workspace_files.Files::new(
      Map([
        (
          "morphir.toml", "# Keep\n[workspace]\nmembers=['packages/*']\n[frontend]\nlanguage='scheme'\n[pipeline]\nbackend='scheme'\n",
        ),
        ("packages/one/morphir.toml", "# One\n[project]\nname='One'\n"),
        ("packages/one/src/main.scm", "11"),
        ("packages/two/morphir.toml", "[project]\nname='Two'\n"),
        ("packages/two/src/main.scm", "22"),
      ]),
    )
  })
  with_workspace_files({ ..source_model("scheme"), available: true, }, files)
}

///|
test "opening a project selects its compiled model and invalidates an earlier revision" {
  let before = run_all(multiple_projects(), [
    OpenWorkspaceFile("packages/one/src/main.scm"),
  ])
  let reply = @pipeline.execute(compile_request(before, "compile"))
  let compiled = run_all({ ..before, request_id: 8, busy: true, }, [
    Receive(8, before.revision, "compile-workspace", reply.stringify()),
  ])
  assert_eq(text(compiled.document.inspection(), "package"), "one")
  let two = run_all(compiled, [OpenWorkspaceFile("packages/two/src/main.scm")])
  assert_eq(text(two.document.inspection(), "package"), "two")
  let edited = run_all(two, [
    Source("33"),
    OpenWorkspaceFile("packages/one/src/main.scm"),
  ])
  assert_eq(edited.document.inspection(), Json::null())
}

///|
test "add and remove use shared scaffolding and allow two projects of the same language" {
  let before = multiple_projects()
  let added = run_all(before, [
    AddWorkspaceProject,
    EditNewProject(Name, "Three"),
    EditNewProject(Folder, "packages/three"),
    CreateWorkspaceProject,
  ])
  assert_eq(discovered_projects(added).length(), 3)
  assert_eq(current_project_path(added).to_string(), "packages/three")
  assert_eq(
    added.workspace_files.read("morphir.toml"),
    before.workspace_files.read("morphir.toml"),
  )
  let path = known(() => @discovery.ProjectPath::parse("packages/three"))
  let removed = run_all(added, [AskRemoveProject(path), RemoveWorkspaceProject])
  assert_eq(discovered_projects(removed).length(), 2)
  assert_true(
    removed.workspace_files.read("packages/three/src/main.scm") is Some(_),
  )
  let deleted = run_all(added, [
    AskRemoveProject(path),
    DeleteProjectFiles(true),
    RemoveWorkspaceProject,
  ])
  assert_eq(deleted.workspace_files.read("packages/three/src/main.scm"), None)
}

///|
test "file commands preserve bytes and refuse outside paths and collisions" {
  let model = multiple_projects()
  let created = run_all(model, [
    AskWorkspaceFile(Create, ""),
    WorkspaceFilePath("notes.md"),
    CommitWorkspaceFile,
    Source("Keep λ😀\n"),
  ])
  let invalid = run_all(created, [
    AskWorkspaceFile(Rename, "notes.md"),
    WorkspaceFilePath("../escape"),
    CommitWorkspaceFile,
  ])
  assert_eq(invalid.workspace_files, created.workspace_files)
  let collision = run_all(created, [
    AskWorkspaceFile(Rename, "notes.md"),
    WorkspaceFilePath("morphir.toml"),
    CommitWorkspaceFile,
  ])
  assert_eq(collision.workspace_files, created.workspace_files)
  let moved = run_all(created, [
    AskWorkspaceFile(Rename, "notes.md"),
    WorkspaceFilePath("docs/notes.md"),
    CommitWorkspaceFile,
  ])
  assert_eq(moved.workspace_files.read("notes.md"), None)
  assert_eq(moved.workspace_files.read("docs/notes.md"), Some("Keep λ😀\n"))
  let removed = run_all(moved, [
    AskWorkspaceFile(Delete, "docs/notes.md"),
    CommitWorkspaceFile,
  ])
  assert_eq(removed.workspace_files.read("docs/notes.md"), None)
}

///|
test "project settings edit the selected manifest and leave inherited settings intact" {
  let model = multiple_projects()
  let path = known(() => @discovery.ProjectPath::parse("packages/one"))
  let changed = run_all(model, [
    ProjectSetting("packages/one", @workspace_files.Generation, "elm"),
  ])
  assert_eq(
    changed.workspace_files.setting(path, @workspace_files.Generation).effective,
    Some("elm"),
  )
  assert_true(
    changed.workspace_files
    .read("packages/one/morphir.toml")
    .unwrap()
    .has_prefix("# One\n[project]\nname='One'\n"),
  )
  let inherited = run_all(changed, [
    ProjectSetting("packages/one", @workspace_files.Generation, ""),
  ])
  assert_eq(
    inherited.workspace_files.setting(path, @workspace_files.Generation).effective,
    Some("scheme"),
  )
  assert_eq(
    inherited.workspace_files.setting(path, @workspace_files.Generation).override_value,
    None,
  )
  assert_eq(
    inherited.workspace_files.read("morphir.toml"),
    model.workspace_files.read("morphir.toml"),
  )
}

///|
test "a read-only location refuses edits even when a message bypasses disabled controls" {
  let model = { ..multiple_projects(), connected: true, project_dialog: None, }
  for
    message in [
      Source("overwrite"),
      AddWorkspaceProject,
      AskWorkspaceFile(Create, ""),
      ProjectSetting("packages/one", @workspace_files.Generation, "elm"),
    ] {
    let after = run_all(model, [message])
    assert_eq(after.workspace_files, model.workspace_files)
    assert_true(after.project_dialog is None)
  }
}

///|
test "file saves commit a complete generation and collect only obsolete workspace records" {
  let restore = storage_test_environment("")
  defer restore()
  let model = multiple_projects()
  let first = write_projects(model)
  assert_true(first.storage_ok)
  ignore(storage_save("unrelated.files.keep", "keep"))
  let pending_key = workspace_prefix(model) + ".files.another-tab.0"
  ignore(storage_save(pending_key, "uncommitted record from another tab"))
  let edited = run_all(first, [
    OpenWorkspaceFile("packages/one/src/main.scm"),
    Source("33"),
  ])
  let written = write_projects(edited)
  assert_true(written.storage_ok)
  assert_eq(
    stored_keys(workspace_prefix(written) + ".files.").length(),
    written.workspace_files.paths().length() + 1,
  )
  assert_eq(storage_load(pending_key), "uncommitted record from another tab")
  let loaded = restore_all(written)
  assert_eq(loaded.workspace_files, written.workspace_files)
  assert_eq(storage_load("unrelated.files.keep"), "keep")
}

///|
test "ordinary drafts are files of their project or workspace" {
  let model = run_all(multiple_projects(), [
    OpenWorkspaceFile("packages/two/src/main.scm"),
    AddContent(Intent),
    IntentText("Price orders"),
    AddContent(ConceptualModel),
    ConceptText("concept"),
    AddContent(Worksheet),
    Source("(+ 1 2)"),
  ])
  assert_eq(
    model.workspace_files.read("packages/two/intent.md"),
    Some("Price orders"),
  )
  assert_eq(
    model.workspace_files.read("packages/two/src/model.mfs"),
    Some("concept"),
  )
  assert_eq(model.workspace_files.read("worksheet.scm"), Some("(+ 1 2)"))
}

///|
test "quick open lists every workspace file and selects a same-language project" {
  let model = multiple_projects()
  let opened = run_all(model, [
    RunCommand(GoToFile),
    Palette(Query("two/src/main")),
    Palette(Key(@keys.Chord::plain("Enter"))),
  ])
  assert_eq(opened.workspace_files.opened(), Some("packages/two/src/main.scm"))
  assert_eq(current_project_path(opened).to_string(), "packages/two")
}

///|
test "reset keeps project identity settings and a custom source directory" {
  let model = run_all(multiple_projects(), [
    ProjectSetting("packages/one", @workspace_files.SourceDirectory, "lib"),
    OpenWorkspaceFile("packages/one/morphir.toml"),
  ])
  let reset = run_all(model, [ConfirmReset])
  assert_eq(reset.workspace_files.discover().projects[0].name, "One")
  assert_true(
    reset.workspace_files.paths().any(p => p.has_prefix("packages/one/lib/")),
  )
  assert_eq(reset.workspace_files.read("packages/two/src/main.scm"), Some("22"))
  assert_eq(reset.workspace_files.read("packages/one/src/main.scm"), Some("11"))
  let path = known(() => @discovery.ProjectPath::parse("packages/one"))
  assert_eq(
    reset.workspace_files.setting(path, @workspace_files.SourceDirectory).effective,
    Some("lib"),
  )
}

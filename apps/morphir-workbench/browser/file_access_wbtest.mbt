///|
fn folder_model() -> Model {
  let model = create(starting_model(), SourceProject, contents=[SourceProject])
  {
    ..model,
    file_access: Writable({
      grant: known(() => @filewire.GrantId::parse("folder-test")),
      revision: 1,
      saved_revision: model.revision,
      name: "Folder",
      state: Idle,
    }),
  }
}

///|
test "folder saves acknowledge their captured revision and coalesce later source edits" {
  let before = folder_model()
  let edited = run_all(before, [Source("22")])
  let saving = run_all(edited, [SaveProject(edited.revision)])
  assert_false(saving.busy)
  guard saving.file_access is Writable(authority) &&
    authority.state is Saving(active) else {
    fail("No pending file save")
  }
  assert_eq(active, edited.revision)
  let later = run_all(saving, [Source("33"), SaveProject(edited.revision + 1)])
  guard later.file_access is Writable(later_authority) &&
    later_authority.state is Saving(still_active) else {
    fail("Pending file save was replaced")
  }
  assert_eq(still_active, active)
  let acknowledged = run_all(later, [
    FilesSaved(authority.grant, active, "{\"success\":true,\"revision\":2}"),
  ])
  guard acknowledged.file_access is Writable(saved) && saved.state is Idle else {
    fail("No acknowledged file save")
  }
  assert_eq(saved.revision, 2)
  assert_eq(saved.saved_revision, active)
  assert_eq(
    acknowledged.workspace_files.read(source_name(acknowledged)),
    Some("33"),
  )
  let coalesced = run_all(acknowledged, [SaveProject(acknowledged.revision)])
  guard coalesced.file_access is Writable(pending) &&
    pending.state is Saving(captured) else {
    fail("Later edit did not save")
  }
  assert_eq(captured, acknowledged.revision)
  let obsolete = run_all(coalesced, [
    FilesSaved(authority.grant, active, "{\"success\":true,\"revision\":2}"),
  ])
  assert_true(obsolete.file_access == coalesced.file_access)
}

///|
test "a parked workspace receives its file save without changing the visible workspace" {
  let first = folder_model()
  let edited = run_all(first, [Source("22")])
  let saving = run_all(edited, [SaveProject(edited.revision)])
  let visit = visit_of(saving).unwrap()
  guard saving.file_access is Writable(authority) else {
    fail("Folder authority")
  }
  let other = create(saving, Empty, contents=[])
  let acknowledged = run_all(other, [
    Routed(
      visit,
      FilesSaved(
        authority.grant,
        edited.revision,
        "{\"success\":true,\"revision\":2}",
      ),
    ),
  ])
  assert_eq(acknowledged.active, other.active)
  assert_eq(acknowledged.workspace_files, other.workspace_files)
  guard viewing(acknowledged, visit.workspace) is Some(parked) &&
    parked.file_access is Writable(saved) else {
    fail("Parked folder")
  }
  assert_eq(saved.revision, 2)
  assert_eq(saved.saved_revision, edited.revision)
}

///|
test "failed saves retain editable drafts and restored folders have no disk authority" {
  let restore = storage_test_environment("")
  defer restore()
  let before = folder_model()
  let edited = run_all(before, [Source("22")])
  let saving = run_all(edited, [SaveProject(edited.revision)])
  guard saving.file_access is Writable(authority) else {
    fail("Folder authority")
  }
  let blocked = run_all(saving, [
    FilesSaved(
      authority.grant,
      edited.revision,
      "{\"success\":false,\"message\":\"Disk changed\"}",
    ),
    Source("33"),
  ])
  guard blocked.file_access is Writable(failed) && failed.state is Blocked(_) else {
    fail("Save was not blocked")
  }
  assert_eq(blocked.workspace_files.read(source_name(blocked)), Some("33"))
  let refused = run_all(blocked, [SaveProject(blocked.revision)])
  assert_true(refused.file_access == blocked.file_access)
  let restored = restore_all_with(
    { ..blocked, file_access: Memory, },
    storage_load,
  )
  guard restored.file_access is Detached(name) else {
    fail("Restored a live grant from storage")
  }
  assert_eq(name, "Folder")
}

///|
test "read-only folder authority guards source edits and project mutations" {
  let model = { ..folder_model(), file_access: ReadOnly("Older host"), }
  let refused = run_all(model, [
    Source("22"),
    AddWorkspaceProject,
    WorkspaceSetting(@workspace_files.DefaultMember, "other"),
    ConvertLegacyProject("."),
  ])
  assert_eq(refused.workspace_files, model.workspace_files)
  assert_true(refused.project_dialog is None)
}

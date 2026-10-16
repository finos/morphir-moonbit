///|
test "add, rename and delete go through confirm steps and report refusals" {
  let rules = elm_rules()
  let (s1, p1) = @project_files.apply(
    @project_files.State::new(),
    shop(),
    rules,
    StartAdd,
  )
  let (s2, p2) = @project_files.apply(
    s1,
    p1,
    rules,
    AddDraft("src/Shop/Orders/Util.elm"),
  )
  let (s3, p3) = @project_files.apply(s2, p2, rules, ConfirmAdd)
  let (s4, p4) = @project_files.apply(
    s3,
    p3,
    rules,
    StartDelete("src/Shop/Orders/Util.elm"),
  )
  let (s5, p5) = @project_files.apply(s4, p4, rules, ConfirmDelete)
  let (s6, p6) = @project_files.apply(
    s5,
    p5,
    rules,
    StartDelete("src/Shop/Orders/Api.elm"),
  )
  let (s7, _) = @project_files.apply(s6, p6, rules, ConfirmDelete)
  @expect.expect_all(s => {
    s.expect(p3.files.length(), label="added").to_equal(2)
    s.expect(s3.edit == Idle, label="idle after add").to_be_true()
    s.expect(p5.files.length(), label="deleted").to_equal(1)
    s
    .expect(s7.error, label="last file refused")
    .to_contain("at least one file")
  })
}

///|
test "package name and exposure edits update the project" {
  let (_, renamed) = @project_files.apply(
    @project_files.State::new(),
    shop(),
    elm_rules(),
    PackageName("Shop.Billing"),
  )
  let (_, hidden) = @project_files.apply(
    @project_files.State::new(),
    shop(),
    elm_rules(),
    Exposed("Api", false),
  )
  let (bad, kept) = @project_files.apply(
    @project_files.State::new(),
    shop(),
    elm_rules(),
    PackageName("a b"),
  )
  @expect.expect_all(s => {
    s.expect(renamed.name.to_string(), label="name").to_equal("Shop.Billing")
    s.expect(hidden.exposed, label="hidden").to_be_empty()
    s.expect(kept.name.to_string(), label="kept").to_equal("Shop.Orders")
    s.expect(bad.error, label="error").not().to_be_empty()
  })
}

///|
test "a stale or invalid path is refused without a crash" {
  let rules = elm_rules()
  let state = @project_files.State::new()
  let (opened, project) = @project_files.apply(
    state,
    shop(),
    rules,
    Open("src/Gone.elm"),
  )
  let (renaming, _) = @project_files.apply(
    state,
    shop(),
    rules,
    StartRename("not a /../ path"),
  )
  let (answered, kept) = @project_files.apply(
    state,
    shop(),
    rules,
    ConfirmDelete,
  )
  @expect.expect_all(s => {
    s
    .expect(opened.error, label="stale open")
    .to_contain("No file has this path")
    s.expect(project, label="project kept").to_equal(shop())
    s.expect(renaming.error, label="invalid rename").not().to_be_empty()
    s.expect(answered == state, label="answer without question").to_be_true()
    s.expect(kept, label="unchanged").to_equal(shop())
  })
}

///|
test "a one-file language refuses Add file with its reason" {
  let rules : @project.FileRules = { ..elm_rules(), layout: OneFile, }
  let (state, project) = @project_files.apply(
    @project_files.State::new(),
    shop(),
    rules,
    StartAdd,
  )
  @expect.expect_all(s => {
    s.expect(state.error, label="reason").to_contain("morphir-ukvn.5.22.14")
    s.expect(state.edit == Idle, label="idle").to_be_true()
    s.expect(project, label="project").to_equal(shop())
  })
}

///|
/// Property: Cancel always returns to Idle without changing the project.
test "cancel never changes the project" {
  @expect.for_all((step : UInt32) => {
    let start = match step % 3 {
      0 => @project_files.Action::StartAdd
      1 => StartRename("src/Shop/Orders/Api.elm")
      _ => StartDelete("src/Shop/Orders/Api.elm")
    }
    let (s1, p1) = @project_files.apply(
      @project_files.State::new(),
      shop(),
      elm_rules(),
      start,
    )
    let (s2, p2) = @project_files.apply(s1, p1, elm_rules(), Cancel)
    @expect.expect_all(s => {
      s.expect(p2, label="project").to_equal(shop())
      s.expect(s2.edit == Idle, label="idle").to_be_true()
    })
  })
}

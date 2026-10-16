///|
test "restore accepts a valid project and refuses corrupt ones with a note" {
  let model = { ..scope_model(), catalog: catalog_fixture(), }
  let good = active_project({ ..model, language: "elm", }).to_json().stringify()
  let (ok, none) = restored(model, "elm", good)
  let wrong_language = active_project({ ..model, language: "scheme", })
    .to_json()
    .stringify()
  let (mismatch, mismatch_note) = restored(model, "elm", wrong_language)
  @expect.expect_all(s => {
    s.expect(none, label="no note").to_equal("")
    s
    .expect(
      ok.language_projects.get("elm").map(p => p.name.to_string()),
      label="restored",
    )
    .to_equal(Some("Workbench"))
    s
    .expect(
      mismatch.language_projects.contains("elm"),
      label="mismatch kept default",
    )
    .to_be_false()
    s
    .expect(mismatch_note, label="mismatch note")
    .to_contain("Could not restore the saved elm project")
    for
      text in [
        "{", "{\"version\":2}", "{\"version\":1,\"name\":\"A\",\"languageId\":\"elm\",\"files\":[{\"path\":\"../a.elm\",\"content\":\"\"}],\"active\":\"../a.elm\"}",
      ] {
      let (kept, note) = restored(model, "elm", text)
      s
      .expect(note, label=text)
      .to_contain("Could not restore the saved elm project")
      s
      .expect(
        kept.language_projects.contains("elm"),
        label=text + " kept default",
      )
      .to_be_false()
    }
    let (empty, quiet) = restored(model, "elm", "")
    s.expect(quiet, label="nothing stored").to_equal("")
    s
    .expect(empty.language_projects.contains("elm"), label="nothing restored")
    .to_be_false()
  })
}

///|
/// Property: whatever text storage returns, restore never raises and either restores, notes, or finds nothing stored.
test "restore is total over any stored text" {
  @expect.for_all((chars : Array[Char]) => {
    let model = { ..scope_model(), catalog: catalog_fixture(), }
    let text = String::from_array(chars)
    let (after, note) = restored(model, "elm", text)
    @expect.expect(
      after.language_projects.contains("elm") || note != "" || text == "",
      label="restored, noted or empty",
    ).to_be_true()
  })
}

///|
test "a change saves once, for the current revision only, and a failed save shows Not saved" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(model, Source("(define a 1)"), emit)
  let (stale, _) = update(
    edited,
    SaveProject("scheme", edited.revision - 1),
    emit,
  )
  let (current, _) = update(
    edited,
    SaveProject("scheme", edited.revision),
    emit,
  )
  @expect.expect_all(s => {
    s.expect(stale.storage_ok, label="stale save ignored").to_be_true()
    s
    .expect(current.storage_ok, label="outside a browser the save fails")
    .to_be_false()
  })
}

///|
test "reset asks first, then restores the default project" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(model, Source("(define a 1)"), emit)
  let (asked, _) = update(edited, AskReset, emit)
  let (kept, _) = update(asked, CancelReset, emit)
  let (done, _) = update(asked, ConfirmReset, emit)
  @expect.expect_all(s => {
    s.expect(asked.reset_asking, label="asking").to_be_true()
    s.expect(active_text(asked), label="not yet").to_equal("(define a 1)")
    s.expect(kept.reset_asking, label="kept closes").to_be_false()
    s.expect(active_text(kept), label="kept text").to_equal("(define a 1)")
    s.expect(done.reset_asking, label="done closes").to_be_false()
    s
    .expect(active_text(done), label="default")
    .to_contain("(define (price quantity)")
  })
}

///|
test "a language switch inside the debounce window still saves the earlier edit" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(model, Source("(define a 1)"), emit)
  let (switched, _) = update(edited, Language("moonbit"), emit)
  let (typed, _) = update(switched, Source("pub fn x() -> Bool { true }"), emit)
  let (first, _) = update(typed, SaveProject("scheme", edited.revision), emit)
  let (second, _) = update(typed, SaveProject("moonbit", typed.revision), emit)
  @expect.expect_all(s => {
    s.expect(typed.dirty, label="both dirty").to_equal(["scheme", "moonbit"])
    s
    .expect(first.save_attempts, label="stale save writes nothing")
    .to_equal([])
    s
    .expect(second.save_attempts, label="current save writes both")
    .to_equal([storage_key("scheme"), storage_key("moonbit")])
    s
    .expect(second.dirty, label="failed writes stay dirty")
    .to_equal(["scheme", "moonbit"])
    s.expect(second.storage_ok, label="not saved").to_be_false()
  })
}

///|
test "a language change closes the reset question" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (asked, _) = update(model, AskReset, emit)
  let (switched, _) = update(asked, Language("elm"), emit)
  @expect.expect(switched.reset_asking, label="closed").to_be_false()
}

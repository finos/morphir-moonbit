///|
extern "js" fn originals_test_mode() -> () -> Unit =
  #| () => {
  #|   const previous = globalThis.morphirWorkbench;
  #|   globalThis.morphirWorkbench = { ...previous, connected: true, mode: 'connected-originals' };
  #|   return () => { if (previous === undefined) delete globalThis.morphirWorkbench; else globalThis.morphirWorkbench = previous; };
  #| }

///|
test "originals opening preserves its owner when host authority is retained" {
  let base = lifecycle_model()
  let restore = originals_test_mode()
  defer restore()
  for unknown in [false, true] {
    let retained = {
      ..base,
      connected: true,
      host_submitting: !unknown,
      submission_unknown: unknown,
      busy: true,
    }
    let (after, _) = update(retained, OpenOriginals, quiet())
    assert_eq(after.document, retained.document)
    assert_true(after.originals == retained.originals)
    assert_true(after.status.contains("retained host execution"))
  }
}

///|
test "originals Started keeps its semantic owner and source pane choices" {
  let base = lifecycle_model()
  let restore = originals_test_mode()
  defer restore()
  let (opening, _) = update(
    { ..base, connected: true, },
    OpenOriginals,
    quiet(),
  )
  assert_true(opening.busy)
  assert_true(opening.document.opening() is Some(_))
  assert_eq(opening.document.document(), base.document.document())
  assert_eq(
    opening.document.current_revision(),
    base.document.current_revision(),
  )
  assert_eq(opening.pane, base.pane)
  assert_eq(opening.open_outputs, base.open_outputs)
}

///|
test "originals-only Close retires inventory without resetting source panes" {
  let base = lifecycle_model()
  let inventory = @document.OriginalInventory::from_connected(
    Map([("model.yaml", b"formatVersion: 4\r\n")]),
    ["empty"],
    NotReported,
  ) catch {
    _ => abort("inventory")
  }
  let (opening, attempt) = match @document.State::new().begin(Idle) {
    Started(state, attempt) => (state, attempt)
    _ => abort("begin")
  }
  let document = opening.finish_originals(attempt, inventory) catch {
    _ => abort("retain")
  }
  let retained = {
    ..base,
    document,
    pane: OutputOnly,
    open_outputs: ["old/generated.scala"],
    output: {
      "artifacts": [
        {
          "path": "old/generated.scala",
          "content": "object Previous",
          "binary": false,
        },
      ],
    },
  }
  let (closed, _) = update(retained, CloseModel, quiet())
  assert_eq(closed.document.original_inventory(), None)
  assert_eq(closed.document.document(), None)
  assert_eq(closed.pane, retained.pane)
  assert_eq(closed.open_outputs, retained.open_outputs)
  assert_eq(closed.output, retained.output)
  assert_eq(closed.language_projects, retained.language_projects)
  assert_eq(closed.worksheet_source, retained.worksheet_source)
  assert_eq(closed.status, "Model closed")
}

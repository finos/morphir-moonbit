///|
test "connected opening identity comes from the current domain attempt and workspace visit" {
  let (pending, attempt) = pending_connected_model()
  let model = { ..pending, mode: ConnectedOriginals, }
  guard connected_opening_identity(model, attempt) is Some(identity) else {
    abort("actual accepted opening has an identity")
  }
  assert_eq(Some(identity.visit), visit_of(model))
  assert_eq(identity.attempt, attempt)
  // Keeping an older immutable state does not retarget its identity when a
  // replacement attempt is accepted in the next state.
  let (replaced, replacement) = match model.document.begin(Idle) {
    Started(document, replacement) => ({ ..model, document, }, replacement)
    _ => abort("replacement opening")
  }
  assert_true(connected_opening_identity(replaced, attempt) is None)
  guard connected_opening_identity(replaced, replacement) is Some(next) else {
    abort("replacement identity")
  }
  assert_eq(next.visit, identity.visit)
  assert_true(next.attempt != identity.attempt)
  assert_eq(connected_opening_identity(model, attempt), Some(identity))
}

///|
test "connected identity never manufactures a visit mode or current attempt" {
  let (pending, attempt) = pending_connected_model()
  let model = { ..pending, mode: ConnectedOriginals, }
  assert_true(
    connected_opening_identity({ ..model, active: None, }, attempt) is None,
  )
  assert_true(
    connected_opening_identity({ ..model, mode: LocalRuntime, }, attempt)
    is None,
  )
  assert_true(
    connected_opening_identity(
      { ..model, document: @document.State::new(), },
      attempt,
    )
    is None,
  )
}

///|
test "Scheme documentation command declarations" {
  assert_true(
    docs_invocation(docs_command().parse(argv=["generate"], env=Map([]))) ==
    Generate,
  )
  assert_true(
    docs_invocation(docs_command().parse(argv=["check"], env=Map([]))) == Check,
  )
  for
    argv in [
      [],
      ["unknown"],
      ["check", "extra"],
      ["generate", "extra"],
      ["check", "--unknown"],
      ["generate", "--unknown"],
      ["--unknown"],
    ] {
    let refused = try {
      ignore(docs_command().parse(argv~, env=Map([])))
      false
    } catch {
      _ => true
    }
    assert_true(refused, msg=argv.join(" | "))
  }
}

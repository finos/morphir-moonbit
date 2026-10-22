///|
test "acceptance operands retain literal path boundaries" {
  for
    argv in [
      ["guest", "repository", "evidence"],
      ["guest with spaces", "répertoire/世界", "quote\"' $`; evidence"],
      ["-guest", "--repository", "--help"],
      ["", "", ""],
    ] {
    let args = acceptance_command().parse(argv~)
    assert_eq(args.values["guest"][0], argv[0])
    assert_eq(args.values["repository"][0], argv[1])
    assert_eq(args.values["evidence"][0], argv[2])
  }
}

///|
test "acceptance requires exactly three operands before effects" {
  for
    argv in [
      [],
      ["guest"],
      ["guest", "repository"],
      ["guest", "repository", "evidence", "extra"],
      ["--help"],
    ] {
    let rejected = try {
      ignore(acceptance_command().parse(argv~))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "acceptance delimiter introduces operands" {
  let args = acceptance_command().parse(argv=[
    "--", "--help", "-repository", "--evidence",
  ])
  assert_eq(args.values["guest"][0], "--help")
  assert_eq(args.values["repository"][0], "-repository")
  assert_eq(args.values["evidence"][0], "--evidence")
  let literal = acceptance_command().parse(argv=["--", "--", "repo", "out"])
  assert_eq(literal.values["guest"][0], "--")
}

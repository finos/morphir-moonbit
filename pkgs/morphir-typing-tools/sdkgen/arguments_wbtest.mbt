///|
test "SDK command declarations keep literal bootstrap operands" {
  for
    case in [
      (["generate"], Generate),
      (["check"], Check),
      (
        ["bootstrap", " λ bindings.json ", "out $;`.scm"],
        Bootstrap(" λ bindings.json ", "out $;`.scm"),
      ),
      (["bootstrap", "-bindings", "-out"], Bootstrap("-bindings", "-out")),
      (
        ["bootstrap", "--", "--bindings", "--out"],
        Bootstrap("--bindings", "--out"),
      ),
      (["bootstrap", "", ""], Bootstrap("", "")),
    ] {
    let (argv, expected) = case
    assert_true(
      sdk_invocation(sdk_command().parse(argv~, env=Map([]))) == expected,
    )
  }
}

///|
test "SDK command syntax refuses invalid arity before file operations" {
  for
    argv in [
      [],
      ["unknown"],
      ["check", "extra"],
      ["generate", "--unknown"],
      ["bootstrap"],
      ["bootstrap", "bindings"],
      ["bootstrap", "bindings", "out", "extra"],
      ["--unknown"],
    ] {
    let refused = try {
      ignore(sdk_command().parse(argv~, env=Map([])))
      false
    } catch {
      _ => true
    }
    assert_true(refused, msg=argv.join(" | "))
  }
}

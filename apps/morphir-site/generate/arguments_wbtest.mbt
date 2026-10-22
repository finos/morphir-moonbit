///|
test "generation defaults follow the selected root and repeated options keep the first" {
  let parse = fn(args) raise {
    generate_options(generate_command().parse(argv=args, env=Map([])))
  }
  assert_eq(parse([]), ("../..", "../../_site", false))
  assert_eq(parse(["--root", "root λ"]), ("root λ", "root λ/_site", false))
  assert_eq(
    parse([
      "--root", "one", "--root", "two", "--out", "first", "--out", "last", "--main",
    ]),
    ("one", "first", true),
  )
  assert_eq(
    parse(["--out", "'quotes' $;` λ", "--root", "-relative"]),
    ("-relative", "'quotes' $;` λ", false),
  )
  assert_eq(parse(["--root", "", "--out", ""]), ("", "", false))
}

///|
test "generation syntax rejects missing values and unknown operands before effects" {
  for args in [["--root"], ["--out"], ["--unknown"], ["extra"]] {
    assert_true(
      try {
        ignore(generate_command().parse(argv=args, env=Map([])))
        false
      } catch {
        _ => true
      },
    )
  }
}

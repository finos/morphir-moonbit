///|
test "check defaults preserve the deferred configuration base and first options" {
  let parse = fn(args) raise {
    check_options(check_command().parse(argv=args, env=Map([])))
  }
  assert_eq(parse([]), ("../../_site", "../../site/site.json", None))
  assert_eq(
    parse(["--base", ""]),
    ("../../_site", "../../site/site.json", Some("")),
  )
  assert_eq(
    parse([
      "--dir", "first", "--dir", "last", "--config", "config λ", "--base", "/first/",
      "--base", "/last/",
    ]),
    ("first", "config λ", Some("/first/")),
  )
  assert_eq(
    parse(["--dir", "-relative", "--config", "'quotes' $;` λ"]),
    ("-relative", "'quotes' $;` λ", None),
  )
}

///|
test "check syntax rejects missing values and unknown operands before reading files" {
  for args in [["--dir"], ["--config"], ["--base"], ["--unknown"], ["extra"]] {
    assert_true(
      try {
        ignore(check_command().parse(argv=args, env=Map([])))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "fault operands preserve literal paths and domain vocabulary" {
  for
    argv in [
      ["checkpoint", "malformed"],
      ["path with spaces/世界\"'", "unsupported-fault"],
      ["--help", "--unknown"],
      ["-checkpoint", "truncated"],
      ["", ""],
    ] {
    let args = fault_command().parse(argv~)
    assert_eq(args.values["checkpoint"][0], argv[0])
    assert_eq(args.values["fault"][0], argv[1])
  }
}

///|
test "fault parser rejects missing operands before file access" {
  for argv in [[], ["checkpoint"], ["--help"], ["--"]] {
    let rejected = try {
      ignore(fault_command().parse(argv~))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "fault parser preserves ignored trailing operands" {
  let args = fault_command().parse(argv=[
    "checkpoint", "malformed", "extra", "--help", "-x", "", "extra",
  ])
  assert_eq(args.values["checkpoint"], ["checkpoint"])
  assert_eq(args.values["fault"], ["malformed"])
  assert_eq(args.values["ignored"], ["extra", "--help", "-x", "", "extra"])
}

///|
test "fault delimiter introduces path operands" {
  let args = fault_command().parse(argv=["--", "--help", "malformed"])
  assert_eq(args.values["checkpoint"], ["--help"])
  assert_eq(args.values["fault"], ["malformed"])
  let literal = fault_command().parse(argv=["--", "--", "malformed"])
  assert_eq(literal.values["checkpoint"], ["--"])
}

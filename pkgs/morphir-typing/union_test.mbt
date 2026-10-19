///|
test "Union declared branches Fill then Check preserve signature and facts" {
  let union : @ir.Type = Union(tattrs(), [t_string(), t_int()])
  let file = library([
    (
      "m",
      [
        (
          "choose",
          ExpressionBody(
            [(nm("flag"), tr(BOOL, []))],
            union,
            IfThenElse(
              va(),
              Variable(va(), nm("flag")),
              v_str("yes"),
              fact_int("1"),
            ),
          ),
        ),
      ],
    ),
  ])
  let filled = fill(file)
  assert_eq(check(filled), filled)
  guard definition_in(filled, "m", "choose") is ExpressionBody(_, output, _) else {
    fail("definition lost")
  }
  assert_eq(output, union)
}

///|
test "Union semantic context expands visible aliases and keeps opaque identities" {
  let file = library_with_types([
    ("m", [("label", TypeAliasDefinition([], t_string()))], []),
  ])
  let context = @typing.TypeContext::from(file, deps())
  let alias = tr("acme/app:m#label", [])
  let union : @ir.Type = Union(tattrs(), [t_string(), alias])
  assert_eq(context.equivalent(union, t_string()), @typing.TypeRelation::Proven)
  assert_eq(
    context.assignable(t_int(), t_string()),
    @typing.TypeRelation::Refuted,
  )
  assert_eq(
    context.assignable(Union(tattrs(), [t_int(), t_string()]), t_string()),
    @typing.TypeRelation::Refuted,
  )
}

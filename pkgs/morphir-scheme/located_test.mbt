///|
test "located datums carry offsets of every sub-form" {
  let source = "; comment\n(val add\n  ((a number)) number)"
  let forms = @scheme.parse_program_located(source)
  assert_eq(forms.length(), 1)
  let top = forms[0]
  assert_eq(@scheme.line_column(source, top.start), (2, 1))
  assert_eq(top.children.length(), 4)
  assert_eq(top.children[1].datum, @scheme.Datum::Symbol("add"))
  assert_eq(@scheme.line_column(source, top.children[2].start), (3, 3))
  assert_eq(
    @scheme.line_column(source, top.children[2].children[0].children[1].start),
    (3, 7),
  )
}

///|
test "datum comments and quotes keep offsets aligned" {
  let source = "(a #;(skipped x) 'b c)"
  let top = @scheme.parse_program_located(source)[0]
  assert_eq(top.children.map(c => c.datum.to_source()), ["a", "(quote b)", "c"])
  assert_eq(top.children[2].start, 20)
  assert_eq(top.children[1].children[1].start, 18)
}

///|
test "vectors start at the hash sign and keep offsets aligned" {
  let source = "(#(a b) c)"
  let top = @scheme.parse_program_located(source)[0]
  assert_eq(top.children.length(), 2)
  assert_eq(top.children[0].start, 1)
  assert_eq(top.children[0].children.map(c => c.start), [3, 5])
  assert_eq(top.children[1].start, 8)
}

///|
test "the located and plain readers agree" {
  let source = "(package \"p\" (module m (val x () basics#int)))"
  assert_eq(
    @scheme.parse_program_located(source).map(l => l.datum),
    @scheme.parse_program(source),
  )
}

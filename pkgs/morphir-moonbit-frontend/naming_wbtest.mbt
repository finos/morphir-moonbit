///|
test "portable allocator escapes unsupported spellings without losing originals" {
  let source : @ir.SourceLocation = {
    start_line: 1,
    start_column: 7,
    end_line: 1,
    end_column: 12,
  }
  let allocated = allocate_source_names(
    [("readyλ", source), ("readyμ", source)],
    "example:main",
  )
  assert_true(allocated.names["readyλ"] != allocated.names["readyμ"])
  assert_true(
    allocated.names["readyλ"].to_canonical().has_prefix("ready-source-"),
  )
  assert_eq(allocated.warnings[0].locations.map(l => l.original), [
    "readyλ", "readyμ",
  ])
  let single = allocate_source_names([("readyλ", source)], "example:main")
  assert_eq(single.warnings[0].code, "moonbit_frontend.name_spelling_escape")
}

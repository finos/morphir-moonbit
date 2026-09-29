///|
// Oracle: Morphir.SDK.List at bc99af69a8b24d391311fae3822a87eafef3c334.
test "joins preserve Elm argument order and left traversal" {
  let left = from_array([1, 2, 3])
  let right = from_array([2, 2, 4])
  let result = inner_join(right, (a, b) => a == b, left)
  assert_eq(to_array(result), [(2, 2), (2, 2)])
  assert_eq(to_array(left_join(right, (a, b) => a == b, left)), [
    (1, None),
    (2, Some(2)),
    (2, Some(2)),
    (3, None),
  ])
  assert_eq(to_array(left), [1, 2, 3])
  assert_eq(to_array(right), [2, 2, 4])
}

///|
test "sort is stable and leaves the original list intact" {
  let values = from_array([(2, "a"), (1, "b"), (2, "c")])
  let sorted = sort_with(
    (a, b) => {
      let (a_key, _) = a
      let (b_key, _) = b
      @sdk.order(a_key - b_key)
    },
    values,
  )
  assert_eq(to_array(sorted), [(1, "b"), (2, "a"), (2, "c")])
  assert_eq(to_array(values), [(2, "a"), (1, "b"), (2, "c")])
}

///|
test "indexed and zipped maps follow Elm list truncation" {
  let one = from_array([1, 2, 3])
  let two = from_array([10, 20])
  assert_eq(to_array(indexed_map((i, n) => i + n, one)), [1, 3, 5])
  assert_eq(to_array(map2((a, b) => a + b, one, two)), [11, 22])
  assert_eq(to_array(map3((a, b, c) => a + b + c, one, two, one)), [12, 24])
  assert_eq(to_array(map4((a, b, c, d) => a + b + c + d, one, two, one, one)), [
    13, 26,
  ])
  assert_eq(
    to_array(
      map5((a, b, c, d, e) => a + b + c + d + e, one, two, one, one, one),
    ),
    [14, 28],
  )
}

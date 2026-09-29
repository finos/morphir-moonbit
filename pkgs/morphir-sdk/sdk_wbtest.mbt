///|
// Oracle: elm/core 1.0.5 Elm/Kernel/Utils.js comparison of JS strings.
test "string ordering follows UTF-16 lexical order" {
  assert_eq(string_order("ab", "b"), LT)
  assert_eq(string_order("😀", "\u{E000}"), LT)
  assert_eq(string_order("same", "same"), EQ)
  assert_eq(
    text_order(Text::from_string("😀"), Text::from_string("\u{E000}")),
    LT,
  )
  assert_eq(
    text_order(Text::from_units([0xD83D]), Text::from_units([0xDE00])),
    LT,
  )
}

///|
test "Text copies units and checks the MoonBit String boundary" {
  let input : Array[UInt16] = [0xD83D, 0xDE00]
  let value = Text::from_units(input)
  input[0] = 65
  assert_eq(value.to_units(), [0xD83D, 0xDE00])
  let output = value.to_units()
  output[1] = 66
  assert_eq(value.to_string(), "😀")
  let lone = Text::from_units([0xD83D])
  let refused = try {
    ignore(lone.to_string())
    false
  } catch {
    UnrepresentableText(_) => true
    _ => false
  }
  assert_true(refused)
}

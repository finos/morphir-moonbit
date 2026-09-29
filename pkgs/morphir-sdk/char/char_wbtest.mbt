///|
fn c(value : Char) -> @sdk.Character {
  @sdk.Character::from_char(value)
}

///|
// Oracle: elm/core 1.0.5 Char.elm and Elm/Kernel/Char.js.
test "ASCII classes and Unicode code points" {
  assert_true(is_upper(c('Z')))
  assert_true(is_lower(c('z')))
  assert_true(is_alpha_num(c('3')))
  assert_true(is_oct_digit(c('7')))
  assert_false(is_oct_digit(c('8')))
  assert_true(is_hex_digit(c('f')))
  assert_false(is_hex_digit(c('g')))
  assert_eq(to_upper(c('q')), c('Q'))
  assert_eq(to_lower(c('Q')), c('q'))
  assert_eq(to_upper(c('é')), c('É'))
  assert_eq(to_lower(c('É')), c('é'))
  assert_eq(to_upper(c('ß')).to_units(), [83, 83])
  assert_eq(@integer.to_string(to_code(c('😀'))), "128512")
  assert_eq(from_code(@integer.from_int(128512)), c('😀'))
}

///|
test "Char.fromCode keeps surrogates and replaces out of range codes" {
  assert_eq(from_code(@integer.from_int(0xD83D)).to_units(), [0xD83D])
  assert_eq(from_code(@integer.from_int(1114112)), c('�'))
}

///|
fn t(value : String) -> @sdk.Text {
  @sdk.Text::from_string(value)
}

///|
fn c(value : Char) -> @sdk.Character {
  @sdk.Character::from_char(value)
}

///|
// Oracle: elm/core 1.0.5 String.elm and Elm/Kernel/String.js.
test "UTF-16 offsets and scalar traversal" {
  assert_eq(length(t("a😀b")), 4)
  assert_eq(slice(1, 3, t("a😀b")), t("😀"))
  assert_eq(slice(-3, -1, t("a😀b")), t("😀"))
  assert_eq(@list.to_array(indexes(t("😀"), t("a😀b😀"))), [1, 4])
  assert_eq(@list.to_array(to_list(t("😀"))), [c('😀')])
  assert_eq(uncons(t("😀x")), Some((c('😀'), t("x"))))
  assert_eq(reverse(t("a😀b")), t("b😀a"))
  assert_eq(compare(t("ab"), t("b")), @sdk.LT)
}

///|
test "splitting, slicing, joining and padding preserve UTF-16" {
  assert_eq(@list.to_array(split(t(","), t("a,,b"))), [t("a"), t(""), t("b")])
  assert_eq(@list.to_array(split(t(""), t("abc"))), [t("a"), t("b"), t("c")])
  let halves = @list.to_array(split(t(""), t("😀")))
  assert_eq(halves.length(), 2)
  assert_eq(halves[0].to_units(), [0xD83D])
  assert_eq(halves[1].to_units(), [0xDE00])
  assert_eq(slice(1, 2, t("😀")).to_units(), [0xDE00])
  assert_eq(append(halves[0], halves[1]), t("😀"))
  assert_eq(@list.to_array(split(t(""), t(""))), [])
  assert_eq(replace(t("a"), t("x"), t("banana")), t("bxnxnx"))
  assert_eq(
    join(t("/"), @list.from_array([t("a"), t("b"), t("c")])),
    t("a/b/c"),
  )
  assert_eq(pad(5, c(' '), t("1")), t("  1  "))
  assert_eq(pad_left(5, c('.'), t("1")), t("....1"))
  assert_eq(drop_right(2, t("abcd")), t("ab"))
  assert_eq(@list.to_array(words(t("  one\t two\u{00A0}three "))), [
    t("one"),
    t("two"),
    t("three"),
  ])
  assert_eq(@list.to_array(words(t("   "))), [t("")])
  assert_eq(@list.to_array(lines(t("a\r\nb\rc\nd"))), [
    t("a"),
    t("b"),
    t("c"),
    t("d"),
  ])
  assert_eq(trim(t("\u{FEFF} hi \u{00A0}")), t("hi"))
}

///|
test "integer text remains exact" {
  let value = @integer.parse("1208925819614629174706179")
  assert_eq(to_int(from_int(value)), Some(value))
  assert_eq(to_int(t("1e3")), None)
  assert_eq(to_float(t("1e3")), Some(1000.0))
  assert_eq(to_float(t(" 1")), None)
  assert_eq(to_float(t("NaN")), None)
  assert_eq(to_float(t("inf")), None)
  assert_true(to_float(t("Infinity")).unwrap().is_inf())
  assert_eq(from_float(1.0 / 0.0), t("Infinity"))
  assert_eq(from_float(0.0 / 0.0), t("NaN"))
}

///|
// Oracle: ECMAScript default casing, Unicode 17.0, used by elm/core String.
test "Unicode casing includes expansions and final sigma" {
  assert_eq(to_upper(t("straße")), t("STRASSE"))
  assert_eq(to_upper(t("é😀")), t("É😀"))
  assert_eq(to_lower(t("ΟΣ")), t("ος"))
  assert_eq(to_lower(t("ΟΣΑ")), t("οσα"))
  assert_eq(to_lower(t("ΟΣ́")), t("ος́"))
  assert_eq(to_lower(t("İ")), t("i̇"))
}

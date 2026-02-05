// Tests for Name module - ported from morphir-elm Name tests
// Classic Name uses List[String] for Elm compatibility

// ============================================================================
// from_string tests (matching Elm behavior)
// ============================================================================

///|
test "from_string_parses_camelCase" {
  let name = Name::from_string("fooBar")
  inspect(name.to_snake_case(), content="foo_bar")
}

///|
test "from_string_parses_camelCase_with_underscores_and_numbers" {
  let name = Name::from_string("fooBar_baz123")
  inspect(name.to_snake_case(), content="foo_bar_baz_123")
}

///|
test "from_string_parses_valueInUSD_to_single_letters" {
  // Elm behavior: consecutive uppercase becomes single-letter words
  let name = Name::from_string("valueInUSD")
  let list = name.to_list()
  let arr = list.to_array()
  inspect(arr.length(), content="5")
  inspect(arr[0], content="value")
  inspect(arr[1], content="in")
  inspect(arr[2], content="u")
  inspect(arr[3], content="s")
  inspect(arr[4], content="d")
}

///|
test "from_string_parses_ValueInUSD" {
  let name = Name::from_string("ValueInUSD")
  inspect(name.to_snake_case(), content="value_in_USD")
}

///|
test "from_string_parses_value_in_USD" {
  let name = Name::from_string("value_in_USD")
  inspect(name.to_snake_case(), content="value_in_USD")
}

///|
test "from_string_parses_symbols_as_separators" {
  let name = Name::from_string("_-%")
  inspect(name.to_snake_case(), content="")
}

///|
test "from_string_parses_spaces" {
  let name = Name::from_string("foo bar baz")
  inspect(name.to_snake_case(), content="foo_bar_baz")
}

// ============================================================================
// to_title_case tests (Elm behavior)
// ============================================================================

///|
test "to_title_case_basic" {
  let name = Name::from_string("foo_bar_baz_123")
  inspect(name.to_title_case(), content="FooBarBaz123")
}

///|
test "to_title_case_with_abbreviation" {
  // Single-letter words are joined as uppercase abbreviation
  let name = Name::from_string("value_in_USD")
  inspect(name.to_title_case(), content="ValueInUSD")
}

///|
test "to_title_case_single_word" {
  let name = Name::from_string("hello")
  inspect(name.to_title_case(), content="Hello")
}

// ============================================================================
// to_camel_case tests (Elm behavior)
// ============================================================================

///|
test "to_camel_case_basic" {
  let name = Name::from_string("foo_bar_baz_123")
  inspect(name.to_camel_case(), content="fooBarBaz123")
}

///|
test "to_camel_case_with_abbreviation" {
  let name = Name::from_string("value_in_USD")
  inspect(name.to_camel_case(), content="valueInUSD")
}

///|
test "to_camel_case_single_word" {
  let name = Name::from_string("hello")
  inspect(name.to_camel_case(), content="hello")
}

///|
test "to_camel_case_starts_with_abbreviation" {
  // When name starts with single letters, they become uppercase
  let name = Name::from_string("USD_value")
  inspect(name.to_camel_case(), content="uSDValue")
}

// ============================================================================
// to_snake_case tests (Elm behavior)
// ============================================================================

///|
test "to_snake_case_basic" {
  let name = Name::from_string("fooBarBaz123")
  inspect(name.to_snake_case(), content="foo_bar_baz_123")
}

///|
test "to_snake_case_with_abbreviation" {
  let name = Name::from_string("valueInUSD")
  inspect(name.to_snake_case(), content="value_in_USD")
}

///|
test "to_snake_case_empty" {
  let name = Name::from_string("")
  inspect(name.to_snake_case(), content="")
}

// ============================================================================
// to_human_words tests (Elm behavior)
// ============================================================================

///|
test "to_human_words_joins_abbreviations" {
  let name = Name::from_string("value_in_USD")
  let words = name.to_human_words()
  let arr = words.to_array()
  inspect(arr.length(), content="3")
  inspect(arr[0], content="value")
  inspect(arr[1], content="in")
  inspect(arr[2], content="USD")
}

///|
test "to_human_words_title" {
  let name = Name::from_string("value_in_USD")
  let words = name.to_human_words_title()
  let arr = words.to_array()
  inspect(arr.length(), content="3")
  inspect(arr[0], content="Value")
  inspect(arr[1], content="in")
  inspect(arr[2], content="USD")
}

// ============================================================================
// from_list / to_list roundtrip tests
// ============================================================================

///|
test "from_list_to_list_roundtrip" {
  let words : @list.List[String] = @list.from_array(["foo", "bar", "baz"])
  let name = Name::from_list(words)
  let result = name.to_list()
  let arr = result.to_array()
  inspect(arr.length(), content="3")
  inspect(arr[0], content="foo")
  inspect(arr[1], content="bar")
  inspect(arr[2], content="baz")
}

///|
test "from_list_is_identity" {
  // from_list does not transform - it's the identity function like Elm
  let words : @list.List[String] = @list.from_array(["Value", "In", "USD"])
  let name = Name::from_list(words)
  let result = name.to_list()
  let arr = result.to_array()
  inspect(arr[0], content="Value")
  inspect(arr[1], content="In")
  inspect(arr[2], content="USD")
}

///|
test "from_list_single_letters_become_abbreviation_on_output" {
  // When input has single letters, they're joined on output
  let words : @list.List[String] = @list.from_array(["value", "in", "u", "s", "d"])
  let name = Name::from_list(words)
  inspect(name.to_snake_case(), content="value_in_USD")
}

// ============================================================================
// Edge cases
// ============================================================================

///|
test "handles_consecutive_uppercase" {
  // Elm splits consecutive uppercase into single letters
  let name = Name::from_string("XMLHTTPRequest")
  // X, M, L, H, T, T, P become single-letter words, then "request"
  // to_human_words joins them: "XMLHTTP", "request"
  inspect(name.to_snake_case(), content="XMLHTTP_request")
}

///|
test "handles_numbers_in_middle" {
  let name = Name::from_string("test123Value")
  inspect(name.to_snake_case(), content="test_123_value")
}

///|
test "handles_leading_number" {
  let name = Name::from_string("123test")
  inspect(name.to_snake_case(), content="123_test")
}

///|
test "handles_single_letter_name" {
  let name = Name::from_string("a")
  inspect(name.to_title_case(), content="A")
  inspect(name.to_camel_case(), content="a")
  inspect(name.to_snake_case(), content="a")
}

///|
test "handles_multiple_single_letters" {
  let name = Name::from_string("a_b_c")
  inspect(name.to_title_case(), content="ABC")
  inspect(name.to_camel_case(), content="aBC")
  inspect(name.to_snake_case(), content="ABC")
}

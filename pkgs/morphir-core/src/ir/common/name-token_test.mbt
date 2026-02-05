// Tests for NameToken

///|
test "Word_to_string_outputs_value_as_is" {
  let token = NameToken::word("hello")
  inspect(token, content="hello")
}

///|
test "Acronym_to_string_outputs_uppercase" {
  let token = NameToken::acronym("api")
  inspect(token, content="API")
}

///|
test "Word_lowercases_input" {
  let token = NameToken::word("camelCase")
  inspect(token, content="camelcase")
}

///|
test "Acronym_handles_mixed_case_input" {
  let token = NameToken::acronym("Http")
  inspect(token, content="HTTP")
}

// Tests for from_string

///|
test "from_string_creates_acronym_for_all_uppercase" {
  let token = NameToken::from_string("USD")
  inspect(token, content="USD")
  inspect(token.is_acronym(), content="true")
}

///|
test "from_string_creates_word_for_lowercase" {
  let token = NameToken::from_string("value")
  inspect(token, content="value")
  inspect(token.is_acronym(), content="false")
}

///|
test "from_string_creates_word_for_mixed_case" {
  let token = NameToken::from_string("Value")
  inspect(token, content="value")
  inspect(token.is_acronym(), content="false")
}

///|
test "from_string_creates_acronym_for_single_uppercase" {
  let token = NameToken::from_string("A")
  inspect(token, content="A")
  inspect(token.is_acronym(), content="true")
}

// Tests for value accessor

///|
test "value_returns_lowercase_for_word" {
  let token = NameToken::word("Hello")
  inspect(token.value(), content="hello")
}

///|
test "value_returns_lowercase_for_acronym" {
  let token = NameToken::acronym("USD")
  inspect(token.value(), content="usd")
}

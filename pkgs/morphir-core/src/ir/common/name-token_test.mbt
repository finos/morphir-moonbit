// Tests for NameToken

// ============================================================================
// Unchecked constructor tests (for valid inputs)
// ============================================================================

///|
test "Word_to_string_outputs_value_as_is" {
  let token = NameToken::word_unchecked("hello")
  inspect(token, content="hello")
}

///|
test "Acronym_to_string_outputs_uppercase" {
  let token = NameToken::acronym_unchecked("api")
  inspect(token, content="API")
}

///|
test "Word_lowercases_input" {
  let token = NameToken::word_unchecked("camelCase")
  inspect(token, content="camelcase")
}

///|
test "Acronym_handles_mixed_case_input" {
  let token = NameToken::acronym_unchecked("Http")
  inspect(token, content="HTTP")
}

// Tests for from_string_unchecked

///|
test "from_string_unchecked_creates_acronym_for_all_uppercase" {
  let token = NameToken::from_string_unchecked("USD")
  inspect(token, content="USD")
  inspect(token.is_acronym(), content="true")
}

///|
test "from_string_unchecked_creates_word_for_lowercase" {
  let token = NameToken::from_string_unchecked("value")
  inspect(token, content="value")
  inspect(token.is_acronym(), content="false")
}

///|
test "from_string_unchecked_creates_word_for_mixed_case" {
  let token = NameToken::from_string_unchecked("Value")
  inspect(token, content="value")
  inspect(token.is_acronym(), content="false")
}

///|
test "from_string_unchecked_creates_acronym_for_single_uppercase" {
  let token = NameToken::from_string_unchecked("A")
  inspect(token, content="A")
  inspect(token.is_acronym(), content="true")
}

// Tests for value accessor

///|
test "value_returns_lowercase_for_word" {
  let token = NameToken::word_unchecked("Hello")
  inspect(token.value(), content="hello")
}

///|
test "value_returns_lowercase_for_acronym" {
  let token = NameToken::acronym_unchecked("USD")
  inspect(token.value(), content="usd")
}

// ============================================================================
// Validated constructor tests
// ============================================================================

///|
test "word_returns_ok_for_valid_input" {
  let result = NameToken::word("hello")
  inspect(result is Ok(_), content="true")
  match result {
    Ok(token) => inspect(token, content="hello")
    Err(_) => fail("Expected Ok but got Err")
  }
}

///|
test "word_returns_err_for_empty_input" {
  let result = NameToken::word("")
  inspect(result is Err(_), content="true")
}

///|
test "word_accepts_alphanumeric_input" {
  let result = NameToken::word("foo123")
  inspect(result is Ok(_), content="true")
  match result {
    Ok(token) => inspect(token, content="foo123")
    Err(_) => fail("Expected Ok but got Err")
  }
}

///|
test "word_accepts_numeric_only_input" {
  let result = NameToken::word("123")
  inspect(result is Ok(_), content="true")
}

///|
test "word_returns_err_for_underscore" {
  let result = NameToken::word("foo_bar")
  inspect(result is Err(_), content="true")
}

///|
test "acronym_returns_ok_for_valid_input" {
  let result = NameToken::acronym("USD")
  inspect(result is Ok(_), content="true")
  match result {
    Ok(token) => inspect(token, content="USD")
    Err(_) => fail("Expected Ok but got Err")
  }
}

///|
test "acronym_returns_err_for_empty_input" {
  let result = NameToken::acronym("")
  inspect(result is Err(_), content="true")
}

///|
test "acronym_returns_err_for_special_char" {
  let result = NameToken::acronym("US$")
  inspect(result is Err(_), content="true")
}

///|
test "from_string_returns_ok_for_valid_word" {
  let result = NameToken::from_string("value")
  inspect(result is Ok(_), content="true")
  match result {
    Ok(token) => {
      inspect(token, content="value")
      inspect(token.is_acronym(), content="false")
    }
    Err(_) => fail("Expected Ok but got Err")
  }
}

///|
test "from_string_returns_ok_for_valid_acronym" {
  let result = NameToken::from_string("USD")
  inspect(result is Ok(_), content="true")
  match result {
    Ok(token) => {
      inspect(token, content="USD")
      inspect(token.is_acronym(), content="true")
    }
    Err(_) => fail("Expected Ok but got Err")
  }
}

///|
test "from_string_returns_err_for_invalid_input" {
  let result = NameToken::from_string("foo_bar")
  inspect(result is Err(_), content="true")
}

///|
test "from_string_accepts_alphanumeric" {
  let result = NameToken::from_string("test123")
  inspect(result is Ok(_), content="true")
}

// ============================================================================
// Error display tests
// ============================================================================

///|
test "NameTokenError_EmptyInput_shows_message" {
  match NameToken::word("") {
    Err(e) => inspect(e, content="NameToken cannot be empty")
    Ok(_) => fail("Expected Err")
  }
}

///|
test "NameTokenError_InvalidCharacter_shows_message" {
  match NameToken::word("foo$bar") {
    Err(e) => inspect(e, content="NameToken contains invalid character: '$'")
    Ok(_) => fail("Expected Err")
  }
}

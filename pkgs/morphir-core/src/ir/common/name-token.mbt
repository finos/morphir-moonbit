///| A NameToken represents a single component of a name identifier.
///| Words are regular words, Acronyms are all-uppercase abbreviations like USD, API.
///| Both are stored internally as lowercase strings.
///|
///| ## Immutability Contract
///| - Public APIs store owned `String` values.
///| - `StringView` inputs are accepted only by copying to `String`.
///|
///| ## Validation
///| NameTokens should contain only alphanumeric characters (a-z, A-Z, 0-9),
///| matching what the classic Name accepts in its from_string implementation.
///| Use the validated constructors (`word`, `acronym`, `from_string`) which return
///| `Result` types, or the `_unchecked` variants if you've already validated the input.
pub enum NameToken {
  Word(String)
  Acronym(String)
}

///| Error type for NameToken validation failures.
pub enum NameTokenError {
  EmptyInput
  InvalidCharacter(Char)
}

///| Show implementation for NameTokenError.
pub impl Show for NameTokenError with output(self, logger) {
  match self {
    EmptyInput => logger.write_string("NameToken cannot be empty")
    InvalidCharacter(c) =>
      logger.write_string("NameToken contains invalid character: '\{c}'")
  }
}

///| Validates that a string contains only alphanumeric characters (same as classic Name).
///| Returns Ok(()) if valid, or Err with the first invalid character found.
fn validate_token_chars(value : String) -> Result[Unit, NameTokenError] {
  if value.is_empty() {
    return Err(EmptyInput)
  }
  for c in value {
    if not(is_alphanumeric(c)) {
      return Err(InvalidCharacter(c))
    }
  }
  Ok(())
}

///| Returns true if the character is alphanumeric (a-z, A-Z, or 0-9).
fn is_alphanumeric(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///| Creates a Word token with validation. Returns an error if the input
///| is empty or contains non-alphanumeric characters.
///|
///| ```mbt check
///| test {
///|   let token = NameToken::word("Hello")
///|   inspect(token, content="Ok(hello)")
///|
///|   let alphanumeric = NameToken::word("test123")
///|   inspect(alphanumeric, content="Ok(test123)")
///|
///|   let empty = NameToken::word("")
///|   inspect(empty is Err(_), content="true")
///|
///|   let invalid = NameToken::word("foo_bar")
///|   inspect(invalid is Err(_), content="true")
///| }
///| ```
pub fn NameToken::word(value : String) -> Result[NameToken, NameTokenError] {
  match validate_token_chars(value) {
    Ok(_) => Ok(Word(value.to_lower()))
    Err(e) => Err(e)
  }
}

///| Creates a Word token from a `StringView` with validation.
pub fn NameToken::word_view(
  value : StringView
) -> Result[NameToken, NameTokenError] {
  NameToken::word(value.to_string())
}

///| Creates a Word token without validation. The value is stored as lowercase.
///| Use this only when you have already validated the input.
///|
///| ```mbt check
///| test {
///|   let token = NameToken::word_unchecked("Hello")
///|   inspect(token, content="hello")
///|   inspect(token.is_acronym(), content="false")
///| }
///| ```
pub fn NameToken::word_unchecked(value : String) -> NameToken {
  Word(value.to_lower())
}

///| Creates a Word token from a `StringView` without validation.
pub fn NameToken::word_view_unchecked(value : StringView) -> NameToken {
  NameToken::word_unchecked(value.to_string())
}

///| Creates an Acronym token with validation. Returns an error if the input
///| is empty or contains non-alphanumeric characters.
///| The value is stored as lowercase but displayed as uppercase.
///|
///| ```mbt check
///| test {
///|   let token = NameToken::acronym("usd")
///|   inspect(token, content="Ok(USD)")
///|
///|   let empty = NameToken::acronym("")
///|   inspect(empty is Err(_), content="true")
///|
///|   let invalid = NameToken::acronym("US$")
///|   inspect(invalid is Err(_), content="true")
///| }
///| ```
pub fn NameToken::acronym(value : String) -> Result[NameToken, NameTokenError] {
  match validate_token_chars(value) {
    Ok(_) => Ok(Acronym(value.to_lower()))
    Err(e) => Err(e)
  }
}

///| Creates an Acronym token from a `StringView` with validation.
pub fn NameToken::acronym_view(
  value : StringView
) -> Result[NameToken, NameTokenError] {
  NameToken::acronym(value.to_string())
}

///| Creates an Acronym token without validation.
///| The value is stored as lowercase but displayed as uppercase.
///| Use this only when you have already validated the input.
///|
///| ```mbt check
///| test {
///|   let token = NameToken::acronym_unchecked("usd")
///|   inspect(token, content="USD")
///|   inspect(token.is_acronym(), content="true")
///| }
///| ```
pub fn NameToken::acronym_unchecked(value : String) -> NameToken {
  Acronym(value.to_lower())
}

///| Creates an Acronym token from a `StringView` without validation.
pub fn NameToken::acronym_view_unchecked(value : StringView) -> NameToken {
  NameToken::acronym_unchecked(value.to_string())
}

///| Creates a NameToken from a string with validation. All-uppercase strings
///| become Acronyms, otherwise they become Words. Returns an error if the input
///| is empty or contains non-alphanumeric characters.
///|
///| ```mbt check
///| test {
///|   inspect(NameToken::from_string("USD"), content="Ok(USD)")
///|   inspect(NameToken::from_string("value"), content="Ok(value)")
///|   inspect(NameToken::from_string("test123"), content="Ok(test123)")
///|
///|   let invalid = NameToken::from_string("foo_bar")
///|   inspect(invalid is Err(_), content="true")
///| }
///| ```
pub fn NameToken::from_string(
  value : String
) -> Result[NameToken, NameTokenError] {
  match validate_token_chars(value) {
    Ok(_) =>
      if is_all_uppercase(value) {
        Ok(Acronym(value.to_lower()))
      } else {
        Ok(Word(value.to_lower()))
      }
    Err(e) => Err(e)
  }
}

///| Creates a NameToken from a `StringView` with validation.
pub fn NameToken::from_string_view(
  value : StringView
) -> Result[NameToken, NameTokenError] {
  NameToken::from_string(value.to_string())
}

///| Creates a NameToken from a string without validation. All-uppercase strings
///| become Acronyms, otherwise they become Words.
///| Use this only when you have already validated the input.
///|
///| ```mbt check
///| test {
///|   inspect(NameToken::from_string_unchecked("USD"), content="USD")
///|   inspect(NameToken::from_string_unchecked("USD").is_acronym(), content="true")
///|   inspect(NameToken::from_string_unchecked("value"), content="value")
///|   inspect(NameToken::from_string_unchecked("value").is_acronym(), content="false")
///| }
///| ```
pub fn NameToken::from_string_unchecked(value : String) -> NameToken {
  if is_all_uppercase(value) {
    Acronym(value.to_lower())
  } else {
    Word(value.to_lower())
  }
}

///| Creates a NameToken from a `StringView` without validation.
pub fn NameToken::from_string_view_unchecked(value : StringView) -> NameToken {
  NameToken::from_string_unchecked(value.to_string())
}

///|
fn is_all_uppercase(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  for c in s {
    if not(c >= 'A' && c <= 'Z') {
      return false
    }
  }
  true
}

///| Returns true if this token is an acronym.
///|
///| ```mbt check
///| test {
///|   inspect(NameToken::word_unchecked("hello").is_acronym(), content="false")
///|   inspect(NameToken::acronym_unchecked("usd").is_acronym(), content="true")
///| }
///| ```
pub fn NameToken::is_acronym(self : NameToken) -> Bool {
  match self {
    Acronym(_) => true
    Word(_) => false
  }
}

///| Returns the stored value (always lowercase).
///|
///| ```mbt check
///| test {
///|   inspect(NameToken::word_unchecked("Hello").value(), content="hello")
///|   inspect(NameToken::acronym_unchecked("USD").value(), content="usd")
///| }
///| ```
pub fn NameToken::value(self : NameToken) -> String {
  match self {
    Word(v) => v
    Acronym(v) => v
  }
}

///| Show implementation: Words display as lowercase, Acronyms as uppercase.
pub impl Show for NameToken with output(self, logger) {
  match self {
    Word(value) => logger.write_string(value)
    Acronym(value) => logger.write_string(value.to_upper())
  }
}

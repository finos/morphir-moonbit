///| A NameToken represents a single component of a name identifier.
///| Words are regular words, Acronyms are all-uppercase abbreviations like USD, API.
///| Both are stored internally as lowercase strings.
///|
///| ## Immutability Contract
///| - Public APIs store owned `String` values.
///| - `StringView` inputs are accepted only by copying to `String`.
pub enum NameToken {
  Word(String)
  Acronym(String)
}

///| Creates a Word token. The value is stored as lowercase.
///|
///| ```mbt check
///| test {
///|   let token = NameToken::word("Hello")
///|   inspect(token, content="hello")
///|   inspect(token.is_acronym(), content="false")
///| }
///| ```
pub fn NameToken::word(value : String) -> NameToken {
  Word(value.to_lower())
}

///| Creates a Word token from a `StringView`.
pub fn NameToken::word_view(value : StringView) -> NameToken {
  NameToken::word(value.to_string())
}

///| Creates an Acronym token. The value is stored as lowercase but displayed as uppercase.
///|
///| ```mbt check
///| test {
///|   let token = NameToken::acronym("usd")
///|   inspect(token, content="USD")
///|   inspect(token.is_acronym(), content="true")
///| }
///| ```
pub fn NameToken::acronym(value : String) -> NameToken {
  Acronym(value.to_lower())
}

///| Creates an Acronym token from a `StringView`.
pub fn NameToken::acronym_view(value : StringView) -> NameToken {
  NameToken::acronym(value.to_string())
}

///| Creates a NameToken from a string. All-uppercase strings become Acronyms,
///| otherwise they become Words.
///|
///| ```mbt check
///| test {
///|   inspect(NameToken::from_string("USD"), content="USD")
///|   inspect(NameToken::from_string("USD").is_acronym(), content="true")
///|   inspect(NameToken::from_string("value"), content="value")
///|   inspect(NameToken::from_string("value").is_acronym(), content="false")
///| }
///| ```
pub fn NameToken::from_string(value : String) -> NameToken {
  if is_all_uppercase(value) {
    Acronym(value.to_lower())
  } else {
    Word(value.to_lower())
  }
}

///| Creates a NameToken from a `StringView` by copying to `String`.
pub fn NameToken::from_string_view(value : StringView) -> NameToken {
  NameToken::from_string(value.to_string())
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
///|   inspect(NameToken::word("hello").is_acronym(), content="false")
///|   inspect(NameToken::acronym("usd").is_acronym(), content="true")
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
///|   inspect(NameToken::word("Hello").value(), content="hello")
///|   inspect(NameToken::acronym("USD").value(), content="usd")
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

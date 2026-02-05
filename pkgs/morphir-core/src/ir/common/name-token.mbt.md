# NameToken

`NameToken` represents a single component of a name identifier, distinguishing between
regular words and acronyms. This is used by the v4 Name implementation to provide
richer type information than the classic `List[String]` approach.

## Token Types

There are two kinds of tokens:

- **Word**: Regular words like "value", "foo", "bar"
- **Acronym**: All-uppercase abbreviations like "USD", "API", "HTTP"

Both are stored internally as lowercase strings, but display differently:

```mbt check
test {
  let word = NameToken::word_unchecked("Hello")
  let acronym = NameToken::acronym_unchecked("usd")

  // Words display as lowercase
  inspect(word, content="hello")

  // Acronyms display as uppercase
  inspect(acronym, content="USD")
}
```

## Creating Tokens

### Validated Construction (Recommended)

Use `word` or `acronym` for safe construction that validates input:

```mbt check
test {
  // Valid inputs return Ok
  let w = NameToken::word("value")
  inspect(w is Ok(_), content="true")

  // Invalid inputs (special characters) return Err
  let invalid = NameToken::word("foo_bar")
  inspect(invalid is Err(_), content="true")

  // Empty inputs return Err
  let empty = NameToken::acronym("")
  inspect(empty is Err(_), content="true")
}
```

### Unchecked Construction

Use `word_unchecked` or `acronym_unchecked` when you've already validated input:

```mbt check
test {
  let w = NameToken::word_unchecked("value")
  let a = NameToken::acronym_unchecked("api")

  inspect(w.is_acronym(), content="false")
  inspect(a.is_acronym(), content="true")
}
```

### Automatic Detection

Use `from_string` to auto-detect based on case (with validation):

```mbt check
test {
  // All-uppercase becomes Acronym
  let usd = NameToken::from_string("USD")
  match usd {
    Ok(token) => inspect(token.is_acronym(), content="true")
    Err(_) => fail("Expected Ok")
  }

  // Mixed or lowercase becomes Word
  let value = NameToken::from_string("Value")
  match value {
    Ok(token) => inspect(token.is_acronym(), content="false")
    Err(_) => fail("Expected Ok")
  }
}
```

Or use `from_string_unchecked` for pre-validated input:

```mbt check
test {
  inspect(NameToken::from_string_unchecked("USD").is_acronym(), content="true")
  inspect(NameToken::from_string_unchecked("value").is_acronym(), content="false")
}
```

## Validation Rules

NameTokens must contain only alphanumeric characters (a-z, A-Z, 0-9), matching
what the classic Name accepts in its `from_string` implementation:

```mbt check
test {
  // Alphanumeric is valid
  inspect(NameToken::word("test123") is Ok(_), content="true")
  inspect(NameToken::word("123") is Ok(_), content="true")

  // Underscores are invalid (separators, not token content)
  inspect(NameToken::word("foo_bar") is Err(_), content="true")

  // Special characters are invalid
  inspect(NameToken::acronym("US$") is Err(_), content="true")

  // Empty strings are invalid
  inspect(NameToken::word("") is Err(_), content="true")
}
```

## Accessing Values

The `value` method returns the stored lowercase string:

```mbt check
test {
  let word = NameToken::word_unchecked("Hello")
  let acronym = NameToken::acronym_unchecked("USD")

  // Both return lowercase
  inspect(word.value(), content="hello")
  inspect(acronym.value(), content="usd")
}
```

## Immutability Contract

- Public APIs store owned `String` values
- `StringView` inputs are accepted via `*_view` variants but copied to `String`
- The stored value is always lowercase

```mbt check
test {
  // Input case is normalized to lowercase
  let token = NameToken::word_unchecked("MixedCase")
  inspect(token.value(), content="mixedcase")
}
```

## Use Cases

NameToken is designed for the v4 Name type where we want to preserve the
semantic distinction between words and acronyms at the type level, rather
than inferring it from string length as the classic implementation does.

The validated constructors follow the "parse, don't verify" principle:
invalid inputs are rejected at construction time, ensuring that any
`NameToken` value is guaranteed to contain only valid characters.

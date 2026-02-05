# Name

`Name` is an abstraction of human-readable identifiers made up of words. This abstraction
allows us to use the same identifiers across various naming conventions used by different
frontend and backend languages Morphir integrates with.

This implementation matches the Elm `Morphir.IR.Name` module.

## Basic Usage

Names can be created from strings using various naming conventions:

```mbt check
test {
  // camelCase
  inspect(Name::from_string("fooBar").to_snake_case(), content="foo_bar")

  // TitleCase
  inspect(Name::from_string("FooBar").to_snake_case(), content="foo_bar")

  // snake_case
  inspect(Name::from_string("foo_bar").to_camel_case(), content="fooBar")
}
```

## Output Formats

Names can be converted to different naming conventions:

```mbt check
test {
  let name = Name::from_string("foo_bar_baz")

  inspect(name.to_title_case(), content="FooBarBaz")
  inspect(name.to_camel_case(), content="fooBarBaz")
  inspect(name.to_snake_case(), content="foo_bar_baz")
}
```

## Abbreviations

We frequently use abbreviations in a business context to be more concise.
From a naming perspective, abbreviations are challenging because they behave
differently than regular words.

In this module, consecutive single-letter words are treated as abbreviations
and joined together as uppercase when outputting:

```mbt check
test {
  // "USD" becomes three single-letter words: "u", "s", "d"
  let name = Name::from_string("valueInUSD")

  // Single letters are joined as uppercase abbreviations
  inspect(name.to_title_case(), content="ValueInUSD")
  inspect(name.to_camel_case(), content="valueInUSD")
  inspect(name.to_snake_case(), content="value_in_USD")
}
```

The `to_human_words` function shows how abbreviations are handled:

```mbt check
test {
  let name = Name::from_string("value_in_USD")
  let words = name.to_human_words().to_array()

  // Three words: "value", "in", and the abbreviation "USD"
  inspect(words.length(), content="3")
  inspect(words[0], content="value")
  inspect(words[1], content="in")
  inspect(words[2], content="USD")
}
```

## Parsing Algorithm

The parsing algorithm uses the pattern `[a-zA-Z][a-z]*|[0-9]+`:

- A letter followed by zero or more lowercase letters forms a word
- Consecutive uppercase letters become separate single-letter words
- Consecutive digits form a number word

```mbt check
test {
  // Mixed conventions work
  inspect(Name::from_string("XMLHTTPRequest").to_snake_case(), content="XMLHTTP_request")

  // Numbers are preserved
  inspect(Name::from_string("test123Value").to_snake_case(), content="test_123_value")
  inspect(Name::from_string("123test").to_snake_case(), content="123_test")
}
```

## List Conversion

Names can be created from and converted to lists:

```mbt check
test {
  // from_list is the identity function (doesn't transform)
  let words = @list.from_array(["value", "in", "u", "s", "d"])
  let name = Name::from_list(words)

  // Single-letter words become abbreviations on output
  inspect(name.to_snake_case(), content="value_in_USD")

  // to_list returns the raw words
  let list = name.to_list().to_array()
  inspect(list[2], content="u")
  inspect(list[3], content="s")
  inspect(list[4], content="d")
}
```

## Immutability Contract

- Public APIs return immutable `@list.List[String]` and `String` values
- `StringView` inputs are accepted via `from_string_view` but copied to owned `String`
- Internal implementations may use mutable structures for performance

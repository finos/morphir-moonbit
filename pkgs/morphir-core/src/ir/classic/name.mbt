///| A Name is a list of words representing a human-readable identifier.
///| This abstraction allows using the same identifiers across various naming
///| conventions used by different frontend and backend languages.
///|
///| This matches the Elm implementation where Name = List String.
///| `from_list` preserves case; `from_string` lowercases parsed words.
///| Single-letter words are treated as parts of abbreviations when outputting.
///|
///| ## Immutability Contract
///| - Public APIs return immutable `@list.List[String]` and `String` values.
///| - `StringView` or `Array`/`ArrayView` may be used internally for performance
///|   but are never stored or returned from public APIs.
pub struct Name(@list.List[String])

///| Creates a Name from a list of strings.
///| This is the identity function - words are stored as-is.
///| Callers should pass lowercase words (as produced by `from_string`).
///|
///| ```mbt check
///| test {
///|   let words = @list.from_array(["foo", "bar", "baz"])
///|   let name = Name::from_list(words)
///|   inspect(name.to_snake_case(), content="foo_bar_baz")
///| }
///| ```
pub fn Name::from_list(words : @list.List[String]) -> Name {
  Name(words)
}

///| Converts a Name to a list of lowercase strings.
///|
///| ```mbt check
///| test {
///|   let name = Name::from_string("fooBar")
///|   let list = name.to_list().to_array()
///|   inspect(list[0], content="foo")
///|   inspect(list[1], content="bar")
///| }
///| ```
pub fn Name::to_list(self : Name) -> @list.List[String] {
  let Name(words) = self
  words
}

///| Parses a string into a Name by splitting it into words.
///| Handles camelCase, TitleCase, snake_case, and mixed conventions.
///| The algorithm splits on uppercase letters and non-alphanumeric characters.
///|
///| ```mbt check
///| test {
///|   inspect(Name::from_string("fooBar_baz").to_snake_case(), content="foo_bar_baz")
///|   inspect(Name::from_string("valueInUSD").to_snake_case(), content="value_in_USD")
///|   inspect(Name::from_string("ValueInUSD").to_snake_case(), content="value_in_USD")
///|   inspect(Name::from_string("value_in_USD").to_snake_case(), content="value_in_USD")
///| }
///| ```
pub fn Name::from_string(input : String) -> Name {
  if input.is_empty() {
    return Name(@list.from_array([]))
  }
  let words = parse_words(input)
  Name(words)
}

///| Creates a Name from a `StringView` by copying to `String`.
///| This keeps the public contract owned and immutable.
pub fn Name::from_string_view(input : StringView) -> Name {
  Name::from_string(input.to_string())
}

///| Internal: Parse a string into a list of lowercase words.
///| Uses the Elm algorithm: ([a-zA-Z][a-z]*|[0-9]+) pattern.
///| Each uppercase letter followed by lowercase letters is one word.
///| Consecutive uppercase letters become separate single-letter words.
fn parse_words(input : String) -> @list.List[String] {
  find_words(input)
}

///| Recursively find all word matches using lexmatch.
///| Pattern: [a-zA-Z][a-z]* | [0-9]+
fn find_words(input : String) -> @list.List[String] {
  if input.is_empty() {
    return @list.from_array([])
  }
  lexmatch input {
    (before, "[a-zA-Z][a-z]*" as word, after) =>
      // Numbers before this word + this word + words after
      find_numbers(before.to_string())
        .concat(@list.from_array([word.to_string().to_lower()]))
        .concat(find_words(after.to_string()))
    _ =>
      // No word found, extract any remaining numbers
      find_numbers(input)
  }
}

///| Extract numbers from a string that contains no letters.
fn find_numbers(input : String) -> @list.List[String] {
  if input.is_empty() {
    return @list.from_array([])
  }
  lexmatch input {
    (_, "[0-9]+" as num, after) =>
      @list.from_array([num.to_string()]).concat(find_numbers(after.to_string()))
    _ => @list.from_array([])
  }
}

///| Capitalizes the first character of a string.
fn capitalize(s : String) -> String {
  if s.is_empty() {
    return s
  }
  let chars = s.to_array()
  let first = chars[0]
  let upper_first = if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).unsafe_to_char()
  } else {
    first
  }
  let result = StringBuilder::new()
  result.write_char(upper_first)
  for i = 1; i < chars.length(); i = i + 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///| Converts a Name to TitleCase.
///| Consecutive single-letter words are joined as uppercase abbreviations.
///|
///| ```mbt check
///| test {
///|   inspect(Name::from_string("foo_bar_baz_123").to_title_case(), content="FooBarBaz123")
///|   inspect(Name::from_string("value_in_USD").to_title_case(), content="ValueInUSD")
///| }
///| ```
pub fn Name::to_title_case(self : Name) -> String {
  let Name(words) = self
  let result = StringBuilder::new()
  let words_arr = words.to_array()
  let len = words_arr.length()
  let mut i = 0

  while i < len {
    let word = words_arr[i]
    if word.length() == 1 {
      // Start of potential abbreviation - collect consecutive single letters
      let abbrev = StringBuilder::new()
      while i < len && words_arr[i].length() == 1 {
        abbrev.write_string(words_arr[i].to_upper())
        i += 1
      }
      result.write_string(abbrev.to_string())
    } else {
      result.write_string(capitalize(word))
      i += 1
    }
  }

  result.to_string()
}

///| Converts a Name to camelCase.
///| Like TitleCase but first word stays lowercase (unless it's part of an abbreviation).
///|
///| ```mbt check
///| test {
///|   inspect(Name::from_string("foo_bar_baz_123").to_camel_case(), content="fooBarBaz123")
///|   inspect(Name::from_string("value_in_USD").to_camel_case(), content="valueInUSD")
///| }
///| ```
pub fn Name::to_camel_case(self : Name) -> String {
  let Name(words) = self
  match words.head() {
    None => ""
    Some(head) => {
      let result = StringBuilder::new()
      result.write_string(head)
      let tail = words.unsafe_tail()
      let words_arr = tail.to_array()
      let len = words_arr.length()
      let mut i = 0

      while i < len {
        let word = words_arr[i]
        if word.length() == 1 {
          // Start of potential abbreviation - collect consecutive single letters
          let abbrev = StringBuilder::new()
          while i < len && words_arr[i].length() == 1 {
            abbrev.write_string(words_arr[i].to_upper())
            i += 1
          }
          result.write_string(abbrev.to_string())
        } else {
          result.write_string(capitalize(word))
          i += 1
        }
      }

      result.to_string()
    }
  }
}

///| Converts a Name to snake_case.
///| Uses human words, joined with underscores.
///|
///| ```mbt check
///| test {
///|   inspect(Name::from_string("fooBarBaz123").to_snake_case(), content="foo_bar_baz_123")
///|   inspect(Name::from_string("valueInUSD").to_snake_case(), content="value_in_USD")
///| }
///| ```
pub fn Name::to_snake_case(self : Name) -> String {
  let words = self.to_human_words()
  let result = StringBuilder::new()
  let mut first = true
  words.each(fn(word) {
    if not(first) {
      result.write_char('_')
    }
    result.write_string(word)
    first = false
  })
  result.to_string()
}

///| Converts a Name to a list of human-readable strings.
///| Consecutive single-letter words are joined as uppercase abbreviations.
///|
///| ```mbt check
///| test {
///|   let words = Name::from_string("value_in_USD").to_human_words().to_array()
///|   inspect(words[0], content="value")
///|   inspect(words[1], content="in")
///|   inspect(words[2], content="USD")
///| }
///| ```
pub fn Name::to_human_words(self : Name) -> @list.List[String] {
  let Name(words) = self
  if words.length() == 1 {
    match words.head() {
      Some(word) => if word.length() == 1 { words } else { join_abbreviations(words) }
      None => words
    }
  } else {
    join_abbreviations(words)
  }
}

fn join_abbreviations(words : @list.List[String]) -> @list.List[String] {
  let result : Array[String] = []
  let words_arr = words.to_array()
  let len = words_arr.length()
  let mut i = 0

  while i < len {
    let word = words_arr[i]
    if word.length() == 1 {
      // Start of potential abbreviation - collect consecutive single letters
      let abbrev = StringBuilder::new()
      while i < len && words_arr[i].length() == 1 {
        abbrev.write_string(words_arr[i].to_upper())
        i += 1
      }
      result.push(abbrev.to_string())
    } else {
      result.push(word)
      i += 1
    }
  }

  @list.from_array(result)
}

///| Converts a Name to a list of human-readable strings with the first word capitalized.
///|
///| ```mbt check
///| test {
///|   let words = Name::from_string("value_in_USD").to_human_words_title().to_array()
///|   inspect(words[0], content="Value")
///|   inspect(words[1], content="in")
///|   inspect(words[2], content="USD")
///| }
///| ```
pub fn Name::to_human_words_title(self : Name) -> @list.List[String] {
  let words = self.to_human_words()
  match words.head() {
    Some(first) => @list.from_array([capitalize(first)]).concat(words.unsafe_tail())
    None => @list.from_array([])
  }
}

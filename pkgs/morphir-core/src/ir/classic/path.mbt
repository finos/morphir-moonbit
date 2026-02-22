///| A Path is a list of names that represents a path in the tree.

///| It's used at various places in the IR to identify types and values.

///|

///| This matches the Elm implementation where Path = List Name.

///| Unlike Elm's type alias, this is a proper struct tuple providing

///| type safety while maintaining the same semantics.

///|

///| ## Examples

///| ```mbt check

///| test {

///|   let path = Path::from_list(

///|     @list.from_array([Name::from_string("foo"), Name::from_string("bar")])

///|   )

///|   inspect(path.to_string(Name::to_title_case, "."), content="Foo.Bar")

///| }

///|
/// ```
pub struct Path(@list.List[Name])

///| Creates a Path from a list of Names.

///| This is the primary constructor for Path.

///|

///| ```mbt check

///| test {

///|   let names = @list.from_array([Name::from_string("foo"), Name::from_string("bar")])

///|   let path = Path::from_list(names)

///|   inspect(path.to_list().length(), content="2")

///| }

///|
/// ```
pub fn Path::from_list(names : @list.List[Name]) -> Path {
  Path(names)
}

///| Converts a Path to a list of Names.

///|

///| ```mbt check

///| test {

///|   let path = Path::from_string("foo.bar")

///|   let names = path.to_list()

///|   inspect(names.length(), content="2")

///| }

///|
/// ```
pub fn Path::to_list(self : Path) -> @list.List[Name] {
  let Path(names) = self
  names
}

///| Translates a string into a path by splitting it into names along special characters.

///| The algorithm treats any non-word characters that are not spaces as a path separator.

///|

///| ```mbt check

///| test {

///|   let path = Path::from_string("fooBar.Baz")

///|   inspect(path.to_string(Name::to_title_case, "."), content="FooBar.Baz")

///| }

///| ```

///|

///| ```mbt check

///| test {

///|   let path = Path::from_string("foo bar/baz")

///|   inspect(path.to_string(Name::to_snake_case, "/"), content="foo_bar/baz")

///| }

///|
/// ```
pub fn Path::from_string(input : String) -> Path {
  if input.is_empty() {
    return Path(@list.from_array([]))
  }
  // Split on non-word, non-space characters (., /, :, etc.)
  let segments = split_path(input)
  let names = segments.map(fn(s) { Name::from_string(s) })
  Path(names)
}

///| Internal: Split a string on path separators (non-word, non-space characters).

///|
/// Separators are characters that are not alphanumeric, underscore, or space.
fn split_path(input : String) -> @list.List[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  let chars = input.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if is_path_separator(c) {
      // Found a separator - save current segment if non-empty
      let segment = current.to_string()
      if not(segment.is_empty()) {
        result.push(segment)
      }
      current.reset()
    } else {
      current.write_char(c)
    }
  }
  // Don't forget the last segment
  let last = current.to_string()
  if not(last.is_empty()) {
    result.push(last)
  }
  @list.from_array(result)
}

///| Internal: Check if a character is a path separator.

///|
/// Path separators are non-word, non-space characters (., /, :, -, etc.)
fn is_path_separator(c : Char) -> Bool {
  // Word characters: a-z, A-Z, 0-9, _
  // Space is also not a separator
  not(is_word_char(c) || c == ' ')
}

///|
/// Internal: Check if a character is a word character (alphanumeric or underscore).
fn is_word_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///| Turn a path into a string using the specified naming convention and separator.

///|

///| ```mbt check

///| test {

///|   let path = Path::from_list(@list.from_array([

///|     Name::from_list(@list.from_array(["foo", "bar"])),

///|     Name::from_list(@list.from_array(["baz"]))

///|   ]))

///|   inspect(path.to_string(Name::to_title_case, "."), content="FooBar.Baz")

///| }

///| ```

///|

///| ```mbt check

///| test {

///|   let path = Path::from_list(@list.from_array([

///|     Name::from_list(@list.from_array(["foo", "bar"])),

///|     Name::from_list(@list.from_array(["baz"]))

///|   ]))

///|   inspect(path.to_string(Name::to_snake_case, "/"), content="foo_bar/baz")

///| }

///|
/// ```
pub fn Path::to_string(
  self : Path,
  name_to_string : (Name) -> String,
  sep : String,
) -> String {
  let Path(names) = self
  let result = StringBuilder::new()
  let mut first = true
  names.each(fn(name) {
    if not(first) {
      result.write_string(sep)
    }
    result.write_string(name_to_string(name))
    first = false
  })
  result.to_string()
}

///| Checks if a path is a prefix of another path.

///|

///| ```mbt check

///| test {

///|   let path = Path::from_string("foo.bar")

///|   let prefix = Path::from_string("foo")

///|   inspect(path.is_prefix_of(prefix), content="true")

///| }

///| ```

///|

///| ```mbt check

///| test {

///|   let path = Path::from_string("foo")

///|   let prefix = Path::from_string("foo.bar")

///|   inspect(path.is_prefix_of(prefix), content="false")

///| }

///| ```

///|

///| ```mbt check

///| test {

///|   let path = Path::from_string("foo.bar")

///|   let prefix = Path::from_string("foo.bar")

///|   inspect(path.is_prefix_of(prefix), content="true")

///| }

///|
/// ```
pub fn Path::is_prefix_of(self : Path, prefix : Path) -> Bool {
  let Path(path_names) = self
  let Path(prefix_names) = prefix
  is_prefix_of_helper(path_names, prefix_names)
}

///|
/// Internal helper for prefix checking.
fn is_prefix_of_helper(
  path : @list.List[Name],
  prefix : @list.List[Name],
) -> Bool {
  match (prefix.head(), path.head()) {
    // Empty prefix is a prefix of any path
    (None, _) => true
    // Non-empty prefix can't be a prefix of empty path
    (Some(_), None) => false
    // Compare heads and recurse
    (Some(prefix_head), Some(path_head)) =>
      if names_equal(prefix_head, path_head) {
        is_prefix_of_helper(path.unsafe_tail(), prefix.unsafe_tail())
      } else {
        false
      }
  }
}

///|
/// Internal: Compare two names for equality by comparing their word lists.
fn names_equal(a : Name, b : Name) -> Bool {
  let a_words = a.to_list()
  let b_words = b.to_list()
  if a_words.length() != b_words.length() {
    return false
  }
  lists_equal(a_words, b_words)
}

///|
/// Internal: Compare two string lists for equality.
fn lists_equal(a : @list.List[String], b : @list.List[String]) -> Bool {
  match (a.head(), b.head()) {
    (None, None) => true
    (Some(ah), Some(bh)) =>
      if ah == bh {
        lists_equal(a.unsafe_tail(), b.unsafe_tail())
      } else {
        false
      }
    _ => false
  }
}

///| Creates an empty Path.

///|

///| ```mbt check

///| test {

///|   let path = Path::empty()

///|   inspect(path.to_list().length(), content="0")

///| }

///|
/// ```
pub fn Path::empty() -> Path {
  Path(@list.from_array([]))
}

///| Checks if a Path is empty.

///|

///| ```mbt check

///| test {

///|   inspect(Path::empty().is_empty(), content="true")

///|   inspect(Path::from_string("foo").is_empty(), content="false")

///| }

///|
/// ```
pub fn Path::is_empty(self : Path) -> Bool {
  let Path(names) = self
  names.length() == 0
}

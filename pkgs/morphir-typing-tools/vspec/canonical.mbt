///|
/// Split an Elm name into lower-case words.
///
/// Words start at a letter and continue over lower-case letters, or are runs of digits. Other
/// characters, such as `-`, only separate words.
fn words_of(text : String) -> Array[String] {
  let words : Array[String] = []
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if is_letter(c) {
      let start = i
      i += 1
      while i < chars.length() && is_lower(chars[i]) {
        i += 1
      }
      words.push(String::from_array(chars[start:i]).to_lower())
    } else if is_digit(c) {
      let start = i
      while i < chars.length() && is_digit(chars[i]) {
        i += 1
      }
      words.push(String::from_array(chars[start:i]))
    } else {
      i += 1
    }
  }
  words
}

///|
fn is_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_lower(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// The name of an Elm name as a semantic name.
pub fn elm_name(text : String) -> @ir.Name {
  @ir.Name::from_words(words_of(text))
}

///|
/// The canonical form of an Elm name, as migration decodes it from morphir-elm IR.
///
/// The name splits at camel-case boundaries and digit runs, and every word is lower case. Then
/// `Name::from_words` turns a run of two or more single letters into one upper-case initialism.
pub fn canonical_name(elm_name : String) -> String {
  @ir.Name::from_words(words_of(elm_name)).to_canonical()
}

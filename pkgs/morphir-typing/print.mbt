///|
/// An IR type in Elm notation, for messages and tests. A reference shows its local name, so
/// `morphir/SDK:list#list` is `List`. A variable shows in camel case, so `comparable-a` is `comparableA`.
fn elm_text(t : @ir.Type) -> String {
  match t {
    Function(_, input, output) => {
      let left = match input {
        Function(_, _, _) => "(" + elm_text(input) + ")"
        _ => elm_text(input)
      }
      left + " -> " + elm_text(output)
    }
    Reference(_, name, args) =>
      [upper_camel(name.local_name), ..args.map(elm_argument)].join(" ")
    _ => elm_argument(t)
  }
}

///|
/// A type in an argument position: a function or an applied reference takes parentheses.
fn elm_argument(t : @ir.Type) -> String {
  match t {
    Variable(_, name) => lower_camel(name)
    Reference(_, name, []) => upper_camel(name.local_name)
    Reference(_, _, _) | Function(_, _, _) => "(" + elm_text(t) + ")"
    Tuple(_, items) => "( " + items.map(elm_text).join(", ") + " )"
    Unit(_) => "()"
    Record(_, fields) if fields.is_empty() => "{}"
    Record(_, fields) => "{ " + elm_fields(fields) + " }"
    ExtensibleRecord(_, row, fields) =>
      "{ " + lower_camel(row) + " | " + elm_fields(fields) + " }"
  }
}

///|
fn elm_fields(fields : Map[@ir.Name, @ir.Type]) -> String {
  fields
  .iter()
  .map(field => lower_camel(field.0) + " : " + elm_text(field.1))
  .collect()
  .join(", ")
}

///|
/// `comparable-a` is `comparableA`.
fn lower_camel(name : @ir.Name) -> String {
  let parts = name
    .to_segments()
    .map(segment => {
      match segment {
        Word(text) | Initialism(text) => text
      }
    })
  let out = StringBuilder()
  for i, part in parts {
    out.write_string(if i == 0 { part } else { capitalize(part) })
  }
  out.to_string()
}

///|
/// `int-8` is `Int8`.
fn upper_camel(name : @ir.Name) -> String {
  name
  .to_segments()
  .map(segment => {
    match segment {
      Word(text) | Initialism(text) => capitalize(text)
    }
  })
  .join("")
}

///|
fn capitalize(text : String) -> String {
  let chars = text.to_array()
  if chars.length() > 0 && chars[0] >= 'a' && chars[0] <= 'z' {
    chars[0] = (chars[0].to_int() - 32).unsafe_to_char()
  }
  String::from_array(chars)
}

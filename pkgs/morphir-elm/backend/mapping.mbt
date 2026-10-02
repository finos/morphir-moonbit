///|
/// `Function` and `Type` hold an Elm name, qualified or not, and an optional import line.
pub(all) enum MappingEntry {
  Operator(String)
  Function(String, String?)
  Type(String, String?)
  Removed
} derive(Eq, Debug)

///|
/// Keys are canonical FQName text, for example `morphir/SDK:basics#add`.
pub struct Mapping {
  priv entries : Map[String, MappingEntry]
}

///|
pub fn Mapping::empty() -> Mapping {
  { entries: Map([]), }
}

///|
pub fn Mapping::builtin() -> Mapping {
  { entries: Map::from_array(builtin_entries()), }
}

///|
pub fn Mapping::with_overrides(
  self : Mapping,
  overrides : Map[String, MappingEntry],
) -> Mapping {
  let entries = self.entries.copy()
  for key, entry in overrides {
    entries[key] = entry
  }
  { entries, }
}

///|
pub fn Mapping::lookup(self : Mapping, name : @ir.FQName) -> MappingEntry? {
  match self.entries.get(name.to_canonical()) {
    Some(Removed) | None => None
    Some(entry) => Some(entry)
  }
}

///|
pub fn Mapping::is_empty(self : Mapping) -> Bool {
  self.entries.is_empty()
}

///|
fn parse_mapping_entry(
  key : String,
  value : Json,
) -> MappingEntry raise ElmGenerationError {
  let at = "backends.elm.mapping." + key
  let canonical = @ir.FQName::parse(key) catch {
    _ => refuse("invalid_mapping", at, "the key is not a canonical FQName")
  }
  if canonical.to_canonical() != key {
    refuse(
      "invalid_mapping",
      at,
      "write the key as " + canonical.to_canonical(),
    )
  }
  guard value is Object(fields) else {
    refuse("invalid_mapping", at, "an entry is a table")
  }
  let mut kind : (String, String)? = None
  let mut import_line : String? = None
  for name, field in fields {
    guard field is String(text) && text != "" else {
      refuse("invalid_mapping", at, name + " must be nonempty text")
    }
    match name {
      "operator" | "function" | "type" => {
        if kind is Some(_) {
          refuse(
            "invalid_mapping", at, "use exactly one of operator, function or type",
          )
        }
        kind = Some((name, text))
      }
      "import" => import_line = Some(text)
      other => refuse("invalid_mapping", at, "unknown key " + other)
    }
  }
  match (kind, import_line) {
    (None, None) => Removed
    (None, Some(_)) =>
      refuse("invalid_mapping", at, "import needs a function or type")
    (Some(("operator", _)), Some(_)) =>
      refuse("invalid_mapping", at, "an operator takes no import")
    (Some(("operator", op)), None) => Operator(op)
    (Some(("function", name)), imp) => Function(name, imp)
    (Some((_, name)), imp) => Type(name, imp)
  }
}

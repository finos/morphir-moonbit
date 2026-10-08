///|
fn symbol(at : @scheme.Located) -> String? {
  match at.datum {
    Symbol(text) => Some(text)
    _ => None
  }
}

///|
fn read_name(ctx : Context, at : @scheme.Located) -> @ir.Name raise SpecError {
  guard symbol(at) is Some(text) else { ctx.fail(at, "expected a name") }
  let name = @ir.Name::parse(text) catch {
    _ =>
      ctx.fail(at, "name `\{text}` is not canonical (use `\{suggest(text)}`)")
  }
  if name.to_canonical() != text {
    ctx.fail(
      at,
      "name `\{text}` is not canonical (use `\{name.to_canonical()}`)",
    )
  }
  name
}

///|
/// camelCase to canonical words for error hints only.
fn suggest(text : String) -> String {
  let out = StringBuilder()
  for i, c in text.iter().collect() {
    if c >= 'A' && c <= 'Z' && i > 0 {
      out.write_char('-')
      out.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn read_reference(
  ctx : Context,
  at : @scheme.Located,
  text : String,
) -> @ir.FQName raise SpecError {
  let full = if text.contains(":") {
    text
  } else {
    ctx.package_name.to_canonical() + ":" + text
  }
  let name = @ir.FQName::parse(full) catch {
    _ => ctx.fail(at, "`\{text}` is not a reference")
  }
  if name.to_canonical() != full {
    ctx.fail(
      at,
      "reference `\{text}` is not canonical (use `\{name.to_canonical()}`)",
    )
  }
  name
}

///|
fn class_of(name : @ir.Name) -> String? {
  let text = name.to_canonical()
  for class in ["compappend", "appendable", "comparable", "number"] {
    if text.has_prefix(class) {
      return Some(class)
    }
  }
  None
}

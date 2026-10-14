///|
let url_markers : Array[String] = [" href=\"", " src=\""]

///|
fn earliest(text : StringView) -> (Int, String)? {
  let mut best : (Int, String)? = None
  for marker in url_markers {
    if text.find(marker) is Some(i) {
      match best {
        Some((j, _)) if j <= i => ()
        _ => best = Some((i, marker))
      }
    }
  }
  best
}

///|
/// Apply `f` to every `href` and `src` attribute value. `f` receives the URL with
/// entities decoded, and its result is escaped again.
pub fn map_urls(html : String, f : (String) -> String) -> String {
  let out = StringBuilder()
  let mut rest = html[:]
  while earliest(rest) is Some((start, marker)) {
    let value_start = start + marker.length()
    let value = rest[value_start:]
    guard value.find("\"") is Some(end) else { break }
    out.write_view(rest[:value_start])
    out.write_string(escape(f(unescape(value[:end].to_owned()))))
    rest = value[end:]
  }
  out.write_view(rest)
  out.to_string()
}

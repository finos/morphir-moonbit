///|
/// The route of a file below `docs/`. `rel` uses `/`, has no leading `/`, and ends in
/// `.md` or `.html`. A `README` or `index` file gives the route of its directory.
pub fn doc_route(rel : String) -> String {
  let stem = strip_extension(rel).to_lower()
  let (dir, name) = match stem.rev_find("/") {
    Some(i) => (stem[:i].to_owned(), stem[i + 1:].to_owned())
    None => ("", stem)
  }
  let path = if name == "readme" || name == "index" {
    dir
  } else if dir == "" {
    name
  } else {
    "\{dir}/\{name}"
  }
  if path == "" {
    "/docs/"
  } else {
    "/docs/\{path}/"
  }
}

///|
pub fn strip_extension(path : String) -> String {
  for ext in [".html", ".md"] {
    if path.has_suffix(ext) {
      return path[:path.length() - ext.length()].to_owned()
    }
  }
  path
}

///|
/// Split a blog file name `YYYY-MM-DD-slug.md` (or `.html`) into its date and slug.
pub fn post_parts(file_name : String) -> (String, String)? {
  let stem = strip_extension(file_name)
  if stem == file_name || stem.length() < 12 || stem[10] != '-' {
    return None
  }
  let date = stem[:10].to_owned()
  let slug = stem[11:].to_owned()
  for i, c in date {
    let ok = if i == 4 || i == 7 { c == '-' } else { c >= '0' && c <= '9' }
    if !ok {
      return None
    }
  }
  Some((date, slug))
}

///|
pub fn post_route(slug : String) -> String {
  "/blog/\{slug}/"
}

///|
pub fn package_route(name : String) -> String {
  "/docs/packages/\{name}/"
}

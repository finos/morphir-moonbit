///|
/// Reject escapes rather than normalizing them through the host root.
fn normalize(path : String) -> String raise {
  if path.has_prefix("/") ||
    path.contains("\\") ||
    path.contains(":") ||
    path.contains("\u0000") {
    raise @scheme.Invalid("Expected a portable relative path: " + path)
  }
  let parts : Array[String] = []
  for part in path.split("/") {
    let part = part.to_owned()
    if part == ".." {
      raise @scheme.Invalid("Path escapes its root: " + path)
    }
    if part != "" && part != "." {
      parts.push(part)
    }
  }
  parts.join("/")
}

///|
fn join(root : String, path : String) -> String raise {
  let path = normalize(path)
  if root == "" {
    path
  } else if path == "" {
    root
  } else {
    root + "/" + path
  }
}

///|
fn within(root : String, path : String) -> Bool {
  root == "" || path.has_prefix(root + "/")
}

///|
fn relative(root : String, path : String) -> String raise {
  if !within(root, path) {
    raise @scheme.Invalid("Host listed a path outside source root: " + path)
  }
  if root == "" {
    path
  } else {
    path[root.length() + 1:].to_owned()
  }
}

///|
fn parent(path : String) -> String {
  let parts = path.split("/").map(StringView::to_owned).collect()
  parts[:parts.length() - 1].to_owned().join("/")
}

///|
fn stem(path : String) -> String {
  let parts = path.split("/").map(StringView::to_owned).collect()
  let file = parts[parts.length() - 1]
  let bits = file.split(".").map(StringView::to_owned).collect()
  let name = if bits.length() > 1 {
    bits[:bits.length() - 1].to_owned().join(".")
  } else {
    file
  }
  parts[parts.length() - 1] = name
  parts.join("/")
}

///|
/// Project metadata and filenames use conventional spelling; IR uses canonical names.
fn canonical_path(text : String) -> String raise {
  let paths = text
    .split(".")
    .map(StringView::to_owned)
    .collect()
    .join("/")
    .split("/")
  let result = []
  for path in paths {
    let path = path.to_owned()
    let canonical = Some(@ir.Name::parse(path).to_canonical()) catch {
      _ => None
    }
    if canonical is Some(value) {
      result.push(value)
      continue
    }
    let chars = path.to_array()
    let words = []
    let mut word = ""
    for i, ch in chars {
      let upper = ch >= 'A' && ch <= 'Z'
      let previous_lower = i > 0 && chars[i - 1] >= 'a' && chars[i - 1] <= 'z'
      let next_lower = i + 1 < chars.length() &&
        chars[i + 1] >= 'a' &&
        chars[i + 1] <= 'z'
      if ch == '_' ||
        ch == '-' ||
        ch == ' ' ||
        (upper && (previous_lower || next_lower)) {
        if word != "" {
          words.push(word)
          word = ""
        }
      }
      if ch != '_' && ch != '-' && ch != ' ' {
        word = word + ch.to_string()
      }
    }
    if word != "" {
      words.push(word)
    }
    let value = words
      .map(fn(w) {
        if w.length() > 1 && w == w.to_upper() {
          w
        } else {
          w.to_lower()
        }
      })
      .join("-")
    result.push(@ir.Name::parse(value).to_canonical())
  }
  result.join("/")
}

///|
pub fn normalize(path : String) -> String raise {
  if path.has_prefix("/") ||
    path.contains("\\") ||
    path.contains(":") ||
    path.contains("\u0000") {
    raise @config.Invalid("Expected a confined relative path: " + path)
  }
  let parts = []
  for part in path.split("/") {
    let part = part.to_owned()
    if part == ".." {
      raise @config.Invalid("Path escapes its root: " + path)
    }
    if part != "" && part != "." {
      parts.push(part)
    }
  }
  parts.join("/")
}

///|
pub fn join(root : String, path : String) -> String raise {
  let root = normalize(root)
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
pub fn within(root : String, path : String) -> Bool {
  root == "" || path == root || path.has_prefix(root + "/")
}

///|
pub fn parent(path : String) -> String {
  let parts = path.split("/").map(StringView::to_owned).collect()
  if parts.length() <= 1 {
    ""
  } else {
    parts[:parts.length() - 1].to_owned().join("/")
  }
}

///|
fn suffix(root : String, path : String) -> String {
  if root == "" {
    path
  } else if path == root {
    ""
  } else {
    path[root.length() + 1:].to_owned()
  }
}

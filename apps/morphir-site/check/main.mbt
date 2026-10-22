///|
/// Order by code unit: the pinned `String::compare` orders by length first.
fn compare_units(a : String, b : String) -> Int32 {
  let shared = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<shared {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
async fn list_files(root : String, prefix~ : String = "") -> Array[String] {
  let out = []
  let dir = if prefix == "" { root } else { "\{root}/\{prefix}" }
  let names = @fs.readdir(dir)
  names.sort_by(compare_units)
  for name in names {
    let rel = if prefix == "" { name } else { "\{prefix}/\{name}" }
    match @fs.kind("\{root}/\{rel}") {
      Directory => out.append(list_files(root, prefix=rel))
      Regular => out.push(rel)
      _ => ()
    }
  }
  out
}

///|
fn check_command() -> @argparse.Command {
  @argparse.Command(
    "morphir-site check",
    about="Check the generated site's links and metadata",
    options=[
      @argparse.OptionArg("dir", action=Append, allow_hyphen_values=true),
      @argparse.OptionArg("config", action=Append, allow_hyphen_values=true),
      @argparse.OptionArg("base", action=Append, allow_hyphen_values=true),
    ],
  )
}

///|
fn check_options(args : @argparse.Matches) -> (String, String, String?) {
  (
    args.values.get("dir").map(values => values[0]).unwrap_or("../../_site"),
    args.values
    .get("config")
    .map(values => values[0])
    .unwrap_or("../../site/site.json"),
    args.values.get("base").map(values => values[0]),
  )
}

///|
async fn main {
  let args = check_command().parse() catch {
    error => {
      println("error: \{error}")
      @sys.exit(1)
      return
    }
  }
  let (dir, config_path, base_override) = check_options(args)
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file(config_path).text(),
  ) catch {
    @model.Invalid(found) => {
      for p in found {
        println("error: \{p.render()}")
      }
      @sys.exit(1)
      abort("unreachable")
    }
    error => {
      println("error: \{error}")
      @sys.exit(1)
      abort("unreachable")
    }
  }
  // `--base` overrides the base path from `site/site.json`.
  let base = base_override.unwrap_or(config.base_path)
  let all = list_files(dir)
  // The workbench at try/ is checked by its own tests and the browser smoke test.
  let files = all.filter(f => !f.has_prefix("try/"))
  let html = []
  for f in files {
    if f.has_suffix(".html") {
      html.push((f, @fs.read_file("\{dir}/\{f}").text()))
    }
  }
  let feed = if files.contains("blog/atom.xml") {
    Some(@fs.read_file("\{dir}/blog/atom.xml").text())
  } else {
    None
  }
  let problems = @site.check_site(base, all, html, feed)
  for p in problems {
    println("error: \{p.render()}")
  }
  if problems.length() > 0 {
    @sys.exit(1)
  }
  println("check:site: \{html.length()} pages OK")
}

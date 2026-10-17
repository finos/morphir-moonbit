///|
/// Compile each file in file mode; run the last one's `main` when it has trailing expressions.
fn run_example(files : Array[(String, String)]) -> String raise {
  let mut last = ""
  for file in files {
    let module_name = module_of(file.0)
    let ir = @frontend.compile_file(file.1, module_name~)
    last = if has_main(ir) {
      @scheme.value_to_string(
        @backend.run_file(
          ir,
          @ir.FQName::parse("user:" + module_name + "#main"),
          [],
        ),
      )
    } else {
      ""
    }
  }
  last
}

///|
fn module_of(path : String) -> String {
  if path == "" {
    return "main"
  }
  let p = if path.has_prefix("src/") { path[4:].to_owned() } else { path }
  match p.rev_find(".") {
    Some(i) => p[:i].to_owned()
    None => p
  }
}

///|
fn has_main(ir : @ir.IRFile) -> Bool raise {
  guard ir.distribution is Library(_, _, definition) else { return false }
  let main = @ir.Name::parse("main")
  definition.modules.values().any(m => m.value.values.contains(main))
}

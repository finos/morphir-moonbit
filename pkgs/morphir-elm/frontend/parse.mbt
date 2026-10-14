///|
/// The IR module path: the module name without the package segments.
pub fn module_path(
  module_name : Array[String],
  pkg_segs : Array[String],
) -> @ir.Path {
  @mapping.elm_path(module_name[pkg_segs.length():].to_owned())
}

///|
fn dotted(segments : Array[String]) -> String {
  segments.join(".")
}

///|
fn package_segments(package_name : String) -> Array[String] {
  package_name.split(".").map(s => s.to_owned()).collect()
}

///|
/// Parses every source, then checks the module rules. All sources are parsed before the first problem is raised.
pub fn parse_modules(
  sources : Array[ElmSource],
  package_name : String,
) -> Array[@resolve.ParsedModule] raise ElmFailed {
  let pkg_segs = package_segments(package_name)
  let problems : Array[ElmProblem] = []
  let modules : Array[@resolve.ParsedModule] = []
  for source in sources {
    let result = @krueger.parse_module(@krueger.SourceText::new(source.content))
    let errors = result.diagnostics.filter(d => d.severity is Error)
    for d in errors {
      problems.push({
        code: "elm.parse",
        message: d.code + ": " + d.message,
        path: source.path,
        location: Some({
          start_line: d.span.start.line,
          start_column: d.span.start.column,
          end_line: d.span.end.line,
          end_column: d.span.end.column,
        }),
      })
    }
    guard result.ast is Some(file) && errors.is_empty() else {
      if errors.is_empty() {
        problems.push(
          problem("elm.parse", "the module does not parse", source.path, None),
        )
      }
      continue
    }
    let header = file.module_definition
    if !(header.value is NormalModule(_)) {
      problems.push(
        problem(
          "elm.unsupported",
          "port and effect modules are not supported",
          source.path,
          Some(header.range),
        ),
      )
      continue
    }
    let parsed : @resolve.ParsedModule = { name: [], path: source.path, file, }
    let name = parsed.header().module_name.value.to_owned()
    let expected = source.path
      .strip_suffix(".elm")
      .unwrap_or(source.path)
      .split("/")
      .map(s => s.to_owned())
      .collect()
    if name != expected {
      problems.push(
        problem(
          "elm.module_name",
          "the module \{dotted(name)} must be in \{dotted(name).replace_all(old=".", new="/")}.elm",
          source.path,
          Some(parsed.header().module_name.range),
        ),
      )
      continue
    }
    if name.length() <= pkg_segs.length() ||
      name[:pkg_segs.length()].to_owned() != pkg_segs {
      problems.push(
        problem(
          "elm.module_name",
          "the module \{dotted(name)} must start with the package name \{package_name} and have one more segment",
          source.path,
          Some(parsed.header().module_name.range),
        ),
      )
      continue
    }
    modules.push({ ..parsed, name, })
  }
  fail_if_any(problems)
  check_cycles(modules)
  modules
}

///|
/// Elm forbids import cycles. The first module of a cycle, in source order, gets the problem.
fn check_cycles(modules : Array[@resolve.ParsedModule]) -> Unit raise ElmFailed {
  let by_name : Map[String, @resolve.ParsedModule] = Map([])
  for m in modules {
    by_name[dotted(m.name)] = m
  }
  // 0 = new, 1 = on the stack, 2 = done
  let state : Map[String, Int] = Map([])
  let problems : Array[ElmProblem] = []
  fn visit(name : String, stack : Array[String]) -> Unit {
    match state.get(name) {
      Some(2) => return
      Some(1) => {
        let start = stack.search(name).unwrap_or(0)
        let cycle = stack[start:].to_owned()
        cycle.push(name)
        let first = by_name[cycle[0]]
        if !problems.iter().any(p => p.code == "elm.import_cycle") {
          problems.push(
            problem(
              "elm.import_cycle",
              "the imports form a cycle: " + cycle.join(" -> "),
              first.path,
              None,
            ),
          )
        }
        return
      }
      _ => ()
    }
    state[name] = 1
    stack.push(name)
    guard by_name.get(name) is Some(m) else { return }
    for i in m.imports() {
      let target = dotted(i)
      if by_name.contains(target) {
        visit(target, stack)
      }
    }
    ignore(stack.pop())
    state[name] = 2
  }
  for m in modules {
    visit(dotted(m.name), [])
  }
  fail_if_any(problems)
}

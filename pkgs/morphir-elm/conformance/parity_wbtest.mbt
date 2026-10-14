///|
/// Reads a morphir-elm make output as current IR. morphir-elm writes the inferred type of each value input next
/// to its declared type, and the format 3 migration refuses an input whose two types differ (for example `t5` for
/// an extensible record). The harness sets each inferred input type to the declared type first. Value attributes
/// are not compared.
fn read_expected(text : String) -> @ir.IRFile raise {
  let json = @json.parse(text)
  declared_input_types(json)
  @migration.to_current(@versioned_json.read(json.stringify()))
}

///|
/// Sets the attribute of every value input (`[name, attribute, type]` in `inputTypes`) to its declared type.
fn declared_input_types(json : Json) -> Unit {
  match json {
    Object(fields) =>
      for key, field in fields {
        if key == "inputTypes" && field is Array(inputs) {
          for input in inputs {
            if input is Array(parts) && parts.length() == 3 {
              parts[1] = parts[2]
            }
          }
        }
        declared_input_types(field)
      }
    Array(items) =>
      for item in items {
        declared_input_types(item)
      }
    _ => ()
  }
}

///|
/// Compiles a parity project with the frontend and compares the result with the morphir-elm make output.
fn parity_differences(project : ParityProject) -> Array[String] raise {
  let expected = read_expected(project.expected) catch {
    e => fail("expected IR does not read: " + e.to_string())
  }
  let sources : Array[@frontend.ElmSource] = project.sources.map(s => {
    path: s.0,
    content: s.1,
  })
  let actual = @frontend.compile_project(
    sources,
    project.package_name,
    project.exposed,
  ) catch {
    @frontend.ElmFailed(problems) =>
      fail(
        problems.map(p => p.code + " " + p.path + " " + p.message).join("; "),
      )
  }
  differences(expected, actual)
}

///|
test "every parity project matches morphir-elm make, except pinned gaps" {
  let gaps = parity_gaps()
  let failures : Array[String] = []
  for project in parity_projects() {
    let found = parity_differences(project) catch { e => [e.to_string()] }
    let pinned = gaps.get(project.name).unwrap_or([])
    if found != pinned {
      failures.push(
        project.name +
        ": differences\n  " +
        found.join("\n  ") +
        "\npinned\n  " +
        pinned.join("\n  "),
      )
    }
  }
  if !failures.is_empty() {
    fail(failures.join("\n"))
  }
}

///|
test "every pinned gap names a parity project" {
  let names = parity_projects().map(p => p.name)
  for name, _ in parity_gaps() {
    assert_true(names.contains(name))
  }
}

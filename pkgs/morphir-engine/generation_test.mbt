///|
fn generation_files(
  backend : String,
  language? : String = "ir-json",
) -> Map[String, String] raise {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Pricing'\n[frontend]\nlanguage='" +
      language +
      "'\n[pipeline]\nbackend='" +
      backend +
      "'\nvalidation='source-only'",
    ),
    ("src/main.json", @ir_json.write(@fixtures.library())),
  ])
}

///|
fn generation_plan(
  engine : @engine.Engine,
  files : Map[String, String],
) -> @engine.Plan raise {
  engine.plan(
    @engine.Host::memory(files),
    @workspace.discover({ files, directories: ["", "src"], }),
    @engine.Request::new(),
  )
}

///|
test "MoonBit generation isolates each complete library and accepts JSON Ion inputs" {
  let registry = @data.Registry::new()
  let engine = @engine.Engine::new()
  for language in ["ir-json", "ion-text", "ion-binary"] {
    let files = generation_files("moonbit", language~)
    files.remove("src/main.json")
    let suffix = if language == "ir-json" {
      ".json"
    } else if language == "ion-text" {
      ".ion"
    } else {
      ".ionb"
    }
    files["src/main" + suffix] = "placeholder"
    let unit = @data.IRUnit::new("main", @fixtures.pricing())
    let content = registry.encode(
      if language == "ir-json" {
        "morphir-json"
      } else {
        language
      },
      unit,
    )
    let plan = generation_plan(engine, files)
    assert_true(plan.requires_byte_write())
    let report = engine.execute_content(plan, fn(_, _) { content })
    if !report.successful() {
      fail(report.diagnostics[0].message)
    }
    assert_eq(report.processed, 1)
    assert_eq(report.artifacts.length(), 4)
    assert_eq(report.projects.length(), 1)
    assert_eq(report.projects[0].root, ".morphir/out/compile.dest/main")
    assert_eq(report.projects[0].policy, @engine.SourceOnly)
    assert_true(
      report.artifacts.any(a => {
        a.path.has_suffix("/symbols.10n") && a.content is @data.Binary(_)
      }),
    )
  }
}

///|
test "generic generation validates membership and paths without MoonBit filenames" {
  let files = generation_files("other")
  let batches : Array[(@engine.GenerationBatch, Bool)] = [
    (
      {
        warnings: [],
        files: [
          {
            path: "component/spec.txt",
            content: @data.Text("library"),
            format: "other-source",
          },
        ],
        projects: [
          {
            id: "other",
            root: "component",
            members: ["spec.txt"],
            dependencies: [],
            build_contract: "other-library-v1",
          },
        ],
      },
      true,
    ),
    (
      {
        warnings: [],
        files: [
          { path: "../escape", content: @data.Text("bad"), format: "other", },
        ],
        projects: [
          {
            id: "other",
            root: "",
            members: ["../escape"],
            dependencies: [],
            build_contract: "other",
          },
        ],
      },
      false,
    ),
    (
      {
        warnings: [],
        files: [
          { path: "one", content: @data.Text("bad"), format: "other", },
          { path: "ONE", content: @data.Text("bad"), format: "other", },
        ],
        projects: [
          {
            id: "other",
            root: "",
            members: ["one", "ONE"],
            dependencies: [],
            build_contract: "other",
          },
        ],
      },
      false,
    ),
    (
      {
        warnings: [],
        files: [
          { path: "one", content: @data.Text("bad"), format: "other", },
          { path: "one/two", content: @data.Text("bad"), format: "other", },
        ],
        projects: [
          {
            id: "other",
            root: "",
            members: ["one", "one/two"],
            dependencies: [],
            build_contract: "other",
          },
        ],
      },
      false,
    ),
    (
      {
        warnings: [],
        files: [{ path: "one", content: @data.Text("bad"), format: "other", }],
        projects: [
          {
            id: "other",
            root: "",
            members: ["missing"],
            dependencies: [],
            build_contract: "other",
          },
        ],
      },
      false,
    ),
    (
      {
        warnings: [],
        files: [{ path: "one", content: @data.Text("bad"), format: "other", }],
        projects: [],
      },
      false,
    ),
  ]
  for (batch, valid) in batches {
    let engine = @engine.Engine::new()
    engine.register_generation_backend("other", {
      generate: fn(_, _, _) { batch },
      write_bytes: false,
      validate_options: fn(_) { () },
      targets: [],
    })
    let plan = generation_plan(engine, files)
    let report = engine.execute_content(plan, fn(_, _) {
      @data.Text(files["src/main.json"])
    })
    if valid && !report.successful() {
      fail(report.diagnostics[0].message)
    }
    assert_eq(report.successful(), valid)
    if !valid {
      assert_true(report.artifacts.is_empty())
      assert_true(report.projects.is_empty())
    }
  }
}

///|
test "input project roots reject case and ancestor collisions during planning" {
  for
    paths in [
      ["src/one.json", "src/ONE.json"],
      ["src/one.json", "src/one/two.json"],
    ] {
    let files = generation_files("moonbit")
    files.remove("src/main.json")
    for path in paths {
      files[path] = "ignored"
    }
    assert_true(
      try {
        ignore(generation_plan(@engine.Engine::new(), files))
        false
      } catch {
        _ => true
      },
    )
  }
}

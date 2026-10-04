///|
fn build_files() -> Map[String, String] {
  let files = checkpoint_files()
  files["morphir.toml"] = "[project]\nname='Pricing'\n[frontend]\nlanguage='ir-json'\n[pipeline]\nbackend='moonbit'\ntarget='native'"
  files
}

///|
fn evidence(request : @host.LibraryBuildRequest, lease : String) -> Json {
  let digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  Json::object(
    Map::from_array([
      ("successful", Json::boolean(true)),
      ("frozen", Json::boolean(true)),
      ("leaseId", Json::string(lease)),
      ("projectId", Json::string(request.project.id)),
      ("contract", Json::string(request.project.build_contract)),
      ("sourceIdentity", Json::string(request.source_identity)),
      ("target", Json::string(request.target)),
      ("compilerVersion", Json::string(@toolchain.compiler_version)),
      ("compilerIdentity", Json::string(digest)),
      ("coreIdentity", Json::string(digest)),
      ("buildIdentity", Json::string(digest)),
      (
        "dependencies",
        Json::array(
          request.project.dependencies.map(d => {
            Json::object(
              Map::from_array([
                ("moduleName", Json::string(d.module_name)),
                ("version", Json::string(d.version)),
                ("apiProfile", Json::string(d.api_profile)),
                ("semanticPin", Json::string(d.semantic_pin)),
                ("sourceIdentity", Json::string(digest)),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
}

///|
test "required builds and disposal finish before publication and produce Ion evidence" {
  let (mount, engine, plan) = prepare(build_files())
  let order = []
  let provider : @host.LibraryBuildProvider = {
    contracts: ["moonbit-library-v1"],
    acquire: fn() {
      order.push("acquire")
      {
        id: "lease1",
        build: fn(request) {
          order.push("build")
          evidence(request, "lease1")
        },
        dispose: fn() { order.push("dispose") },
      }
    },
  }
  let outputs = Map([])
  let memory = @host.ContentPublisher::memory(outputs)
  let publisher = {
    ..memory,
    begin: fn(destinations) raise {
      order.push("publish")
      (memory.begin)(destinations)
    },
  }
  let result = @host.Host::new(mount, library_build=Some(provider)).run_content(
    engine, plan, publisher,
  )
  assert_true(result.successful())
  assert_eq(order, ["acquire", "build", "dispose", "publish"])
  assert_eq(result.validated.length(), 1)
  assert_eq(outputs.length(), 5)
  guard outputs[result.validated[0].receipt] is @data.Binary(bytes) else {
    fail("Ion receipt")
  }
  let receipt = @ion_binary.read_binary_value(bytes[:])
  assert_eq(receipt.annotations()[0].text(), Some("morphir_library_build"))
}

///|
test "wrong or stale build evidence and cleanup failures leave prior output intact" {
  for
    wrong in [
      "successful", "frozen", "leaseId", "sourceIdentity", "compilerVersion", "compilerIdentity",
      "coreIdentity", "buildIdentity", "dependencies", "cleanup",
    ] {
    let (mount, engine, plan) = prepare(build_files())
    let disposed = Ref(false)
    let provider : @host.LibraryBuildProvider = {
      contracts: ["moonbit-library-v1"],
      acquire: fn() {
        {
          id: "fresh",
          build: fn(request) {
            let value = evidence(request, "fresh")
            guard value is Object(fields) else { abort("fixture") }
            if wrong != "cleanup" {
              fields[wrong] = if wrong == "successful" || wrong == "frozen" {
                Json::boolean(false)
              } else if wrong == "dependencies" {
                Json::array([])
              } else {
                Json::string("stale")
              }
            }
            value
          },
          dispose: fn() raise {
            disposed.val = true
            if wrong == "cleanup" {
              raise @config.Invalid("injected cleanup failure")
            }
          },
        }
      },
    }
    let old = Map::from_array([
      (".morphir/out/compile.dest/previous", @data.Text("previous")),
    ])
    let before = old.copy()
    let result = @host.Host::new(mount, library_build=Some(provider)).run_content(
      engine,
      plan,
      @host.ContentPublisher::memory(old),
    )
    assert_false(result.successful())
    assert_true(disposed.val)
    assert_true(result.validated.is_empty())
    assert_true(result.committed.is_empty())
    assert_eq(old, before)
    assert_eq(result.report.artifacts.length(), 4)
  }
}

///|
test "all projects must validate and cancellation disposes the lease" {
  for cancel in [false, true] {
    let files = build_files()
    files["src/Other.json"] = files["src/Main.json"]
    let (mount, engine, plan) = prepare(files)
    let calls = Ref(0)
    let acquired = Ref(0)
    let disposed = Ref(0)
    let cancellation = Ref(false)
    let provider : @host.LibraryBuildProvider = {
      contracts: ["moonbit-library-v1"],
      acquire: fn() {
        acquired.val += 1
        let id = "lease" + acquired.val.to_string()
        {
          id,
          build: fn(request) raise {
            calls.val += 1
            if calls.val == 2 {
              if cancel {
                cancellation.val = true
              } else {
                raise @config.Invalid("compiler failed")
              }
            }
            evidence(request, id)
          },
          dispose: fn() { disposed.val += 1 },
        }
      },
    }
    let outputs = Map([])
    let result = @host.Host::new(mount, library_build=Some(provider), cancelled=fn() {
      cancellation.val
    }).run_content(engine, plan, @host.ContentPublisher::memory(outputs))
    assert_false(result.successful())
    assert_eq(calls.val, 2)
    assert_eq(disposed.val, 2)
    assert_true(outputs.is_empty())
    assert_true(result.validated.is_empty())
    assert_eq(result.report.artifacts.length(), 8)
  }
}

///|
test "embedded package compilation does not imply library project capability" {
  let (mount, engine, plan) = prepare(build_files())
  let calls = Ref(0)
  let provider : @host.LibraryBuildProvider = {
    contracts: ["embedded-package-v1"],
    acquire: fn() raise {
      calls.val += 1
      raise @config.Invalid("unexpected")
    },
  }
  let result = @host.Host::new(mount, library_build=Some(provider)).run_content(
    engine,
    plan,
    @host.ContentPublisher::memory(Map([])),
  )
  assert_false(result.successful())
  assert_eq(calls.val, 0)
  assert_true(
    result.publication_error.unwrap().contains("build.unsupported_contract"),
  )
}

///|
test "generation validation and publication events describe actual effects" {
  let (mount, engine, plan) = prepare(build_files())
  let effects : Array[String] = []
  let provider : @host.LibraryBuildProvider = {
    contracts: ["moonbit-library-v1"],
    acquire: fn() {
      {
        id: "fresh",
        build: fn(request) { evidence(request, "fresh") },
        dispose: fn() { () },
      }
    },
  }
  let publisher : @host.ContentPublisher = {
    guarantee: @host.HostManaged,
    write_bytes: true,
    begin: fn(_) raise { raise @config.Invalid("held lock") },
  }
  let host = @host.Host::new(mount, library_build=Some(provider), event=fn(
    event,
  ) {
    match event {
      Generated(_) => effects.push("generated")
      Validated(_) => effects.push("validated")
      Published(_) => effects.push("published")
      _ => ()
    }
  })
  let result = host.run_content(engine, plan, publisher)
  assert_false(result.successful())
  assert_eq(effects, ["generated", "validated"])
  assert_eq(result.validated.length(), 1)
  assert_true(result.committed.is_empty())
}

///|
test "artifact budgets are checked before acquiring a compiler lease" {
  let files = build_files()
  files["morphir.toml"] = files["morphir.toml"].replace(
    old="backend='moonbit'",
    new="backend='huge'",
  )
  let mount = @host.Mount::memory(files)
  let snapshot = @host.Host::new(mount).snapshot()
  let engine = @engine.Engine::new()
  engine.register_generation_backend("huge", {
    write_bytes: false,
    validate_options: fn(_) { () },
    targets: ["wasm", "wasm-gc", "js", "native"],
    generate: fn(_, _, _) {
      {
        warnings: [],
        files: [
          {
            path: "source",
            content: @data.Text(Array::make(4096, "x").join("")),
            format: "source",
          },
        ],
        projects: [
          {
            id: "large",
            root: "",
            members: ["source"],
            dependencies: [],
            build_contract: "moonbit-library-v1",
          },
        ],
      }
    },
  })
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    @engine.Request::new(),
  )
  let acquired = Ref(false)
  let provider : @host.LibraryBuildProvider = {
    contracts: ["moonbit-library-v1"],
    acquire: fn() raise {
      acquired.val = true
      raise @config.Invalid("unexpected")
    },
  }
  let result = @host.Host::new(mount, library_build=Some(provider), limits={
    max_files: 100,
    max_bytes: 1024,
    max_depth: 64,
  }).run_content(engine, plan, @host.ContentPublisher::memory(Map([])))
  assert_false(result.successful())
  assert_false(acquired.val)
  assert_true(result.publication_error.unwrap().contains("Artifact byte limit"))
}

///|
test "publication cleanup retains the primary failure" {
  let (mount, engine, plan) = prepare(checkpoint_files())
  let publisher : @host.ContentPublisher = {
    guarantee: @host.HostManaged,
    write_bytes: true,
    begin: fn(_) {
      {
        stage: fn(_) { () },
        commit: fn(_) raise { raise @config.Invalid("primary commit failure") },
        abort: fn() raise { raise @config.Invalid("secondary cleanup failure") },
      }
    },
  }
  let result = @host.Host::new(mount).run_content(engine, plan, publisher)
  let message = result.publication_error.unwrap()
  assert_true(message.contains("primary commit failure"))
  assert_true(message.contains("secondary cleanup failure"))
  assert_true(result.committed.is_empty())
}

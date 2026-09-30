///|
fn fixture() -> (Host, Map[String, String], Map[String, Bool], Array[String]) {
  let files : Map[String, String] = Map([])
  let dirs = Map::from_array([("/", true), ("/work", true), ("/tmp", true)])
  let calls : Array[String] = []
  let host : Host = {
    execute: fn(program, args, _, _, _) {
      calls.push(program + " " + args.join(" "))
      if program.has_suffix("/moonc") {
        object([
          ("exitCode", Json::number(0.0)),
          ("stdout", Json::string("moonc v" + compiler_version + " (fixture)")),
          ("stderr", Json::string("")),
        ])
      } else if args.length() > 0 && args[0] == "run" {
        object([
          ("exitCode", Json::number(0.0)),
          ("stdout", Json::string("42\n")),
          ("stderr", Json::string("")),
        ])
      } else {
        object([
          ("exitCode", Json::number(1.0)),
          ("stdout", Json::string("")),
          ("stderr", Json::string("fixture failure")),
        ])
      }
    },
    kind: fn(path) {
      if dirs.contains(path) {
        2
      } else if files.contains(path) {
        1
      } else {
        0
      }
    },
    read: fn(path) raise {
      match files.get(path) {
        Some(s) => s
        None => raise ToolchainError("missing fixture")
      }
    },
    write: fn(path, text) { files[path] = text },
    list: fn(path) {
      let prefix = path + "/"
      files
      .keys()
      .concat(dirs.keys())
      .filter(p => p.has_prefix(prefix) && !p[prefix.length():].contains("/"))
      .map(p => p[prefix.length():].to_owned())
      .collect()
    },
    mkdir: fn(path) raise {
      if dirs.contains(path) {
        raise ToolchainError("Busy")
      }
      dirs[path] = true
    },
    remove_file: fn(path) { files.remove(path) },
    remove_dir: fn(path) { dirs.remove(path) },
    rename: fn(_, _) raise {
      raise ToolchainError("fixture rename unavailable")
    },
    temporary: fn() {
      dirs["/tmp/smoke"] = true
      "/tmp/smoke"
    },
    environment: Map::from_array([("HOME", "/users/test")]),
    cwd: "/work",
    system: "linux",
    architecture: "x64",
    process: true,
    cancelled: fn() { false },
  }
  (host, files, dirs, calls)
}

///|
fn expect_failure(action : () -> Json raise) -> Unit raise {
  let failed = try {
    ignore(action())
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "info reports absence without acquiring tooling" {
  let (host, _, _, calls) = fixture()
  let result = host.request(object([("operation", Json::string("info"))]))
  assert_eq(field(result, "available"), Json::boolean(false))
  assert_eq(
    field(result, "operations"),
    Json::array([Json::string("info"), Json::string("setup")]),
  )
  assert_eq(calls.length(), 0)
}

///|
test "absent toolchains advertise setup only for pinned acquisition platforms" {
  let (host, _, _, calls) = fixture()
  for
    (system, architecture) in [
      ("windows", "x64"),
      ("linux", "arm64"),
      ("macos", "x64"),
    ] {
    let unsupported = { ..host, system, architecture, }
    let result = unsupported.request(
      object([("operation", Json::string("info"))]),
    )
    assert_eq(field(result, "operations"), Json::array([Json::string("info")]))
  }
  let macos = { ..host, system: "macos", architecture: "arm64", }
  let result = macos.request(object([("operation", Json::string("info"))]))
  assert_eq(
    field(result, "operations"),
    Json::array([Json::string("info"), Json::string("setup")]),
  )
  assert_eq(calls.length(), 0)
}

///|
test "existing toolchains advertise exec only with moonx and retain setup for reuse" {
  let (host, files, dirs, _) = fixture()
  dirs["/system"] = true
  dirs["/system/lib/core"] = true
  files["/system/bin/moonc"] = ""
  files["/system/bin/moon"] = ""
  host.environment["MOON_HOME"] = "/system"
  let unsupported = { ..host, architecture: "arm64", }
  let without = unsupported.request(
    object([("operation", Json::string("info"))]),
  )
  assert_eq(field(without, "moonx"), Json::boolean(false))
  assert_eq(
    field(without, "operations"),
    Json::array(["info", "compile", "run", "setup", "build"].map(Json::string)),
  )
  files["/system/bin/moonx"] = ""
  let with_moonx = unsupported.request(
    object([("operation", Json::string("info"))]),
  )
  assert_eq(field(with_moonx, "moonx"), Json::boolean(true))
  assert_eq(
    field(with_moonx, "operations"),
    Json::array(
      ["info", "compile", "run", "setup", "build", "exec"].map(Json::string),
    ),
  )
}

///|
test "explicit invalid installation never falls back" {
  let (host, files, dirs, calls) = fixture()
  dirs["/system"] = true
  dirs["/system/lib/core"] = true
  files["/system/bin/moonc"] = ""
  files["/system/bin/moon"] = ""
  host.environment["MOON_HOME"] = "/system"
  expect_failure(fn() raise {
    host.request(
      object([
        ("operation", Json::string("info")),
        ("home", Json::string("/missing")),
      ]),
    )
  })
  assert_eq(calls.length(), 0)
}

///|
test "system toolchain reuse validates core and cleans smoke files" {
  let (host, files, dirs, calls) = fixture()
  dirs["/system"] = true
  dirs["/system/lib/core"] = true
  files["/system/bin/moonc"] = ""
  files["/system/bin/moon"] = ""
  host.environment["MOON_HOME"] = "/system"
  let result = host.request(object([("operation", Json::string("setup"))]))
  assert_eq(string(result, "home"), "/system")
  assert_eq(field(result, "validated"), Json::boolean(true))
  assert_eq(calls.length(), 2)
  assert_true(!dirs.contains("/tmp/smoke"))
  assert_true(!files.contains("/tmp/smoke/main.mbt"))
}

///|
test "acquisition requires consent before effects" {
  let (host, _, _, calls) = fixture()
  expect_failure(fn() raise {
    host.request(object([("operation", Json::string("setup"))]))
  })
  assert_eq(calls.length(), 0)
}

///|
test "failed download cleans owned lock and staging" {
  let (host, _, dirs, calls) = fixture()
  expect_failure(fn() raise {
    host.request(
      object([
        ("operation", Json::string("setup")),
        ("home", Json::string("/tools/pinned")),
        ("consent", Json::boolean(true)),
      ]),
    )
  })
  assert_eq(calls.length(), 1)
  assert_true(!dirs.contains("/tools/pinned.lock"))
  assert_true(!dirs.contains("/tools/pinned.lock/installation"))
  assert_true(!dirs.contains("/tools/pinned"))
}

///|
test "timeout and cancellation stop effects" {
  let (host, _, _, calls) = fixture()
  expect_failure(fn() raise {
    host.request(
      object([
        ("operation", Json::string("info")),
        ("timeout", Json::number(0.0)),
      ]),
    )
  })
  let cancelled = { ..host, cancelled: fn() { true }, }
  expect_failure(fn() raise {
    cancelled.request(
      object([
        ("operation", Json::string("setup")),
        ("consent", Json::boolean(true)),
      ]),
    )
  })
  assert_eq(calls.length(), 0)
}

///|
test "malformed process responses fail before publication" {
  let (host, files, dirs, _) = fixture()
  dirs["/system"] = true
  dirs["/system/lib/core"] = true
  files["/system/bin/moonc"] = ""
  files["/system/bin/moon"] = ""
  host.environment["MOON_HOME"] = "/system"
  let invalid = { ..host, execute: fn(_, _, _, _, _) { Json::null() }, }
  expect_failure(fn() raise {
    invalid.request(object([("operation", Json::string("info"))]))
  })
}

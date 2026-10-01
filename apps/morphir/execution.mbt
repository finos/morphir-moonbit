///|
fn execution_command(args : Array[String], mode : OutputMode) -> Int raise {
  let options : Map[String, String] = Map([])
  let dependencies : Map[String, String] = Map([])
  let mut model = ""
  let mut dry_run = false
  let mut i = 1
  while i < args.length() {
    let key = args[i]
    if key == "--dry-run" {
      dry_run = true
    } else if key.has_prefix("--") {
      if ![
          "--suite", "--suite-format", "--model-format", "--unit-id", "--target",
          "--execution-helper", "--home", "--node", "--dependency", "--timeout",
          "--log-file", "--log-format",
        ].contains(key) {
        raise @config.Invalid("Unknown execution option: " + key)
      }
      i += 1
      if i == args.length() {
        raise @config.Invalid("Missing value for " + key)
      }
      if key == "--dependency" {
        let pair = args[i].split_once("=")
        guard pair is Some((name, path)) else {
          raise @config.Invalid("Expected module=path")
        }
        if dependencies.contains(name.to_owned()) {
          raise @config.Invalid("Duplicate dependency")
        }
        dependencies[name.to_owned()] = path.to_owned()
      } else {
        if options.contains(key) {
          raise @config.Invalid("Duplicate execution option: " + key)
        }
        options[key] = args[i]
      }
    } else {
      if model != "" {
        raise @config.Invalid("Unexpected execution argument")
      }
      model = key
    }
    i += 1
  }
  if model == "" || !options.contains("--suite") {
    raise @config.Invalid("execute/verify requires a model and --suite")
  }
  let logs = @host.TelemetrySession::new(
    if dry_run {
      None
    } else {
      options.get("--log-file")
    },
    format=options.get("--log-format").unwrap_or("ion-binary"),
  )
  // Dry runs never open a log file or acquire a process session.
  let observer = if dry_run {
    @observe.Observer::noop()
  } else {
    logs.observer()
  }
  errdefer logs.flush()
  let scope = observer.scope()
  let plan = scope.observe(@observe.Plan, fn(scope) raise {
    let unit = scope.observe(@observe.Decode, fn(_) raise {
      let format = options
        .get("--model-format")
        .unwrap_or(
          if model.has_suffix(".ionb") || model.has_suffix(".10n") {
            "ion-binary"
          } else if model.has_suffix(".ion") {
            "ion-text"
          } else {
            "morphir-json"
          },
        )
      let content = if format == "ion-binary" {
        @data.Binary(@platform.read_bytes(model))
      } else {
        @data.Text(@platform.read(model))
      }
      @data.Registry::new().decode(format, {
        unit_id: options.get("--unit-id").unwrap_or("model"),
        content,
      })
    })
    let path = options["--suite"]
    let format = options
      .get("--suite-format")
      .unwrap_or(
        if path.has_suffix(".ionb") || path.has_suffix(".10n") {
          "ion-binary"
        } else if path.has_suffix(".json") {
          "json"
        } else {
          "ion-text"
        },
      )
    let suite = @protocol.Suite::decode(@platform.read_bytes(path), format)
    scope.observe(@observe.Generate, fn(_) raise {
      @execution.plan(
        unit,
        suite,
        target=options.get("--target").unwrap_or("js"),
      )
    })
  })
  if dry_run {
    let result : Json = {
      "dryRun": true,
      "target": plan.target,
      "calls": plan.suite.calls.map(c => c.id),
      "entries": plan.suite.calls.map(c => c.entry),
      "evaluator": if args[0] == "verify" {
        "scheme-portable-v1/shared-sdk/bounded"
      } else {
        "none"
      },
    }
    if mode is Human {
      println(
        "Planned " +
        plan.suite.calls.length().to_string() +
        " call(s) for " +
        plan.target,
      )
    } else {
      emit_result(result, mode)
    }
    return 0
  }
  let result = {
    let provider = @host.process_execution(
      options.get("--node").unwrap_or("node"),
      options.get("--execution-helper").unwrap_or(""),
      options.get("--home").unwrap_or(""),
      dependencies,
      timeout=build_timeout(options.get("--timeout").unwrap_or("120000")),
    )
    @execution.run(
      plan,
      provider,
      evaluator=if args[0] == "verify" {
        Some(@execution.Evaluator::scheme())
      } else {
        None
      },
      observer~,
    )
  }
  logs.flush()
  if mode is Human {
    for call in result.calls {
      println(
        call.id +
        ": " +
        call.actual.to_json().stringify() +
        (if call.matches { "" } else { " MISMATCH" }),
      )
    }
  } else {
    emit_result(result.to_json(), mode)
  }
  if result.successful() {
    0
  } else {
    1
  }
}

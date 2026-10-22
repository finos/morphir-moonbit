///|
test "MCK keeps runner controls separate from opaque canonical arguments" {
  let cli = parse_cli([
    "--json", "mck", "--runner-pin", "runner.json", "workbench", "run", "--adapter",
    "adapter path", "--adapter-arg", "--json", "--adapter-arg", "", "--adapter-arg",
    "$(literal)", "--kit", "kit path", "--report", "out.json",
  ])
  assert_eq(cli.command, "mck")
  assert_true(flag(cli, "json"))
  assert_eq(value(cli, "runner-pin"), "runner.json")
  assert_eq(
    cli.forwarded,
    Some([
      "workbench", "run", "--adapter", "adapter path", "--adapter-arg", "--json",
      "--adapter-arg", "", "--adapter-arg", "$(literal)", "--kit", "kit path", "--report",
      "out.json",
    ]),
  )
  assert_eq(parse_cli(["mck", "--help"]).forwarded, None)
  assert_true(parse_cli(["mck", "--help"]).help)
  assert_eq(
    parse_cli(["mck", "--", "report", "compare", "a", "b"]).forwarded,
    Some(["report", "compare", "a", "b"]),
  )
  assert_eq(
    parse_cli(["mck", "check", "kit", "--json"]).forwarded,
    Some(["check", "kit", "--json"]),
  )
}

///|
test "MCK pins refuse unsupported contracts versions and malformed identities" {
  let pin : Json = {
    "contractVersion": "0.1.0-draft.1",
    "runnerVersion": "0.4.0-beta.10",
    "executable": "/private/backend/morphir",
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sourceRevision": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "origin": "https://github.com/finos/morphir/releases/tag/v0.4.0-beta.10",
  }
  let admitted = mck_pin(pin)
  assert_eq(admitted.executable, "/private/backend/morphir")
  for
    (key, replacement) in [
      ("contractVersion", "2.0.0"),
      ("runnerVersion", "0.4.0-beta.9"),
      ("sha256", "abc"),
      ("executable", "morphir"),
      ("sourceRevision", "main"),
      ("origin", ""),
    ] {
    guard pin is Object(fields) else { abort("fixture pin") }
    let changed = fields.copy()
    changed[key] = Json::string(replacement)
    assert_true(
      try {
        ignore(mck_pin(Json::object(changed)))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "MCK local controls preserve the implicit and explicit raw boundary" {
  let tail = [
    "check", "--runner-pin", "child pin", "--json-lines", "--help", "", "λ space",
    "--flag", "one", "--flag", "two", "--", "--", "$(literal);`literal`",
  ]
  for separator in [[], ["--"]] {
    let cli = parse_cli(
      [
        "--no-banner", "--json", "mck", "--runner-pin=runner pin", "--node", "node path",
      ] +
      separator +
      tail,
    )
    assert_eq(cli.command, "mck")
    assert_eq(value(cli, "runner-pin"), "runner pin")
    assert_eq(value(cli, "node"), "node path")
    assert_true(flag(cli, "json"))
    assert_true(!flag(cli, "json-lines"))
    assert_true(!cli.help)
    assert_eq(cli.forwarded, Some(tail))
  }
  assert_eq(parse_cli(["mck", "--"]).forwarded, None)
  assert_eq(parse_cli(["mck", "--", ""]).forwarded, Some([""]))
  assert_eq(parse_cli(["mck", ""]).forwarded, Some([""]))
  assert_eq(
    value(parse_cli(["mck", "--runner-pin", "check", "run"]), "runner-pin"),
    "check",
  )
  assert_eq(
    parse_cli(["mck", "--runner-pin", "check", "run"]).forwarded,
    Some(["run"]),
  )
  assert_eq(value(parse_cli(["mck", "--node", "-", "check"]), "node"), "-")
}

///|
test "MCK help validates every local control before the child boundary" {
  let cli = parse_cli(["--no-banner", "mck", "--help", "check", "--unknown"])
  assert_true(cli.help)
  assert_eq(cli.forwarded, Some(["check", "--unknown"]))
  assert_true(cli.help_text.contains("all later arguments are opaque"))
  for
    args in [
      ["mck", "--help", "--unknown", "check"],
      ["mck", "--runner-pin", "--help", "check"],
      ["mck", "--runner-pin", "--no-banner", "check"],
      ["mck", "--runner-pin", "--", "check"],
      ["mck", "--runner-pin=", "check"],
      ["mck", "--node", "", "check"],
      ["mck", "--timeout", "1", "--timeout=2", "check"],
      ["--json", "mck", "--json-lines", "check"],
      ["mck", "-", "check"],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
      msg=args.join(" | "),
    )
  }
  assert_true(
    error_output_mode(["--json", "mck", "--help", "--unknown"]) is JSON,
  )
  assert_true(
    error_output_mode(["mck", "--json-lines", "--unknown"]) is JSONLines,
  )
  // These are the current failure-envelope rules, even for child-owned flags.
  assert_true(error_output_mode(["mck", "check", "--json"]) is JSON)
  assert_true(error_output_mode(["mck", "--", "check", "--json"]) is Human)
}

///|
/// Task 17 feasibility probe, not the production parser. The existing MCK route
/// has already selected `mck` and its exact supported leading global tokens.
/// Only raw token boundaries are classified here; argparse owns value consumption.
fn qualify_mck_prefix(
  globals : Array[String],
  tokens : Array[String],
  set_controls~ : Bool = false,
  attempts~ : Array[Int32] = [],
) -> Cli raise {
  let controls = command_schema("mck").options
  let raw = globals + ["mck"] + tokens
  let start = globals.length() + 1
  let syntax = @argparse.Command(
    "morphir",
    flags=[
      @argparse.FlagArg("help", short='h', global=true),
      @argparse.FlagArg("json", global=true),
      @argparse.FlagArg("json-lines", global=true),
      @argparse.FlagArg("no-banner", global=true, hidden=true),
    ],
    subcommands=[
      @argparse.Command(
        "mck",
        options=controls.map(name => {
          @argparse.OptionArg(
            name,
            action=if set_controls { Set } else { Append },
          )
        }),
        disable_help_flag=true,
        disable_help_subcommand=true,
      ),
    ],
    disable_help_flag=true,
    disable_help_subcommand=true,
  )
  let mut candidates = 0
  for end = 0; end <= tokens.length(); end = end + 1 {
    if end < tokens.length() &&
      tokens[end] != "--" &&
      tokens[end].has_prefix("-") {
      continue
    }
    candidates += 1
    attempts.push(end)
    let valid = try {
      ignore(syntax.parse(argv=raw[:start + end], env=Map([])))
      true
    } catch {
      _ => false
    }
    if valid {
      // Domain failures are terminal, rather than an excuse to seek a later cut.
      let cli = parse_cli_local(
        raw[:start + end].to_owned().filter(arg => arg != "--no-banner"),
      )
      let offset = if end < tokens.length() && tokens[end] == "--" {
        end + 1
      } else {
        end
      }
      return {
        ..cli,
        forwarded: if offset < tokens.length() {
          Some(tokens[offset:].to_owned())
        } else {
          None
        },
      }
    }
    // Set controls consume at most one non-hyphen value apiece. A valid cut
    // therefore exists within controls.length() + 1 candidate boundaries.
    // This bounds parse attempts, without imposing an argv-length limit.
    if set_controls && candidates >= controls.length() + 1 {
      break
    }
  }
  // Retain library diagnostics when no prefix can be parsed. A production
  // implementation must wrap this in the existing config error boundary.
  attempts.push(tokens.length())
  ignore(syntax.parse(argv=raw, env=Map([])))
  raise @config.Invalid("qualification.no_valid_mck_prefix")
}

///|
test "MCK prefix qualification keeps domain diagnostics and identifies syntax changes" {
  for
    tokens in [
      ["--runner-pin="],
      ["--node", "", "check"],
      ["--timeout", "1", "--timeout=2", "check"],
      ["--json", "--json-lines", "check"],
    ] {
    let current = try {
      ignore(parse_cli(["mck"] + tokens))
      "accepted"
    } catch {
      error => @host.error_message(error)
    }
    let candidate = try {
      ignore(qualify_mck_prefix([], tokens))
      "accepted"
    } catch {
      error => @host.error_message(error)
    }
    assert_eq(candidate, current)
    assert_true(current != "accepted")
  }
  let current = try {
    ignore(parse_cli(["mck", "--no-banner=true", "check"]))
    "accepted"
  } catch {
    error => @host.error_message(error)
  }
  let candidate = try {
    ignore(qualify_mck_prefix([], ["--no-banner=true", "check"]))
    "accepted"
  } catch {
    error => @host.error_message(error)
  }
  assert_true(current.contains("unexpected argument '--no-banner'"))
  assert_true(candidate.contains("unexpected argument '--no-banner=true'"))
  assert_true(current.contains("Usage: morphir mck"))
  assert_true(candidate.contains("Usage: morphir mck"))
  // Filtering compatibility tokens before validating syntax can swallow check.
  assert_eq(
    value(parse_cli_local(["mck", "--runner-pin", "check"]), "runner-pin"),
    "check",
  )
  assert_true(
    try {
      ignore(qualify_mck_prefix([], ["--runner-pin", "--no-banner", "check"]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "library validated MCK prefixes match current accepted values and refusals" {
  let controls = [
    [],
    ["--help"],
    ["--no-banner"],
    ["--runner-pin=pin"],
    ["--runner-pin", "check"],
    ["--runner-pin", ""],
    ["--runner-pin="],
    ["--runner-pin", "--no-banner"],
    ["--runner-pin", "--help"],
    ["--runner-pin", "--"],
    ["--unknown"],
    ["-"],
    ["--node", "-"],
    ["--node=--no-banner"],
    ["--timeout", "1", "--timeout", "2"],
    ["--json", "--json-lines"],
    ["--help", "--unknown"],
    ["--no-banner=true"],
    ["--runner-pin", "pin", "--no-banner"],
    ["--no-banner", "--runner-pin", "pin"],
  ]
  for name in command_schema("mck").options {
    for
      form in [
        ["--" + name + "= spaced λ "],
        ["--" + name, "check"],
        ["--" + name, ""],
        ["--" + name],
        ["--" + name, "-value"],
        ["--" + name, "one", "--" + name, "two"],
        ["--" + name + "=--"],
      ] {
      controls.push(form)
    }
  }
  let tails = [
    [],
    ["check"],
    ["--"],
    ["--", "check"],
    [""],
    ["check", "--node", "child", "--json", "--", "", "--", "--help"],
  ]
  for globals in [[], ["--no-banner", "--json"], ["-h", "--json-lines"]] {
    for control in controls {
      for tail in tails {
        let tokens = control + tail
        let current = Some(parse_cli(globals + ["mck"] + tokens)) catch {
          _ => None
        }
        let candidate = Some(qualify_mck_prefix(globals, tokens)) catch {
          _ => None
        }
        let bounded = Some(
          qualify_mck_prefix(globals, tokens, set_controls=true),
        ) catch {
          _ => None
        }
        match (current, bounded) {
          (Some(current), Some(bounded)) => {
            assert_eq(bounded.command, current.command)
            assert_eq(bounded.flags, current.flags)
            assert_eq(bounded.entries, current.entries)
            assert_eq(bounded.forwarded, current.forwarded)
            assert_eq(bounded.help, current.help)
            assert_eq(bounded.help_text, current.help_text)
          }
          (None, None) => ()
          _ =>
            abort(
              "bounded MCK prefix mismatch: " +
              (globals + ["mck"] + tokens).join(" | "),
            )
        }
        match (current, candidate) {
          (Some(current), Some(candidate)) => {
            assert_eq(candidate.command, current.command)
            assert_eq(candidate.flags, current.flags)
            assert_eq(candidate.entries, current.entries)
            assert_eq(candidate.forwarded, current.forwarded)
            assert_eq(candidate.help, current.help)
            assert_eq(candidate.help_text, current.help_text)
          }
          (None, None) => ()
          _ =>
            abort(
              "MCK prefix qualification mismatch: " +
              (globals + ["mck"] + tokens).join(" | "),
            )
        }
      }
    }
  }
}

///|
test "Set MCK syntax bounds candidate parses without limiting argv length" {
  let flags = [ for _ in 0..<2048 => "--no-banner" ]
  let controls = []
  for name in command_schema("mck").options {
    controls.push("--" + name)
    controls.push("check")
  }
  let tail = ["check"] +
    [
      for _ in 0..<2048 => "child value"
    ] +
    ["--", "", "--help"]
  let attempts = []
  let cli = qualify_mck_prefix(
    [],
    flags + controls + tail,
    set_controls=true,
    attempts~,
  )
  assert_eq(cli.forwarded, Some(tail))
  assert_eq(attempts.length(), command_schema("mck").options.length() + 1)
  let invalid_attempts = []
  assert_true(
    try {
      ignore(
        qualify_mck_prefix(
          [],
          flags + ["--unknown"] + tail,
          set_controls=true,
          attempts=invalid_attempts,
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    invalid_attempts.length(),
    command_schema("mck").options.length() + 2,
  )
  let current = try {
    ignore(parse_cli(["mck", "--timeout=1", "--timeout=2", "check"]))
    "accepted"
  } catch {
    error => @host.error_message(error)
  }
  let bounded = try {
    ignore(
      qualify_mck_prefix(
        [],
        ["--timeout=1", "--timeout=2", "check"],
        set_controls=true,
      ),
    )
    "accepted"
  } catch {
    error => @host.error_message(error)
  }
  assert_eq(current, "Repeated option: --timeout")
  assert_true(
    bounded.contains("argument '--timeout' cannot be used multiple times"),
  )
}

///|
test "variadic parser values cannot reconstruct an opaque MCK tail" {
  let parser = @argparse.Command(
    "mck",
    flags=[@argparse.FlagArg("json")],
    options=[@argparse.OptionArg("node")],
    positionals=[
      @argparse.PositionArg(
        "tail",
        num_args=@argparse.ValueRange(lower=0),
        allow_hyphen_values=true,
      ),
    ],
    disable_help_flag=true,
  )
  let parsed = parser.parse(
    argv=["check", "--json", "--node=child", "", "--", "x", "--"],
    env=Map([]),
  )
  assert_eq(parsed.values.get("tail"), Some(["check", "", "x", "--"]))
  assert_eq(parsed.flags.get("json"), Some(true))
  assert_eq(parsed.values.get("node"), Some(["child"]))
}

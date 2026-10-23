///|
/// Keep the runtime prefix in one adapter; Node supplies two argv entries.
#cfg(target="js")
fn finite_argv() -> ArrayView[String] {
  match @env.args() {
    [_, _, .. rest] => rest
    _ => []
  }
}

///|
#cfg(not(target="js"))
fn finite_argv() -> ArrayView[String] {
  match @env.args() {
    [_, .. rest] => rest
    _ => []
  }
}

///|
fn finite_command() -> @argparse.Command {
  @argparse.Command(
    "morphir-host.acceptance.metadata-fixture",
    about="Generate and verify the command fixture. Leading --json selects one compact morphir/command-result 0.1.0 object plus LF on stdout. Success has state, exitCode0, result and diagnostics; failure has error{code,message}, exitCode1 and no result. Existing JSON success schemas remain bare. --json --help returns help without effects; --json --self-test reports the completed fixture output. Default ignored arguments and failure presentation stay unchanged.",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[
      @argparse.FlagArg("json"),
      @argparse.FlagArg("help", short='h'),
      @argparse.FlagArg("self-test"),
    ],
  )
}

///|
fn finite_success(result : Json) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir-host.acceptance.metadata-fixture",
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": [],
  }
}

///|
fn finite_failure(error : Error) -> Unit {
  println(
    (
      {
        "profile": "morphir/command-result",
        "contractVersion": "0.1.0",
        "command": "morphir-host.acceptance.metadata-fixture",
        "state": "failed",
        "exitCode": 1,
        "error": { "code": "command.failed", "message": error.to_string() },
        "diagnostics": [],
      } : Json).stringify(),
  )
  @sys.exit(1)
}

///|
fn main raise {
  let argv = finite_argv()
  if argv is ["--json", ..] {
    try {
      let command = finite_command()
      let parsed = command.parse(argv~)
      if parsed.flags.get("help").unwrap_or(false) {
        println(finite_success({ "help": command.render_help() }).stringify())
      } else {
        let checkpoint = finite_run()
        let output : Json = { "codec": "ion-text", "checkpoint": checkpoint }
        println(
          if parsed.flags.get("self-test").unwrap_or(false) {
            finite_success({ "passed": true, "output": output }).stringify()
          } else {
            finite_success(output).stringify()
          },
        )
      }
    } catch {
      error => finite_failure(error)
    }
  } else {
    // Historically these fixture programs ignored argv. Keep that legacy path.
    println(finite_run())
  }
}

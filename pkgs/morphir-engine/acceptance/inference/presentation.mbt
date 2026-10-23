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
    "morphir-engine.acceptance.inference",
    about="Generate and verify the command fixture",
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
    "command": "morphir-engine.acceptance.inference",
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
        "command": "morphir-engine.acceptance.inference",
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
        let output = finite_run()
        println(
          if parsed.flags.get("self-test").unwrap_or(false) {
            finite_success({ "passed": true, "output": output }).stringify()
          } else {
            output.stringify()
          },
        )
      }
    } catch {
      error => finite_failure(error)
    }
  } else {
    // Historically these fixture programs ignored argv. Keep that legacy path.
    println(finite_run().stringify())
  }
}

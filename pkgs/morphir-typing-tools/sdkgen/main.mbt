///|
enum SdkCommand {
  Bootstrap(String, String)
  Generate
  Check
} derive(Eq)

///|
fn sdk_command() -> @argparse.Command {
  @argparse.Command(
    "sdkgen",
    about="Generate and check SDK bindings",
    subcommand_required=true,
    subcommands=[
      @argparse.Command("bootstrap", positionals=[
        @argparse.PositionArg(
          "bindings",
          num_args=@argparse.ValueRange::single(),
          allow_hyphen_values=true,
        ),
        @argparse.PositionArg(
          "out",
          num_args=@argparse.ValueRange::single(),
          allow_hyphen_values=true,
        ),
      ]),
      @argparse.Command("generate"),
      @argparse.Command("check"),
    ],
  )
}

///|
fn sdk_invocation(matches : @argparse.Matches) -> SdkCommand {
  match matches.subcommand {
    Some(("bootstrap", args)) =>
      Bootstrap(args.values["bindings"][0], args.values["out"][0])
    Some(("generate", _)) => Generate
    Some(("check", _)) => Check
    _ => abort("sdkgen command selection invariant")
  }
}

///|
fn main {
  let matches = sdk_command().parse() catch {
    error => {
      println(error.to_string())
      @sys.exit(2)
      return
    }
  }
  match sdk_invocation(matches) {
    Bootstrap(bindings, out) =>
      try {
        let message = bootstrap(bindings, out)
        println(message)
      } catch {
        BootstrapError(message) => {
          println("sdkgen: \{message}")
          @sys.exit(1)
        }
        ToolError(message) => {
          println("sdkgen: \{message}")
          @sys.exit(1)
        }
        e => {
          println("sdkgen: \{e}")
          @sys.exit(1)
        }
      }
    Generate =>
      println(generate()) catch {
        ToolError(message) => {
          println("sdkgen: \{message}")
          @sys.exit(1)
        }
        e => {
          println("sdkgen: \{e}")
          @sys.exit(1)
        }
      }
    Check =>
      try {
        let (problems, count) = check()
        if problems.is_empty() {
          println("sdk.scm matches \{count} bindings; sdk_data.mbt is current")
        } else {
          for problem in problems {
            println(problem)
          }
          println("sdkgen: \{problems.length()} differences")
          @sys.exit(1)
        }
      } catch {
        ToolError(message) => {
          println("sdkgen: \{message}")
          @sys.exit(1)
        }
        e => {
          println("sdkgen: \{e}")
          @sys.exit(1)
        }
      }
  }
}

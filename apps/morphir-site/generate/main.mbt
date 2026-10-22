///|
fn generate_command() -> @argparse.Command {
  @argparse.Command(
    "morphir-site generate",
    about="Generate the Morphir project site",
    flags=[@argparse.FlagArg("main")],
    options=[
      @argparse.OptionArg("root", action=Append, allow_hyphen_values=true),
      @argparse.OptionArg("out", action=Append, allow_hyphen_values=true),
    ],
  )
}

///|
fn generate_options(args : @argparse.Matches) -> (String, String, Bool) {
  let root = args.values.get("root").map(values => values[0]).unwrap_or("../..")
  let out = args.values
    .get("out")
    .map(values => values[0])
    .unwrap_or("\{root}/_site")
  (root, out, args.flags.get("main").unwrap_or(false))
}

///|
async fn main {
  let args = generate_command().parse() catch {
    error => {
      println("error: \{error}")
      @sys.exit(1)
      return
    }
  }
  let (root, out, main_build) = generate_options(args)
  let warnings = generate(root, out, main_build) catch {
    @model.Invalid(problems) => {
      for p in problems {
        println("error: \{p.render()}")
      }
      println("site: \{problems.length()} problem(s)")
      @sys.exit(1)
      []
    }
    error => {
      println("error: \{error}")
      @sys.exit(1)
      []
    }
  }
  for w in warnings {
    println("warning: \{w.render()}")
  }
  println("site: wrote \{out}")
}

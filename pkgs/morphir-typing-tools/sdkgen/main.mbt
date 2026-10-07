///|
fn usage() -> Unit {
  println("usage: sdkgen bootstrap <bindings.json> <out.scm>")
  println("       sdkgen generate | check")
}

///|
fn main {
  let args = @env.args()
  // The first two entries are the program path and the executable name on native.
  let rest = args[1:].to_owned()
  match rest {
    ["bootstrap", bindings, out] =>
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
    ["generate"] =>
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
    ["check"] =>
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
    _ => {
      usage()
      @sys.exit(2)
    }
  }
}

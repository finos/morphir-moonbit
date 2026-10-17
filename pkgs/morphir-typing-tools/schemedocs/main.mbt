///|
let chapters : Array[String] = [
  "pkgs/morphir-scheme/README.mbt.md", "pkgs/morphir-scheme/frontend/README.mbt.md",
  "pkgs/morphir-scheme/backend/README.mbt.md", "pkgs/morphir-scheme/pipeline/README.mbt.md",
  "pkgs/morphir-scheme/spec/README.mbt.md",
]

///|
/// Each chapter's generated files: (chapter path, generated file path, text).
fn outputs() -> Array[(String, String, String)] raise {
  let result = []
  for path in chapters {
    let dir = path[:path.length() - "/README.mbt.md".length()].to_owned()
    let text = @fs.read_file_to_string(path) catch {
      _ => raise DocError("\{path}: cannot read the chapter")
    }
    let chapter = parse_chapter(text) catch {
      DocError(message) => raise DocError("\{path}: \{message}")
    }
    result.push(
      (path, dir + "/docs_examples_test.mbt", render_examples(path, chapter)),
    )
    if render_procedures(path, chapter) is Some(text) {
      result.push((path, dir + "/docs_procedures_generated_wbtest.mbt", text))
    }
  }
  result
}

///|
fn main {
  let args = @env.args()
  // The first two entries are the program path and the executable name on native.
  let rest = args[1:].to_owned()
  try {
    match rest {
      ["generate"] =>
        for output in outputs() {
          @fs.write_string_to_file(output.1, output.2)
          println("wrote \{output.1}")
        }
      ["check"] => {
        let problems = []
        for output in outputs() {
          let current = @fs.read_file_to_string(output.1) catch { _ => "" }
          if check_message(output.0, output.1, output.2, current) is Some(d) {
            problems.push(d)
          }
        }
        if problems.is_empty() {
          println("scheme docs examples are current")
        } else {
          for p in problems {
            println(p)
          }
          println("schemedocs: run `mise run scheme-docs:generate`")
          @sys.exit(1)
        }
      }
      _ => {
        println("usage: schemedocs generate | check")
        @sys.exit(2)
      }
    }
  } catch {
    DocError(message) => {
      println("schemedocs: \{message}")
      @sys.exit(1)
    }
    e => {
      println("schemedocs: \{e}")
      @sys.exit(1)
    }
  }
}

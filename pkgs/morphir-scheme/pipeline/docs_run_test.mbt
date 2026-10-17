///|
fn run_example(files : Array[(String, String)]) -> String raise {
  @scheme.value_to_string(
    @pipeline.new_runtime().eval(files.map(f => f.1).join("\n")),
  )
}

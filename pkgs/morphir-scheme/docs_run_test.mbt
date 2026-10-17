///|
fn run_example(files : Array[(String, String)]) -> String raise {
  let source = files.map(f => f.1).join("\n")
  @scheme.value_to_string(@scheme.Runtime::new().eval(source))
}

///|
fn run_example(files : Array[(String, String)]) -> String raise {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @scheme.value_to_string(runtime.eval(files.map(f => f.1).join("\n")))
}

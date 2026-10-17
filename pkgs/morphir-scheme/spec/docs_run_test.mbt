///|
/// A package form is read and printed; any other block is a lone type in package `my/pkg`, module `m`.
fn run_example(files : Array[(String, String)]) -> String raise {
  let source = files.map(f => f.1).join("\n")
  try {
    if source.contains("(package ") {
      let (name, spec) = @spec.read_package(source)
      @spec.print_package(name, spec)
    } else {
      let t = @spec.read_type_text(
        source,
        package_name="my/pkg",
        module_path="m",
      )
      @spec.print_type(t, package_name=@ir.Path::parse("my/pkg"))
    }
  } catch {
    @spec.SpecError(line~, column~, message~) =>
      raise @scheme.Invalid("\{line}:\{column}: \{message}")
    e => raise e
  }
}

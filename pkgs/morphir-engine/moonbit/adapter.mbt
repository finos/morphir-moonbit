///|
/// Explicit application registration; importing engine core does not enable it.
pub fn register(
  engine : @engine.Engine,
  limits? : @frontend.Limits = @frontend.Limits::default(),
  unit_limits? : @data.Limits = @data.Limits::default(),
  observer? : @observe.Observer = @observe.Observer::noop(),
) -> Unit raise {
  engine.register_unit_frontend(
    "moonbit",
    [".mbt"],
    fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile(
        {
          unit_id,
          package_name: source.package_name,
          module_name: source.module_name,
          source: source.content,
        },
        limits~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    },
    profile=Some(@frontend.PROFILE),
    dependencies=Map::from_array([
      ("moonbitlang/parser", @frontend.PARSER_VERSION),
      ("moonbitlang/lexer", "0.4.0"),
    ]),
    limits=unit_limits,
  )
}

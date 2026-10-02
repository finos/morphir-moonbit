///|
/// Fully typed, SDK-free intersection for the pinned classic Rust evaluator.
pub fn rust_conformance() -> @ir.IRFile raise {
  let int = scalar("morphir/SDK:basics#int")
  let bool = scalar("morphir/SDK:basics#bool")
  let text = scalar("morphir/SDK:string#string")
  let unit = @ir.Type::Unit(ta())
  let values = Map([])
  values[@ir.Name::parse("answer")] = definition(
    int,
    @ir.Value::Literal(va(int), @ir.Literal::IntegerLiteral("42")),
  )
  for
    (name, t) in [
      ("integer", int),
      ("boolean", bool),
      ("text", text),
      ("unit", unit),
    ] {
    let item = function(
      [("input", t)],
      t,
      @ir.Value::Variable(va(t), @ir.Name::parse("input")),
    )
    values[@ir.Name::parse(name)] = {
      ..item,
      value: { ..item.value, doc: Some(""), },
    }
  }
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("rust-conformance"), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("main"),
          {
            access: @ir.Access::Public,
            value: { types: Map([]), values, doc: None, },
          },
        ),
      ]),
    }),
  )
}

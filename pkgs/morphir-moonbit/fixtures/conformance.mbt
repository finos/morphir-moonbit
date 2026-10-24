///|
/// Model expressions are distinct from the hand-calculated expectation fixture.
pub fn conformance() -> @ir.IRFile raise {
  let file = pricing()
  guard file.distribution
    is Library(package_name, dependencies, package_definition) else {
    abort("fixture")
  }
  let modules = package_definition.modules.copy()
  let int = scalar("morphir/SDK:basics#int")
  let values = Map([])
  for name in ["add", "multiply", "integer-divide", "mod-by", "remainder-by"] {
    values[@ir.Name::parse(name)] = function(
      [("first", int), ("second", int)],
      int,
      apply(
        apply(
          ref_value("morphir/SDK:basics#" + name, arrow(int, arrow(int, int))),
          variable("first"),
        ),
        variable("second"),
      ),
    )
  }
  let bool = scalar("morphir/SDK:basics#bool")
  let failing = apply(
    apply(
      ref_value(
        "morphir/SDK:basics#integer-divide",
        arrow(int, arrow(int, int)),
      ),
      lit_int("1"),
    ),
    lit_int("0"),
  )
  let failing_bool = apply(
    apply(
      ref_value("morphir/SDK:basics#equal", arrow(int, arrow(int, bool))),
      failing,
    ),
    lit_int("0"),
  )
  values[@ir.Name::parse("safe-or")] = definition(
    bool,
    apply(
      apply(
        ref_value("morphir/SDK:basics#or", arrow(bool, arrow(bool, bool))),
        @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(true)),
      ),
      failing_bool,
    ),
  )
  modules[@ir.Path::parse("arithmetic")] = {
    access: @ir.Access::Public,
    value: { types: Map([]), values, doc: None, },
  }
  @ir.IRFile::new(
    @ir.Distribution::Library(package_name, dependencies, { modules, }),
  )
}

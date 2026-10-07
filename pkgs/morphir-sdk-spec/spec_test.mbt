///|
fn sdk_module(name : String) -> @ir.ModuleSpecification {
  @sdk_spec.sdk_specification().modules
  .get(@ir.Path::parse(name) catch { _ => panic() })
  .unwrap()
}

///|
test "the SDK specification has the hand-written types" {
  let basics = sdk_module("basics")
  for t in ["int", "float", "bool", "never", "order"] {
    assert_true(
      basics.types.contains(@ir.Name::parse(t) catch { _ => panic() }),
      msg=t,
    )
  }
  for
    m in [
      "char", "string", "list", "maybe", "result", "dict", "set", "decimal", "int",
    ] {
    assert_false(sdk_module(m).types.is_empty(), msg=m)
  }
}

///|
test "the SDK specification has every value from bindings" {
  let total = @sdk_spec.sdk_specification().modules
    .values()
    .fold(init=0, (n, m) => n + m.values.length())
  assert_eq(total, 248)
  let list = sdk_module("list")
  assert_true(
    list.values.contains(@ir.Name::parse("map-2") catch { _ => panic() }),
  )
}

///|
test "the SDK specification has local-date and constructor arities" {
  let local_date = sdk_module("local-date")
  guard local_date.types.get(
      @ir.Name::parse("local-date") catch {
        _ => panic()
      },
    )
    is Some(t) else {
    fail("local-date#local-date is missing")
  }
  assert_true(t.value.body is OpaqueTypeSpecification([]))
  let maybe = sdk_module("maybe")
  guard maybe.types.get(@ir.Name::parse("maybe") catch { _ => panic() })
    is Some({ value: { body: CustomTypeSpecification(_, ctors), .. }, .. }) else {
    fail("maybe#maybe is not a custom type")
  }
  guard ctors.get(@ir.Name::parse("just") catch { _ => panic() }) is Some(args) else {
    fail("maybe#just is missing")
  }
  assert_eq(args.length(), 1)
}

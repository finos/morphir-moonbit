///|
fn var_(name : String, class? : String) -> @ir.Type {
  let constraints : Map[String, @ir.Data] = Map([])
  if class is Some(class) {
    constraints["typeclass"] = Text(class)
  }
  Variable(
    { source: None, constraints, extensions: Map([]), },
    @ir.Name::parse(name) catch {
      _ => abort("bad name")
    },
  )
}

///|
fn spec_of(
  inputs : Array[(String, @ir.Type)],
  output : @ir.Type,
) -> @ir.ValueSpecification {
  {
    annotations: [],
    inputs: inputs.map(i => {
      (@ir.Name::parse(i.0) catch { _ => abort("bad name") }, i.1)
    }),
    output,
  }
}

///|
/// The problems of comparing `add : (a, b) -> result` in bindings.json with `scm`.
fn add_problems(
  params : Array[@ir.Type],
  result : @ir.Type,
  scm : @ir.ValueSpecification,
) -> Array[String] {
  let problems : Array[String] = []
  compare_signature(
    "morphir/SDK:basics#add",
    [("a", params[0]), ("b", params[1])],
    result,
    scm,
    problems,
  )
  problems
}

///|
test "check: a dropped number class is a difference" {
  let number = var_("number", class="number")
  // sdk.scm writes `add : a -> a -> a`, which drops the class.
  let plain = var_("a")
  assert_eq(
    add_problems(
      [number, number],
      number,
      spec_of([("a", plain), ("b", plain)], plain),
    ),
    [
      "morphir/SDK:basics#add: the type of parameter `a` differs", "morphir/SDK:basics#add: the type of parameter `b` differs",
      "morphir/SDK:basics#add: the result type differs",
    ],
  )
  // Another class is a difference too.
  let comparable = var_("comparable", class="comparable")
  assert_eq(
    add_problems(
      [number, number],
      number,
      spec_of([("a", comparable), ("b", comparable)], comparable),
    ).length(),
    3,
  )
}

///|
test "check: classes match by typeclass or by name prefix" {
  let number = var_("number", class="number")
  // A renamed variable with the same class from its typeclass.
  let n = var_("n", class="number")
  assert_eq(
    add_problems([number, number], number, spec_of([("a", n), ("b", n)], n)),
    [],
  )
  // The class from the name prefix alone.
  let bare = var_("number-a")
  assert_eq(
    add_problems(
      [number, number],
      number,
      spec_of([("a", bare), ("b", bare)], bare),
    ),
    [],
  )
}

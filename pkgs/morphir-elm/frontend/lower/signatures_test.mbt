///|
let values_source = "module My.Pkg.M exposing (..)\n\ntup : ( Int, Int ) -> Int\ntup ( a, b ) =\n    a\n\nwild : Int -> Int\nwild _ =\n    1\n\npartial : Int -> Int -> Int\npartial a =\n    \\b -> a\n\n{-| Doc. -}\nunitF : () -> ()\nunitF u =\n    u\n\nplain x y =\n    x\n\nh : Int -> Int -> Int\nh a =\n    (\\x -> a)\n\ng : Int -> Int -> ( Int, Int ) -> Int\ng a =\n    \\x ( y, z ) -> a\n\nf : Int -> ( Int, Int ) -> Int\nf a (b, c) =\n    a\n"

///|
fn function_named(text : String, name : String) -> @ast.Function {
  for d in declarations(text) {
    if d.value is FunctionDeclaration(f) &&
      f.declaration.value.name.value == name {
      return f
    }
  }
  panic()
}

///|
test "inputs follow morphir-elm: variables, then leading lambdas, stopping at a pattern" {
  let names = fn(n) {
    @lower.value_inputs(function_named(values_source, n)).map(x => x.value)
  }
  assert_eq(names("tup"), [])
  assert_eq(names("wild"), [])
  assert_eq(names("partial"), ["a", "b"])
  assert_eq(names("unitF"), ["u"])
  assert_eq(names("plain"), ["x", "y"])
  assert_eq(names("h"), ["a", "x"])
  assert_eq(names("g"), ["a", "x"])
  assert_eq(names("f"), ["a"])
}

///|
test "annotated signatures split the annotation by the inputs" {
  let scope = scope_of(values_source)
  let sig = fn(n) {
    @lower.lower_value_signature(scope, function_named(values_source, n)) catch {
      _ => panic()
    }
  }
  guard sig("partial")
    is (_, IncompleteBody(inputs, Some(output), Draft, None), None) else {
    fail("partial")
  }
  assert_eq(inputs.map(i => i.0.to_canonical()), ["a", "b"])
  assert_true(bare(output) is Reference(_, _, []))
  guard sig("tup") is (_, IncompleteBody([], Some(out), _, _), _) else {
    fail("tup")
  }
  assert_true(bare(out) is Function(_, Tuple(_, _), Reference(_, _, _)))
  guard sig("h") is (_, IncompleteBody(hi, Some(ho), _, _), _) else {
    fail("h")
  }
  assert_eq(hi.map(i => i.0.to_canonical()), ["a", "x"])
  assert_true(bare(ho) is Reference(_, _, []))
  guard sig("g") is (_, IncompleteBody(gi, Some(go), _, _), _) else {
    fail("g")
  }
  assert_eq(gi.map(i => i.0.to_canonical()), ["a", "x"])
  assert_true(bare(go) is Function(_, Tuple(_, _), Reference(_, _, _)))
  guard sig("f") is (_, IncompleteBody(fi, Some(fo), _, _), _) else {
    fail("f")
  }
  assert_eq(fi.map(i => i.0.to_canonical()), ["a"])
  assert_true(bare(fo) is Function(_, Tuple(_, _), Reference(_, _, _)))
  guard sig("unitF")
    is (_, IncompleteBody([(_, Unit(_))], Some(Unit(_)), _, _), Some(" Doc. ")) else {
    fail("unitF")
  }
}

///|
test "unannotated signatures get marked placeholders" {
  let scope = scope_of(values_source)
  let result = @lower.lower_value_signature(
    scope,
    function_named(values_source, "plain"),
  ) catch {
    _ => panic()
  }
  guard result is (_, IncompleteBody(inputs, Some(output), _, _), _) else {
    fail("plain")
  }
  let types = inputs.map(i => i.1)
  types.push(output)
  assert_eq(types.length(), 3)
  for i, t in types {
    guard t is Variable(attrs, name) else { fail("variable") }
    assert_true(attrs.is_unknown())
    assert_eq(name.to_canonical(), "t-" + i.to_string())
  }
}

///|
test "a record argument pattern is refused" {
  let text = "module My.Pkg.M exposing (..)\n\nr : { x : Int } -> Int\nr { x } =\n    x\n"
  let scope = scope_of(text)
  let code = try {
    ignore(@lower.lower_value_signature(scope, function_named(text, "r")))
    "ok"
  } catch {
    @lower.LowerError(code, _, Some(_)) => code
    @lower.LowerError(_, _, None) => "no range"
  }
  assert_eq(code, "elm.unsupported")
}

///|
/// Probe fx1 (morphir-elm 2.100.0): an input is taken only while the rest of
/// the annotation is a function type. A type alias of a function type stops the
/// inputs, also inside parentheses, and the alias is the output type.
let alias_source = "module My.Pkg.M exposing (..)\n\ntype alias Handler =\n    Int -> Int\n\nf : Handler\nf x =\n    x\n\ng : Handler\ng =\n    \\y -> y\n\nh : Int -> Handler\nh a b =\n    a\n\nk : (Int -> Int)\nk x =\n    x\n\np : ( Handler )\np x =\n    x\n\nz : Int\nz =\n    1\n\ns : Int\ns a =\n    a\n"

///|
test "inputs stop where the annotation is not a function type" {
  let names = fn(n) {
    @lower.value_inputs(function_named(alias_source, n)).map(x => x.value)
  }
  assert_eq(names("f"), [])
  assert_eq(names("g"), [])
  assert_eq(names("h"), ["a"])
  assert_eq(names("k"), ["x"])
  assert_eq(names("p"), [])
  assert_eq(names("z"), [])
  assert_eq(names("s"), [])
}

///|
test "a function type alias annotation is the output type" {
  let scope = scope_of(alias_source)
  let sig = fn(n : String) -> (Array[(String, @ir.Type)], @ir.Type) raise {
    guard @lower.lower_value_signature(scope, function_named(alias_source, n))
      is (_, IncompleteBody(inputs, Some(output), Draft, None), _) else {
      fail(n)
    }
    (inputs.map(i => (i.0.to_canonical(), bare(i.1))), bare(output))
  }
  let handler = fn(t : @ir.Type) {
    t is Reference(_, name, []) && name.to_canonical().has_suffix("handler")
  }
  for n in ["f", "g", "p"] {
    let (inputs, output) = sig(n)
    assert_eq(inputs.length(), 0, msg=n)
    assert_true(handler(output), msg=n)
  }
  // h : Int -> Handler, h a b = a: one input, and the output is Handler.
  let (h_inputs, h_output) = sig("h")
  assert_eq(h_inputs.map(i => i.0), ["a"])
  assert_true(h_inputs[0].1 is Reference(_, _, []))
  assert_true(handler(h_output))
}

///|
test "a parenthesized function annotation is peeled, and a value has no inputs" {
  let scope = scope_of(alias_source)
  guard @lower.lower_value_signature(scope, function_named(alias_source, "k"))
    is (_, IncompleteBody([(x, Reference(_, _, []))], Some(output), _, _), _) else {
    fail("k")
  }
  assert_eq(x.to_canonical(), "x")
  assert_true(bare(output) is Reference(_, _, []))
  for n in ["z", "s"] {
    guard @lower.lower_value_signature(scope, function_named(alias_source, n))
      is (_, IncompleteBody([], Some(output), _, _), _) else {
      fail(n)
    }
    assert_true(bare(output) is Reference(_, _, []), msg=n)
  }
}

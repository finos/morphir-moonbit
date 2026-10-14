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
    @lower.value_inputs(function_named(values_source, n).declaration.value).map(x => {
        x.value
      },
    )
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
test "a record argument pattern and a short annotation are refused" {
  let text = "module My.Pkg.M exposing (..)\n\nr : { x : Int } -> Int\nr { x } =\n    x\n\ns : Int\ns a =\n    a\n"
  let scope = scope_of(text)
  let code = fn(n) {
    try {
      ignore(@lower.lower_value_signature(scope, function_named(text, n)))
      "ok"
    } catch {
      @lower.LowerError(code, _, Some(_)) => code
      @lower.LowerError(_, _, None) => "no range"
    }
  }
  assert_eq(code("r"), "elm.unsupported")
  assert_eq(code("s"), "elm.signature_arity")
}

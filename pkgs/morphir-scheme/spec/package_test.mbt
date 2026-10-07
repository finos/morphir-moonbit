///|
let sample : String =
  #|(package "morphir/SDK"
  #|  (module basics
  #|    (doc "Core types.")
  #|    (type bool (opaque))
  #|    (type order (custom (LT) (EQ) (GT)))
  #|    (val add ((a number) (b number)) number)
  #|    (val compare ((a comparable) (b comparable)) basics#order))
  #|  (module maybe
  #|    (type maybe (custom (just a) (nothing)) a)
  #|    (val map ((f (-> a b)) (maybe (maybe#maybe a))) (maybe#maybe b)
  #|      (doc "Map a value."))))

///|
fn package_error(text : String) -> String {
  try {
    ignore(@spec.read_package(text))
    ""
  } catch {
    @spec.SpecError(line~, column~, message~) => "\{line}:\{column} \{message}"
  }
}

///|
test "a package reads into a PackageSpecification" {
  let (name, spec) = @spec.read_package(sample)
  assert_eq(name.to_canonical(), "morphir/SDK")
  assert_eq(spec.modules.keys().map(p => p.to_canonical()).collect(), [
    "basics", "maybe",
  ])
  let basics = spec.modules
    .get(@ir.Path::parse("basics") catch { _ => panic() })
    .unwrap()
  assert_eq(basics.doc, Some("Core types."))
  let order = basics.types
    .get(@ir.Name::parse("order") catch { _ => panic() })
    .unwrap()
  guard order.value.body is CustomTypeSpecification([], ctors) else {
    fail("custom")
  }
  assert_eq(ctors.keys().map(n => n.to_canonical()).collect(), [
    "LT", "EQ", "GT",
  ])
  let add = basics.values
    .get(@ir.Name::parse("add") catch { _ => panic() })
    .unwrap()
  assert_eq(add.value.inputs.map(i => i.0.to_canonical()), ["a", "b"])
  let maybe = spec.modules
    .get(@ir.Path::parse("maybe") catch { _ => panic() })
    .unwrap()
  let map = maybe.values
    .get(@ir.Name::parse("map") catch { _ => panic() })
    .unwrap()
  assert_eq(map.doc, Some("Map a value."))
  let just = maybe.types
    .get(@ir.Name::parse("maybe") catch { _ => panic() })
    .unwrap()
  guard just.value.body is CustomTypeSpecification([param], ctors2) else {
    fail("maybe")
  }
  assert_eq(param.to_canonical(), "a")
  let args = ctors2.get(@ir.Name::parse("just") catch { _ => panic() }).unwrap()
  assert_eq(args.map(a => a.0.to_canonical()), ["arg-1"])
}

///|
test "type forms, docs and annotations read into the IR" {
  let (_, spec) = @spec.read_package(
    (
      #|(package "p"
      #|  (module m
      #|    (type id (alias int) )
      #|    (type name (doc "A name.") (opaque))
      #|    (type wrap (derived string m#from-string m#to-string))
      #|    (val f () int
      #|      (annotation acme:tags#note "x" 12 #t (1 "y"))
      #|      (annotation acme:tags#plain))))
    ),
  )
  let m = spec.modules.get(@ir.Path::parse("m") catch { _ => panic() }).unwrap()
  let nm = m.types.get(@ir.Name::parse("name") catch { _ => panic() }).unwrap()
  assert_eq(nm.doc, Some("A name."))
  let id = m.types.get(@ir.Name::parse("id") catch { _ => panic() }).unwrap()
  guard id.value.body is TypeAliasSpecification([], _) else { fail("alias") }
  let wrap = m.types
    .get(@ir.Name::parse("wrap") catch { _ => panic() })
    .unwrap()
  guard wrap.value.body is DerivedTypeSpecification([], details) else {
    fail("derived")
  }
  assert_eq(details.to_base_type.to_canonical(), "p:m#to-string")
  let f = m.values.get(@ir.Name::parse("f") catch { _ => panic() }).unwrap()
  guard f.value.annotations
    is [
      Structured(
        _,
        [
          Positional(Literal(_, StringLiteral("x"))),
          Positional(Literal(_, IntegerLiteral("12"))),
          Positional(Literal(_, BoolLiteral(true))),
          Positional(List(_, [_, _])),
        ]
      ),
      Compact(_, None),
    ] else {
    fail("annotations")
  }
}

///|
test "errors name the line and column" {
  let bad =
    #|(package "p"
    #|  (module m
    #|    (val x (a) basics#int)))
  assert_eq(package_error(bad), "3:12 a parameter is (name type)")
}

///|
test "a duplicate module is refused" {
  assert_eq(
    package_error("(package \"p\" (module m) (module m))"),
    "1:25 duplicate module `m`",
  )
}

///|
test "a duplicate value is refused" {
  assert_eq(
    package_error("(package \"p\" (module m (val x () int) (val x () int)))"),
    "1:39 duplicate value `x`",
  )
}

///|
test "a doc that is not first is refused" {
  assert_eq(
    package_error("(package \"p\" (module m (type t (opaque)) (doc \"late\")))"),
    "1:42 a doc must be the first item",
  )
}

///|
test "an unknown item form is refused" {
  assert_eq(
    package_error("(package \"p\" (module m (function f)))"),
    "1:24 unknown item form `function`",
  )
}

///|
test "a reserved head is refused" {
  assert_eq(
    package_error("(package \"p\" (module m (define! x)))"),
    "1:24 `define!` is reserved for macros",
  )
}

///|
test "a missing package name is refused" {
  assert_eq(
    package_error("(package (module m))"),
    "1:10 expected a package name",
  )
  assert_eq(
    package_error("(module m)"),
    "1:1 expected (package \"name\" module...)",
  )
}

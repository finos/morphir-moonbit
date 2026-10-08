///|
fn sample_text() -> String {
  (
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
  )
}

///|
test "printing then reading gives the same specification and the same text" {
  let (name, spec) = @spec.read_package(sample_text())
  let printed = @spec.print_package(name, spec)
  let (name2, spec2) = @spec.read_package(printed)
  assert_eq(name2, name)
  assert_eq(spec2, spec)
  assert_eq(@spec.print_package(name2, spec2), printed)
}

///|
test "the printed layout is canonical" {
  let (name, spec) = @spec.read_package(
    (
      #|(package "p" (module m (doc "D") (type t (doc "T") (alias (tuple a b)) a b)
      #|  (val f ((x a)) a (doc "F") (annotation q:r#s "x" (1 2)))))
    ),
  )
  assert_eq(
    @spec.print_package(name, spec),
    (
      #|(package "p"
      #|  (module m
      #|    (doc "D")
      #|    (type t (doc "T") (alias (tuple a b)) a b)
      #|    (val f ((x a)) a
      #|      (doc "F")
      #|      (annotation q:r#s "x" (1 2)))))
    ),
  )
}

///|
test "the printer writes flat curried functions and same-package references" {
  let t = @spec.read_type_text(
    "(-> a (-> b c))",
    package_name="morphir/SDK",
    module_path="basics",
  )
  assert_eq(
    @spec.print_type(
      t,
      package_name=@ir.Path::parse("morphir/SDK") catch { _ => panic() },
    ),
    "(-> a b c)",
  )
  let r = @spec.read_type_text(
    "(tuple (list#list a) acme/app:money#money)",
    package_name="morphir/SDK",
    module_path="basics",
  )
  assert_eq(
    @spec.print_type(
      r,
      package_name=@ir.Path::parse("morphir/SDK") catch { _ => panic() },
    ),
    "(tuple (list#list a) acme/app:money#money)",
  )
}

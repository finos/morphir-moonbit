///|
/// Tests for PackageName type
test "PackageName::from_string basic" {
  let package_name = PackageName::from_string("Morphir.SDK")
  inspect(
    package_name.to_string(Name::to_title_case, "."),
    content="Morphir.SDK",
  )
}

///|
test "PackageName::from_path and to_path roundtrip" {
  let path = Path::from_string("Morphir.SDK")
  let package_name = PackageName::from_path(path)
  inspect(package_name.to_path().to_list().length(), content="2")
}

///|
test "PackageName::to_string with different conventions" {
  // Note: "SDK" is parsed as S, D, K (single letters) which become "SDK" abbreviation
  let package_name = PackageName::from_string("Morphir.SDK")
  inspect(
    package_name.to_string(Name::to_snake_case, "/"),
    content="morphir/SDK",
  )
}

///|
test "PackageName::from_list and to_list" {
  let names = @list.from_array([
    Name::from_string("foo"),
    Name::from_string("bar"),
  ])
  let package_name = PackageName::from_list(names)
  inspect(package_name.to_list().length(), content="2")
  inspect(package_name.to_string(Name::to_title_case, "."), content="Foo.Bar")
}

///|
test "PackageName::empty and is_empty" {
  let empty = PackageName::empty()
  inspect(empty.is_empty(), content="true")
  inspect(PackageName::from_string("Foo").is_empty(), content="false")
}

///|
test "PackageName and ModuleName are distinct types" {
  // This test verifies type safety - can't accidentally mix them
  let pkg = PackageName::from_string("MyPackage")
  let mod = ModuleName::from_string("MyModule")
  // Both can be converted to paths
  let pkg_path = pkg.to_path()
  let mod_path = mod.to_path()
  inspect(pkg_path.to_string(Name::to_title_case, "."), content="MyPackage")
  inspect(mod_path.to_string(Name::to_title_case, "."), content="MyModule")
}

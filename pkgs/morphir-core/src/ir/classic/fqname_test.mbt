///| Tests for FQName type

test "FQName::new basic" {
  let fqname = FQName::new(
    PackageName::from_string("Morphir.SDK"),
    ModuleName::from_string("Basics"),
    Name::from_string("int"),
  )
  inspect(fqname.to_string(), content="Morphir.SDK:Basics:int")
}

test "FQName::fqn convenience constructor" {
  let fqname = FQName::fqn("Morphir.SDK", "Basics", "int")
  inspect(fqname.to_string(), content="Morphir.SDK:Basics:int")
}

test "FQName::from_qname" {
  let qname = QName::from_name(Path::from_string("Bar"), Name::from_string("baz"))
  let fqname = FQName::from_qname(PackageName::from_string("Foo"), qname)
  inspect(fqname.to_string(), content="Foo:Bar:baz")
}

test "FQName::get_package_name" {
  let fqname = FQName::new(
    PackageName::from_string("Foo"),
    ModuleName::from_string("Bar"),
    Name::from_string("baz"),
  )
  inspect(fqname.get_package_name().to_string(Name::to_title_case, "."), content="Foo")
}

test "FQName::get_package_path (convenience)" {
  let fqname = FQName::new(
    PackageName::from_string("Foo"),
    ModuleName::from_string("Bar"),
    Name::from_string("baz"),
  )
  inspect(fqname.get_package_path().to_string(Name::to_title_case, "."), content="Foo")
}

test "FQName::get_module_name" {
  let fqname = FQName::new(
    PackageName::from_string("Foo"),
    ModuleName::from_string("Bar"),
    Name::from_string("baz"),
  )
  inspect(fqname.get_module_name().to_string(Name::to_title_case, "."), content="Bar")
}

test "FQName::get_module_path (convenience)" {
  let fqname = FQName::new(
    PackageName::from_string("Foo"),
    ModuleName::from_string("Bar"),
    Name::from_string("baz"),
  )
  inspect(fqname.get_module_path().to_string(Name::to_title_case, "."), content="Bar")
}

test "FQName::get_local_name" {
  let fqname = FQName::new(
    PackageName::from_string("Foo"),
    ModuleName::from_string("Bar"),
    Name::from_string("bazQux"),
  )
  inspect(fqname.get_local_name().to_camel_case(), content="bazQux")
}

test "FQName::to_string format" {
  // Package and module use TitleCase with ".", local name uses camelCase
  let fqname = FQName::new(
    PackageName::from_string("morphir.sdk"),
    ModuleName::from_string("basics"),
    Name::from_string("to_string"),
  )
  inspect(fqname.to_string(), content="Morphir.Sdk:Basics:toString")
}

test "FQName::from_string valid" {
  let fqname = FQName::from_string("Foo:Bar:baz", ":")
  inspect(fqname.to_string(), content="Foo:Bar:baz")
}

test "FQName::from_string_strict valid" {
  match FQName::from_string_strict("Foo:Bar:baz", ":") {
    Ok(fqname) => inspect(fqname.to_string(), content="Foo:Bar:baz")
    Err(_) => fail("Expected Ok")
  }
}

test "FQName::from_string_strict invalid" {
  match FQName::from_string_strict("invalid", ":") {
    Ok(_) => fail("Expected Err")
    Err(msg) => inspect(msg.length() > 0, content="true")
  }
}

test "FQName::to_qname" {
  let fqname = FQName::new(
    PackageName::from_string("Foo"),
    ModuleName::from_string("Bar"),
    Name::from_string("baz"),
  )
  inspect(fqname.to_qname().to_string(), content="Bar:baz")
}

test "FQName with multi-segment paths" {
  let fqname = FQName::fqn("Morphir.SDK.Core", "List.Operations", "map")
  inspect(fqname.to_string(), content="Morphir.SDK.Core:List.Operations:map")
}

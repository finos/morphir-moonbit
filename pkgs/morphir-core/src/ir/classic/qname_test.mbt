///| Tests for QName type

test "QName::new basic" {
  let qname = QName::new(
    ModuleName::from_string("Morphir.SDK"),
    Name::from_string("basics"),
  )
  inspect(qname.to_string(), content="Morphir.SDK:basics")
}

test "QName::from_name with Path (convenience)" {
  let qname = QName::from_name(
    Path::from_string("Morphir.SDK"),
    Name::from_string("basics"),
  )
  inspect(qname.to_string(), content="Morphir.SDK:basics")
}

test "QName::from_tuple and to_tuple roundtrip" {
  let module_name = ModuleName::from_string("Foo.Bar")
  let name = Name::from_string("baz")
  let qname = QName::from_tuple((module_name, name))
  let (result_mod, result_name) = qname.to_tuple()
  inspect(result_mod.to_string(Name::to_title_case, "."), content="Foo.Bar")
  inspect(result_name.to_camel_case(), content="baz")
}

test "QName::from_path_tuple with Path (convenience)" {
  let path = Path::from_string("Foo.Bar")
  let name = Name::from_string("baz")
  let qname = QName::from_path_tuple((path, name))
  let (result_path, result_name) = qname.to_path_tuple()
  inspect(result_path.to_string(Name::to_title_case, "."), content="Foo.Bar")
  inspect(result_name.to_camel_case(), content="baz")
}

test "QName::get_module_name" {
  let qname = QName::new(
    ModuleName::from_string("Foo.Bar"),
    Name::from_string("baz"),
  )
  inspect(qname.get_module_name().to_string(Name::to_title_case, "."), content="Foo.Bar")
}

test "QName::get_module_path (convenience)" {
  let qname = QName::from_name(
    Path::from_string("Foo.Bar"),
    Name::from_string("baz"),
  )
  inspect(qname.get_module_path().to_string(Name::to_title_case, "."), content="Foo.Bar")
}

test "QName::get_local_name" {
  let qname = QName::from_name(
    Path::from_string("Foo.Bar"),
    Name::from_string("bazQux"),
  )
  inspect(qname.get_local_name().to_camel_case(), content="bazQux")
}

test "QName::to_string format" {
  // Module uses TitleCase with ".", local name uses camelCase
  let qname = QName::from_name(
    Path::from_string("foo.bar.baz"),
    Name::from_string("a_name"),
  )
  inspect(qname.to_string(), content="Foo.Bar.Baz:aName")
}

test "QName::from_string valid" {
  match QName::from_string("Foo.Bar:bazQux") {
    Some(qname) => inspect(qname.to_string(), content="Foo.Bar:bazQux")
    None => fail("Expected Some")
  }
}

test "QName::from_string invalid" {
  match QName::from_string("invalid") {
    Some(_) => fail("Expected None")
    None => ()
  }
}

test "QName::from_string with empty module" {
  match QName::from_string(":localName") {
    Some(qname) => {
      inspect(qname.get_module_name().is_empty(), content="true")
      inspect(qname.get_local_name().to_camel_case(), content="localName")
    }
    None => fail("Expected Some")
  }
}

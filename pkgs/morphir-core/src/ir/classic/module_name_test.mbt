///| Tests for ModuleName type

test "ModuleName::from_string basic" {
  let module_name = ModuleName::from_string("Morphir.SDK.Basics")
  inspect(module_name.to_string(Name::to_title_case, "."), content="Morphir.SDK.Basics")
}

test "ModuleName::from_path and to_path roundtrip" {
  let path = Path::from_string("Morphir.SDK")
  let module_name = ModuleName::from_path(path)
  inspect(module_name.to_path().to_list().length(), content="2")
}

test "ModuleName::to_string with different conventions" {
  // Note: "SDK" is parsed as S, D, K (single letters) which become "SDK" abbreviation
  let module_name = ModuleName::from_string("Morphir.SDK.Basics")
  inspect(module_name.to_string(Name::to_snake_case, "/"), content="morphir/SDK/basics")
}

test "ModuleName::from_list and to_list" {
  let names = @list.from_array([Name::from_string("foo"), Name::from_string("bar")])
  let module_name = ModuleName::from_list(names)
  inspect(module_name.to_list().length(), content="2")
  inspect(module_name.to_string(Name::to_title_case, "."), content="Foo.Bar")
}

test "ModuleName::empty and is_empty" {
  let empty = ModuleName::empty()
  inspect(empty.is_empty(), content="true")
  inspect(ModuleName::from_string("Foo").is_empty(), content="false")
}

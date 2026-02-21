///| Tests for Path type

test "Path::from_string with dot separator" {
  let path = Path::from_string("fooBar.Baz")
  inspect(path.to_string(Name::to_title_case, "."), content="FooBar.Baz")
}

test "Path::from_string with slash separator" {
  let path = Path::from_string("foo bar/baz")
  inspect(path.to_string(Name::to_snake_case, "/"), content="foo_bar/baz")
}

test "Path::from_list and to_list roundtrip" {
  let names = @list.from_array([
    Name::from_list(@list.from_array(["foo", "bar"])),
    Name::from_list(@list.from_array(["baz"])),
  ])
  let path = Path::from_list(names)
  inspect(path.to_list().length(), content="2")
}

test "Path::to_string with title case and dot" {
  let path = Path::from_list(
    @list.from_array([
      Name::from_list(@list.from_array(["foo", "bar"])),
      Name::from_list(@list.from_array(["baz"])),
    ]),
  )
  inspect(path.to_string(Name::to_title_case, "."), content="FooBar.Baz")
}

test "Path::to_string with snake case and slash" {
  let path = Path::from_list(
    @list.from_array([
      Name::from_list(@list.from_array(["foo", "bar"])),
      Name::from_list(@list.from_array(["baz"])),
    ]),
  )
  inspect(path.to_string(Name::to_snake_case, "/"), content="foo_bar/baz")
}

test "Path::is_prefix_of with valid prefix" {
  let path = Path::from_string("foo.bar")
  let prefix = Path::from_string("foo")
  inspect(path.is_prefix_of(prefix), content="true")
}

test "Path::is_prefix_of with invalid prefix" {
  let path = Path::from_string("foo")
  let prefix = Path::from_string("foo.bar")
  inspect(path.is_prefix_of(prefix), content="false")
}

test "Path::is_prefix_of with equal paths" {
  let path = Path::from_string("foo.bar")
  let prefix = Path::from_string("foo.bar")
  inspect(path.is_prefix_of(prefix), content="true")
}

test "Path::empty and is_empty" {
  let path = Path::empty()
  inspect(path.is_empty(), content="true")
  inspect(Path::from_string("foo").is_empty(), content="false")
}

///| A PackageName is a path that identifies a package.
///|
///| In Elm this is defined as `type alias PackageName = Path`.
///| Using a struct tuple provides type safety - you can't accidentally
///| use a PackageName where a ModuleName is expected.
///|
///| ## Examples
///| ```mbt check
///| test {
///|   let package_name = PackageName::from_string("Morphir.SDK")
///|   inspect(package_name.to_string(Name::to_title_case, "."), content="Morphir.SDK")
///| }
///| ```
pub struct PackageName(Path)

///| Creates a PackageName from a Path.
///|
///| ```mbt check
///| test {
///|   let path = Path::from_string("Morphir.SDK")
///|   let package_name = PackageName::from_path(path)
///|   inspect(package_name.to_string(Name::to_title_case, "."), content="Morphir.SDK")
///| }
///| ```
pub fn PackageName::from_path(path : Path) -> PackageName {
  PackageName(path)
}

///| Converts a PackageName to its underlying Path.
///|
///| ```mbt check
///| test {
///|   let package_name = PackageName::from_string("Foo.Bar")
///|   let path = package_name.to_path()
///|   inspect(path.to_list().length(), content="2")
///| }
///| ```
pub fn PackageName::to_path(self : PackageName) -> Path {
  let PackageName(path) = self
  path
}

///| Creates a PackageName from a string.
///| Delegates to Path::from_string for parsing.
///|
///| ```mbt check
///| test {
///|   let package_name = PackageName::from_string("foo.bar.baz")
///|   inspect(package_name.to_string(Name::to_title_case, "."), content="Foo.Bar.Baz")
///| }
///| ```
pub fn PackageName::from_string(input : String) -> PackageName {
  PackageName(Path::from_string(input))
}

///| Converts a PackageName to a string using the specified naming convention and separator.
///|
///| ```mbt check
///| test {
///|   let package_name = PackageName::from_string("Morphir.SDK")
///|   inspect(package_name.to_string(Name::to_snake_case, "/"), content="morphir/sdk")
///| }
///| ```
pub fn PackageName::to_string(
  self : PackageName,
  name_to_string : (Name) -> String,
  sep : String
) -> String {
  let PackageName(path) = self
  path.to_string(name_to_string, sep)
}

///| Creates a PackageName from a list of Names.
///|
///| ```mbt check
///| test {
///|   let names = @list.from_array([Name::from_string("foo"), Name::from_string("bar")])
///|   let package_name = PackageName::from_list(names)
///|   inspect(package_name.to_string(Name::to_title_case, "."), content="Foo.Bar")
///| }
///| ```
pub fn PackageName::from_list(names : @list.List[Name]) -> PackageName {
  PackageName(Path::from_list(names))
}

///| Converts a PackageName to a list of Names.
///|
///| ```mbt check
///| test {
///|   let package_name = PackageName::from_string("Foo.Bar")
///|   inspect(package_name.to_list().length(), content="2")
///| }
///| ```
pub fn PackageName::to_list(self : PackageName) -> @list.List[Name] {
  let PackageName(path) = self
  path.to_list()
}

///| Creates an empty PackageName.
pub fn PackageName::empty() -> PackageName {
  PackageName(Path::empty())
}

///| Checks if a PackageName is empty.
pub fn PackageName::is_empty(self : PackageName) -> Bool {
  let PackageName(path) = self
  path.is_empty()
}

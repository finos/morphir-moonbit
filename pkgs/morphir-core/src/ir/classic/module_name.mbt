///| A ModuleName is a path that identifies a module within a package.

///|

///| In Elm this is defined as `type alias ModuleName = Path`.

///| Using a struct tuple provides type safety - you can't accidentally

///| use a ModuleName where a PackageName is expected.

///|

///| ## Examples

///| ```mbt check

///| test {

///|   let module_name = ModuleName::from_string("Morphir.SDK.Basics")

///|   inspect(module_name.to_string(Name::to_title_case, "."), content="Morphir.SDK.Basics")

///| }

///|
/// ```
pub struct ModuleName(Path)

///| Creates a ModuleName from a Path.

///|

///| ```mbt check

///| test {

///|   let path = Path::from_string("Morphir.SDK")

///|   let module_name = ModuleName::from_path(path)

///|   inspect(module_name.to_string(Name::to_title_case, "."), content="Morphir.SDK")

///| }

///|
/// ```
pub fn ModuleName::from_path(path : Path) -> ModuleName {
  ModuleName(path)
}

///| Converts a ModuleName to its underlying Path.

///|

///| ```mbt check

///| test {

///|   let module_name = ModuleName::from_string("Foo.Bar")

///|   let path = module_name.to_path()

///|   inspect(path.to_list().length(), content="2")

///| }

///|
/// ```
pub fn ModuleName::to_path(self : ModuleName) -> Path {
  let ModuleName(path) = self
  path
}

///| Creates a ModuleName from a string.

///| Delegates to Path::from_string for parsing.

///|

///| ```mbt check

///| test {

///|   let module_name = ModuleName::from_string("foo.bar.baz")

///|   inspect(module_name.to_string(Name::to_title_case, "."), content="Foo.Bar.Baz")

///| }

///|
/// ```
pub fn ModuleName::from_string(input : String) -> ModuleName {
  ModuleName(Path::from_string(input))
}

///| Converts a ModuleName to a string using the specified naming convention and separator.

///|

///| ```mbt check

///| test {

///|   let module_name = ModuleName::from_string("Morphir.SDK.Basics")

///|   inspect(module_name.to_string(Name::to_snake_case, "/"), content="morphir/sdk/basics")

///| }

///|
/// ```
pub fn ModuleName::to_string(
  self : ModuleName,
  name_to_string : (Name) -> String,
  sep : String,
) -> String {
  let ModuleName(path) = self
  path.to_string(name_to_string, sep)
}

///| Creates a ModuleName from a list of Names.

///|

///| ```mbt check

///| test {

///|   let names = @list.from_array([Name::from_string("foo"), Name::from_string("bar")])

///|   let module_name = ModuleName::from_list(names)

///|   inspect(module_name.to_string(Name::to_title_case, "."), content="Foo.Bar")

///| }

///|
/// ```
pub fn ModuleName::from_list(names : @list.List[Name]) -> ModuleName {
  ModuleName(Path::from_list(names))
}

///| Converts a ModuleName to a list of Names.

///|

///| ```mbt check

///| test {

///|   let module_name = ModuleName::from_string("Foo.Bar")

///|   inspect(module_name.to_list().length(), content="2")

///| }

///|
/// ```
pub fn ModuleName::to_list(self : ModuleName) -> @list.List[Name] {
  let ModuleName(path) = self
  path.to_list()
}

///|
/// Creates an empty ModuleName.
pub fn ModuleName::empty() -> ModuleName {
  ModuleName(Path::empty())
}

///|
/// Checks if a ModuleName is empty.
pub fn ModuleName::is_empty(self : ModuleName) -> Bool {
  let ModuleName(path) = self
  path.is_empty()
}

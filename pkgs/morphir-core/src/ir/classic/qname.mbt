///| A QName (Qualified Name) is a combination of a module name and a local name.
///|
///| In Elm this is defined as `type QName = QName Path Name`.
///| This struct uses the type-safe ModuleName wrapper for better type safety
///| while maintaining the same semantics.
///|
///| ## Examples
///| ```mbt check
///| test {
///|   let qname = QName::new(
///|     ModuleName::from_string("Morphir.SDK"),
///|     Name::from_string("basics")
///|   )
///|   inspect(qname.to_string(), content="Morphir.SDK:basics")
///| }
///| ```
pub struct QName {
  module_name : ModuleName
  local_name : Name
}

///| Creates a QName from a module name and a local name.
///|
///| ```mbt check
///| test {
///|   let qname = QName::new(
///|     ModuleName::from_string("Foo.Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(qname.to_string(), content="Foo.Bar:baz")
///| }
///| ```
pub fn QName::new(module_name : ModuleName, local_name : Name) -> QName {
  { module_name, local_name }
}

///| Creates a QName from a module path and a local name.
///| This is a convenience constructor that accepts a Path directly.
///|
///| ```mbt check
///| test {
///|   let qname = QName::from_name(
///|     Path::from_string("Foo.Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(qname.to_string(), content="Foo.Bar:baz")
///| }
///| ```
pub fn QName::from_name(module_path : Path, local_name : Name) -> QName {
  { module_name: ModuleName::from_path(module_path), local_name }
}

///| Creates a QName from a tuple of (ModuleName, Name).
///|
///| ```mbt check
///| test {
///|   let qname = QName::from_tuple((
///|     ModuleName::from_string("Foo.Bar"),
///|     Name::from_string("baz")
///|   ))
///|   inspect(qname.to_string(), content="Foo.Bar:baz")
///| }
///| ```
pub fn QName::from_tuple(tuple : (ModuleName, Name)) -> QName {
  let (module_name, local_name) = tuple
  { module_name, local_name }
}

///| Creates a QName from a tuple of (Path, Name).
///| This is a convenience constructor that accepts a Path directly.
///|
///| ```mbt check
///| test {
///|   let qname = QName::from_path_tuple((
///|     Path::from_string("Foo.Bar"),
///|     Name::from_string("baz")
///|   ))
///|   inspect(qname.to_string(), content="Foo.Bar:baz")
///| }
///| ```
pub fn QName::from_path_tuple(tuple : (Path, Name)) -> QName {
  let (path, local_name) = tuple
  { module_name: ModuleName::from_path(path), local_name }
}

///| Converts a QName to a tuple of (ModuleName, Name).
///|
///| ```mbt check
///| test {
///|   let qname = QName::new(
///|     ModuleName::from_string("Foo.Bar"),
///|     Name::from_string("baz")
///|   )
///|   let (mod_name, name) = qname.to_tuple()
///|   inspect(mod_name.to_list().length(), content="2")
///| }
///| ```
pub fn QName::to_tuple(self : QName) -> (ModuleName, Name) {
  (self.module_name, self.local_name)
}

///| Converts a QName to a tuple of (Path, Name).
///| This is a convenience method for compatibility with code expecting Path.
///|
///| ```mbt check
///| test {
///|   let qname = QName::new(
///|     ModuleName::from_string("Foo.Bar"),
///|     Name::from_string("baz")
///|   )
///|   let (path, name) = qname.to_path_tuple()
///|   inspect(path.to_list().length(), content="2")
///| }
///| ```
pub fn QName::to_path_tuple(self : QName) -> (Path, Name) {
  (self.module_name.to_path(), self.local_name)
}

///| Gets the module name part of a qualified name.
///|
///| ```mbt check
///| test {
///|   let qname = QName::new(
///|     ModuleName::from_string("Foo.Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(qname.get_module_name().to_string(Name::to_title_case, "."), content="Foo.Bar")
///| }
///| ```
pub fn QName::get_module_name(self : QName) -> ModuleName {
  self.module_name
}

///| Gets the module path part of a qualified name.
///| This is a convenience method that extracts the underlying Path.
///|
///| ```mbt check
///| test {
///|   let qname = QName::new(
///|     ModuleName::from_string("Foo.Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(qname.get_module_path().to_string(Name::to_title_case, "."), content="Foo.Bar")
///| }
///| ```
pub fn QName::get_module_path(self : QName) -> Path {
  self.module_name.to_path()
}

///| Gets the local name part of a qualified name.
///|
///| ```mbt check
///| test {
///|   let qname = QName::new(
///|     ModuleName::from_string("Foo.Bar"),
///|     Name::from_string("bazQux")
///|   )
///|   inspect(qname.get_local_name().to_camel_case(), content="bazQux")
///| }
///| ```
pub fn QName::get_local_name(self : QName) -> Name {
  self.local_name
}

///| Converts a QName to a string using ":" as the separator between module and local names.
///| Module name uses TitleCase with "." separator, local name uses camelCase.
///|
///| ```mbt check
///| test {
///|   let qname = QName::new(
///|     ModuleName::from_string("foo.bar.baz"),
///|     Name::from_string("a_name")
///|   )
///|   inspect(qname.to_string(), content="Foo.Bar.Baz:aName")
///| }
///| ```
pub fn QName::to_string(self : QName) -> String {
  let module_str = self.module_name.to_string(Name::to_title_case, ".")
  let local_str = self.local_name.to_camel_case()
  if module_str.is_empty() {
    local_str
  } else {
    module_str + ":" + local_str
  }
}

///| Parses a string into a QName using ":" as the separator between module and local names.
///| Returns None if the string doesn't contain exactly one ":".
///|
///| ```mbt check
///| test {
///|   match QName::from_string("Foo.Bar:bazQux") {
///|     Some(qname) => inspect(qname.to_string(), content="Foo.Bar:bazQux")
///|     None => fail!("Expected Some")
///|   }
///| }
///| ```
///|
///| ```mbt check
///| test {
///|   match QName::from_string("invalid") {
///|     Some(_) => fail!("Expected None")
///|     None => ()
///|   }
///| }
///| ```
pub fn QName::from_string(input : String) -> QName? {
  let parts = split_on_colon(input)
  if parts.length() == 2 {
    let module_str = parts[0]
    let local_str = parts[1]
    Some(
      QName::new(
        ModuleName::from_string(module_str),
        Name::from_string(local_str),
      ),
    )
  } else {
    None
  }
}

///| Internal: Split a string on the first colon.
fn split_on_colon(input : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  let chars = input.to_array()
  let mut found_colon = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == ':' && not(found_colon) {
      result.push(current.to_string())
      current.reset()
      found_colon = true
    } else {
      current.write_char(c)
    }
  }
  result.push(current.to_string())
  result
}

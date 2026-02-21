///| An FQName (Fully Qualified Name) is a combination of a package name,
///| a module name, and a local name.
///|
///| In Elm this is defined as `type alias FQName = (Path, Path, Name)`.
///| This struct uses the type-safe PackageName and ModuleName wrappers
///| for better type safety while maintaining the same semantics.
///|
///| ## Examples
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("Morphir.SDK"),
///|     ModuleName::from_string("Basics"),
///|     Name::from_string("int")
///|   )
///|   inspect(fqname.to_string(), content="Morphir.SDK:Basics:int")
///| }
///| ```
pub struct FQName {
  package_name : PackageName
  module_name : ModuleName
  local_name : Name
}

///| Creates a FQName from package name, module name, and local name.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("Foo"),
///|     ModuleName::from_string("Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(fqname.to_string(), content="Foo:Bar:baz")
///| }
///| ```
pub fn FQName::new(
  package_name : PackageName,
  module_name : ModuleName,
  local_name : Name
) -> FQName {
  { package_name, module_name, local_name }
}

///| Creates a FQName from a QName and a package name.
///|
///| ```mbt check
///| test {
///|   let qname = QName::from_name(Path::from_string("Bar"), Name::from_string("baz"))
///|   let fqname = FQName::from_qname(PackageName::from_string("Foo"), qname)
///|   inspect(fqname.to_string(), content="Foo:Bar:baz")
///| }
///| ```
pub fn FQName::from_qname(package_name : PackageName, qname : QName) -> FQName {
  {
    package_name,
    module_name: ModuleName::from_path(qname.get_module_path()),
    local_name: qname.get_local_name(),
  }
}

///| Gets the package name part of a fully-qualified name.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("Foo"),
///|     ModuleName::from_string("Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(fqname.get_package_name().to_string(Name::to_title_case, "."), content="Foo")
///| }
///| ```
pub fn FQName::get_package_name(self : FQName) -> PackageName {
  self.package_name
}

///| Gets the package path part of a fully-qualified name.
///| This is a convenience method that extracts the underlying Path.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("Foo"),
///|     ModuleName::from_string("Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(fqname.get_package_path().to_string(Name::to_title_case, "."), content="Foo")
///| }
///| ```
pub fn FQName::get_package_path(self : FQName) -> Path {
  self.package_name.to_path()
}

///| Gets the module name part of a fully-qualified name.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("Foo"),
///|     ModuleName::from_string("Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(fqname.get_module_name().to_string(Name::to_title_case, "."), content="Bar")
///| }
///| ```
pub fn FQName::get_module_name(self : FQName) -> ModuleName {
  self.module_name
}

///| Gets the module path part of a fully-qualified name.
///| This is a convenience method that extracts the underlying Path.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("Foo"),
///|     ModuleName::from_string("Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(fqname.get_module_path().to_string(Name::to_title_case, "."), content="Bar")
///| }
///| ```
pub fn FQName::get_module_path(self : FQName) -> Path {
  self.module_name.to_path()
}

///| Gets the local name part of a fully-qualified name.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("Foo"),
///|     ModuleName::from_string("Bar"),
///|     Name::from_string("bazQux")
///|   )
///|   inspect(fqname.get_local_name().to_camel_case(), content="bazQux")
///| }
///| ```
pub fn FQName::get_local_name(self : FQName) -> Name {
  self.local_name
}

///| Convenience function to create a FQName from 3 strings.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::fqn("Morphir.SDK", "Basics", "int")
///|   inspect(fqname.to_string(), content="Morphir.SDK:Basics:int")
///| }
///| ```
pub fn FQName::fqn(
  package_name : String,
  module_name : String,
  local_name : String
) -> FQName {
  FQName::new(
    PackageName::from_string(package_name),
    ModuleName::from_string(module_name),
    Name::from_string(local_name),
  )
}

///| Converts a FQName to a string using ":" as the separator.
///| All paths use TitleCase with "." separator, local name uses camelCase.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("morphir.sdk"),
///|     ModuleName::from_string("basics"),
///|     Name::from_string("to_string")
///|   )
///|   inspect(fqname.to_string(), content="Morphir.Sdk:Basics:toString")
///| }
///| ```
pub fn FQName::to_string(self : FQName) -> String {
  let pkg_str = self.package_name.to_string(Name::to_title_case, ".")
  let mod_str = self.module_name.to_string(Name::to_title_case, ".")
  let local_str = self.local_name.to_camel_case()
  pkg_str + ":" + mod_str + ":" + local_str
}

///| Parses a string into a FQName using the specified separator.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::from_string("Foo:Bar:baz", ":")
///|   inspect(fqname.to_string(), content="Foo:Bar:baz")
///| }
///| ```
pub fn FQName::from_string(input : String, separator : String) -> FQName {
  let parts = split_on_separator(input, separator)
  if parts.length() == 3 {
    FQName::new(
      PackageName::from_string(parts[0]),
      ModuleName::from_string(parts[1]),
      Name::from_string(parts[2]),
    )
  } else {
    // Return empty FQName for malformed input (matches Elm behavior)
    FQName::new(
      PackageName::from_list(@list.from_array([Name::from_list(@list.from_array([]))])),
      ModuleName::empty(),
      Name::from_list(@list.from_array([])),
    )
  }
}

///| Parses a string into a FQName, returning an error for malformed input.
///|
///| ```mbt check
///| test {
///|   match FQName::from_string_strict("Foo:Bar:baz", ":") {
///|     Ok(fqname) => inspect(fqname.to_string(), content="Foo:Bar:baz")
///|     Err(_) => fail!("Expected Ok")
///|   }
///| }
///| ```
///|
///| ```mbt check
///| test {
///|   match FQName::from_string_strict("invalid", ":") {
///|     Ok(_) => fail!("Expected Err")
///|     Err(msg) => inspect(msg.length() > 0, content="true")
///|   }
///| }
///| ```
pub fn FQName::from_string_strict(
  input : String,
  separator : String
) -> Result[FQName, String] {
  let parts = split_on_separator(input, separator)
  if parts.length() == 3 {
    Ok(
      FQName::new(
        PackageName::from_string(parts[0]),
        ModuleName::from_string(parts[1]),
        Name::from_string(parts[2]),
      ),
    )
  } else {
    Err(
      "A fully-qualified name needs to have 3 parts: a package name, a module name and a local name. I found " +
      parts.length().to_string() +
      " parts by splitting '" +
      input +
      "' using '" +
      separator +
      "' as the separator.",
    )
  }
}

///| Internal: Split a string on a separator.
fn split_on_separator(input : String, separator : String) -> Array[String] {
  if separator.is_empty() {
    return [input]
  }
  let result : Array[String] = []
  let current = StringBuilder::new()
  let input_chars = input.to_array()
  let sep_chars = separator.to_array()
  let sep_len = sep_chars.length()
  let mut i = 0
  while i < input_chars.length() {
    // Check if separator matches at current position
    let mut matches = true
    if i + sep_len <= input_chars.length() {
      for j = 0; j < sep_len; j = j + 1 {
        if input_chars[i + j] != sep_chars[j] {
          matches = false
          break
        }
      }
    } else {
      matches = false
    }
    if matches {
      result.push(current.to_string())
      current.reset()
      i = i + sep_len
    } else {
      current.write_char(input_chars[i])
      i = i + 1
    }
  }
  result.push(current.to_string())
  result
}

///| Converts an FQName to a QName by dropping the package name.
///|
///| ```mbt check
///| test {
///|   let fqname = FQName::new(
///|     PackageName::from_string("Foo"),
///|     ModuleName::from_string("Bar"),
///|     Name::from_string("baz")
///|   )
///|   inspect(fqname.to_qname().to_string(), content="Bar:baz")
///| }
///| ```
pub fn FQName::to_qname(self : FQName) -> QName {
  QName::from_name(self.module_name.to_path(), self.local_name)
}

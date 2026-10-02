///|
let zero : @ast.Range = {
  start: { row: 0, column: 0, },
  end: { row: 0, column: 0, },
}

///|
fn[T] node(value : T) -> @ast.Node[T] {
  { range: zero, value, }
}

///|
let default_imports : Array[String] = [
  "Basics", "List", "Maybe", "Result", "String", "Char", "Tuple", "Debug",
]

///|
priv enum Kind {
  Value
  Constructor
  TypeName
}

///|
priv enum Resolved {
  Qualified(Array[String], String)
  Op(String)
}

///|
/// One context per generated Elm module. `scope` maps IR local names (canonical) to Elm names.
priv struct Ctx {
  options : Options
  package_name : @ir.Path
  module : @ir.Path
  imports : Map[String, String?]
  mut uses_sdk_package : Bool
  foreign_packages : Map[String, Bool]
  mut scope : Map[String, String]
  used : Map[String, Bool]
  mut fresh : Int
  /// Elm names of the type variables of the declaration being lowered, by canonical IR name.
  mut type_variables : Map[String, String]
}

///|
fn Ctx::new(
  options : Options,
  package_name : @ir.Path,
  module : @ir.Path,
) -> Ctx {
  {
    options,
    package_name,
    module,
    imports: Map([]),
    uses_sdk_package: false,
    foreign_packages: Map([]),
    scope: Map([]),
    used: Map([]),
    fresh: 0,
    type_variables: Map([]),
  }
}

///|
fn split_qualified(text : String) -> (Array[String], String) {
  let parts = text.split(".").map(p => p.to_string()).collect()
  let local = parts.pop().unwrap()
  (parts, local)
}

///|
fn Ctx::add_import_line(self : Ctx, line : String) -> Unit {
  let parts = line.split(" as ").map(p => p.to_string()).collect()
  match parts {
    [module, alias] => self.imports[module] = Some(alias)
    _ => self.imports[line] = None
  }
}

///|
fn Ctx::resolve(self : Ctx, name : @ir.FQName, kind : Kind) -> Resolved {
  let namespace : Namespace = match kind {
    TypeName => TypeSpace
    Value | Constructor => ValueSpace
  }
  if self.options.profile is Model {
    match self.options.mapping.lookup(name, namespace) {
      Some(Operator(op)) => return Op(op)
      Some(Function(text, import_line)) | Some(Type(text, import_line)) => {
        let (qualifier, local) = split_qualified(text)
        match import_line {
          Some(line) => self.add_import_line(line)
          None =>
            if !qualifier.is_empty() &&
              !default_imports.contains(qualifier.join(".")) {
              self.imports[qualifier.join(".")] = None
            }
        }
        return Qualified(qualifier, local)
      }
      _ => ()
    }
  }
  let local = match kind {
    Value => value_name(name.local_name)
    Constructor | TypeName => type_name(name.local_name)
  }
  if name.package_name == self.package_name && name.module_name == self.module {
    return Qualified([], local)
  }
  let package_text = name.package_name.to_canonical()
  if package_text == "morphir/SDK" {
    self.uses_sdk_package = true
  } else if name.package_name != self.package_name {
    self.foreign_packages[package_text] = true
  }
  let qualifier = module_name(name.package_name, name.module_name)
  self.imports[qualifier.join(".")] = None
  Qualified(qualifier, local)
}

///|
fn Ctx::elm_imports(self : Ctx) -> Array[@ast.Node[@ast.Import]] {
  let names = self.imports.keys().collect()
  names.sort()
  names.map(module => {
    let alias = self.imports.get(module).unwrap()
    node({
      module_name: node(module.split(".").map(p => p.to_string()).collect()[:]),
      module_alias: alias.map(a => node([a][:])),
      exposing_list: None,
    })
  })
}

///|
/// `-}` would end the comment early, so it is written as `- }`.
fn doc_comment(doc : String?, attributes : Array[String]) -> @ast.Node[String]? {
  if doc is None && attributes.is_empty() {
    return None
  }
  let body = doc.unwrap_or("").replace_all(old="-}", new="- }")
  let block = if attributes.is_empty() {
    ""
  } else {
    "\n\n```attributes\n" +
    attributes.map(a => a.replace_all(old="-}", new="-\\u{007D}")).join("\n") +
    "\n```\n"
  }
  Some(node("{-| " + body + block + "\n-}"))
}

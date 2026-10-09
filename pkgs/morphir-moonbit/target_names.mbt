///|
pub const NAMING_POLICY : String = "moonbit-readable-targets-v1"

///|
pub(all) enum NamingStyle {
  Readable
  LegacyHex
} derive(Eq, Debug)

///|
pub extend NamingStyle with Eq::{equal, not_equal}

///|
pub extend NamingStyle with @debug.Debug::{to_repr}

///|
pub(all) struct NamingAllocation {
  owner : String
  role : String
  original : String?
  candidate : String
  allocated : String
  reason : String
} derive(Eq, Debug)

///|
pub extend NamingAllocation with Eq::{equal, not_equal}

///|
pub extend NamingAllocation with @debug.Debug::{to_repr}

///|
priv struct NamingCandidate {
  owner : String
  role : String
  original : String?
  candidate : String
  qualified : String
  source : @diagnostics.Span?
  reason : String
}

///|
priv struct TargetNames {
  style : NamingStyle
  origins : Map[String, @ion.IonValue]
  names : Map[String, String]
  fields : Map[String, Map[@ir.Name, String]]
  reserved : Map[String, Bool]
  reserved_locations : Map[String, Array[@diagnostics.Location]]
  allocations : Array[NamingAllocation]
  warnings : Array[@diagnostics.Warning]
}

///|
fn keyword(text : String) -> Bool {
  [
    "as", "else", "extern", "fn", "if", "let", "const", "match", "using", "mut",
    "type", "struct", "enum", "extenum", "trait", "derive", "while", "break", "continue",
    "import", "return", "throw", "raise", "try", "catch", "pub", "priv", "readonly",
    "true", "false", "_", "test", "loop", "for", "in", "impl", "with", "guard", "async",
    "is", "suberror", "and", "letrec", "enumview", "noraise", "nocancel", "defer",
    "lexmatch", "lexscan", "where", "declare", "nobreak", "proof_assert", "proof_let",
    "main", "init", "module", "move", "ref", "static", "super", "unsafe", "use",
    "await", "dyn", "abstract", "do", "final", "macro", "override", "typeof", "virtual",
    "yield", "local", "method", "alias", "assert", "package", "recur", "isnot", "define",
    "downcast", "inherit", "member", "namespace", "upcast", "void", "lazy", "include",
    "mixin", "protected", "sealed", "constructor", "atomic", "volatile", "anyframe",
    "anytype", "asm", "comptime", "errdefer", "export", "opaque", "orelse", "resume",
    "threadlocal", "unreachable", "dynclass", "dynobj", "dynrec", "var", "finally",
    "noasync", "assume", "extend",
  ].contains(text)
}

///|
fn usable_identifier(text : String, upper : Bool) -> Bool {
  let chars = text.to_array()
  if chars.is_empty() {
    return false
  }
  if upper {
    if chars[0] < 'A' || chars[0] > 'Z' {
      return false
    }
  } else if (chars[0] < 'a' || chars[0] > 'z') && chars[0] != '_' {
    return false
  }
  if text == "_" {
    return false
  }
  chars.all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_'
  })
}

///|
fn render_name(name : @ir.Name, upper : Bool) -> String {
  let parts = name.to_canonical().split("-").map(StringView::to_owned).collect()
  let text = if upper {
    parts
    .map(p => {
      let chars = p.to_array()
      chars[0].to_string().to_upper() +
      chars[1:].iter().map(Char::to_string).collect().join("")
    })
    .join("")
  } else {
    parts.join("_")
  }
  if usable_identifier(text, upper) {
    text
  } else {
    (if upper { "Type_" } else { "value_" }) + text
  }
}

///|
fn TargetNames::new(input : Input, style : NamingStyle) -> TargetNames raise {
  let plan : TargetNames = {
    style,
    origins: Map([]),
    names: Map([]),
    fields: Map([]),
    reserved: Map([]),
    reserved_locations: Map([]),
    allocations: [],
    warnings: [],
  }
  if moonbit_origins(input) {
    let ambiguous : Map[String, Bool] = Map([])
    for metadata in input.metadata {
      if plan.origins.contains(metadata.node_id) {
        plan.origins.remove(metadata.node_id)
        ambiguous[metadata.node_id] = true
      } else if !ambiguous.contains(metadata.node_id) {
        plan.origins[metadata.node_id] = metadata.data
      }
    }
  }
  guard input.ir.distribution is Library(package_name, _, definition) else {
    return plan
  }
  let values = []
  let types = []
  let constructors = []
  for module_name, access in definition.modules {
    for name, _ in access.value.values {
      let fqname : @ir.FQName = { package_name, module_name, local_name: name, }
      ignore(value_name(fqname))
      let owner = value_node(fqname)
      let (original, source) = declaration_hint(plan, owner)
      if style == LegacyHex {
        plan.names[owner] = value_name(fqname)
      } else {
        values.push(
          candidate(owner, "value", name, module_name, original, source, false),
        )
      }
    }
    for name, entry in access.value.types {
      let fqname : @ir.FQName = { package_name, module_name, local_name: name, }
      ignore(value_name(fqname))
      if entry.value.value is CustomTypeDefinition(_, cases) {
        let owner = "type:" + fqname.to_canonical()
        if style == LegacyHex {
          plan.names[owner] = "T_" + hex(fqname.to_canonical())
        } else {
          types.push(
            candidate(owner, "type", name, module_name, None, None, true),
          )
        }
        for name, _ in cases.value {
          let ctor = { ..fqname, local_name: name, }
          let owner = "constructor:" + ctor.to_canonical()
          if style == LegacyHex {
            plan.names[owner] = "C_" + hex(ctor.to_canonical())
          } else {
            constructors.push(
              candidate(
                owner,
                "constructor",
                name,
                module_name,
                None,
                None,
                true,
              ),
            )
          }
        }
      }
    }
  }
  allocate_namespace(plan, values, Map([]))
  allocate_namespace(
    plan,
    types,
    Map::from_array(
      [
        "Int", "Int64", "UInt", "UInt64", "Bool", "Double", "Float", "String", "Char",
        "Byte", "Bytes", "Unit", "Array", "Option", "Result",
      ].map(n => (n, true)),
    ),
  )
  allocate_namespace(
    plan,
    constructors,
    Map::from_array(["Some", "None", "Ok", "Err"].map(n => (n, true))),
  )
  plan
}

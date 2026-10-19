///|
priv struct Checker {
  env : TypeEnvironment
  limits : Limits
  mut nodes : Int32
  mut type_nodes : Int32
  mut subst_exhausted : Bool
}

///|
fn diag(code : String, path : String, message : String) -> Diagnostic {
  { code, path, message, }
}

///|
fn invalid(code : String, path : String, message : String) -> Outcome {
  Invalid([diag(code, path, message)])
}

///|
fn child_path(path : String, segment : String) -> String {
  if path == "/" {
    "/" + segment
  } else {
    path + "/" + segment
  }
}

///|
fn find_record_value(fields : Array[(String, Value)], name : String) -> Value? {
  for (other, value) in fields {
    if other == name {
      return Some(value)
    }
  }
  None
}

///|
fn find_dict_value(entries : Array[(Value, Value)], key : Value) -> Value? {
  for (other, value) in entries {
    if value_equal(other, key) {
      return Some(value)
    }
  }
  None
}

///|
fn find_field_type(
  fields : Array[(String, TypeExpr)],
  name : String,
) -> TypeExpr? {
  for (other, ty) in fields {
    if other == name {
      return Some(ty)
    }
  }
  None
}

///|
fn find_constructor(
  constructors : Array[(String, Array[TypeExpr])],
  name : String,
) -> Array[TypeExpr]? {
  for (other, payloads) in constructors {
    if other == name {
      return Some(payloads)
    }
  }
  None
}

///|
fn value_equal(a : Value, b : Value) -> Bool {
  match (a, b) {
    (VBool(x), VBool(y)) => x == y
    (VInt(x), VInt(y)) => x == y
    (VString(x), VString(y)) => x == y
    (VTuple(xs), VTuple(ys)) | (VList(xs), VList(ys)) =>
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => value_equal(pair.0, pair.1))
    (VSet(xs), VSet(ys)) => {
      if xs.length() != ys.length() {
        return false
      }
      // Sets are unordered: match each element against a distinct partner.
      let used : Array[Bool] = []
      for _ in ys {
        used.push(false)
      }
      for x in xs {
        let mut matched = false
        for j in 0..<ys.length() {
          if !used[j] && value_equal(x, ys[j]) {
            used[j] = true
            matched = true
            break
          }
        }
        if !matched {
          return false
        }
      }
      true
    }
    (VRecord(xs), VRecord(ys)) =>
      xs.length() == ys.length() &&
      xs
      .iter()
      .all(pair => {
        match find_record_value(ys, pair.0) {
          Some(y) => value_equal(pair.1, y)
          None => false
        }
      })
    (VDict(xs), VDict(ys)) =>
      xs.length() == ys.length() &&
      xs
      .iter()
      .all(pair => {
        match find_dict_value(ys, pair.0) {
          Some(vy) => value_equal(pair.1, vy)
          None => false
        }
      })
    (VConstructed(cx, xs), VConstructed(cy, ys)) =>
      cx == cy &&
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => value_equal(pair.0, pair.1))
    (VOpaque(nx, x), VOpaque(ny, y)) => nx == ny && value_equal(x, y)
    _ => false
  }
}

///|
priv enum RefinementResult {
  Holds
  Fails
  Unknown(String)
}

///|
fn refinement_known(refinement : Refinement) -> Bool {
  match refinement {
    NamedRefinement(name) =>
      name == "string.nonEmpty" ||
      name == "int.positive" ||
      name == "int.nonNegative"
    _ => true
  }
}

///|
fn refinement_holds(refinement : Refinement, value : Value) -> RefinementResult {
  match refinement {
    NonEmptyString =>
      match value {
        VString(s) => if s.is_empty() { Fails } else { Holds }
        _ => Fails
      }
    PositiveInt =>
      match value {
        VInt(n) => if n > @bigint.BigInt::from_int(0) { Holds } else { Fails }
        _ => Fails
      }
    NonNegativeInt =>
      match value {
        VInt(n) => if n >= @bigint.BigInt::from_int(0) { Holds } else { Fails }
        _ => Fails
      }
    MaxLength(limit) =>
      match value {
        VString(s) => if s.length() <= limit { Holds } else { Fails }
        _ => Fails
      }
    NamedRefinement(name) =>
      match name {
        "string.nonEmpty" => refinement_holds(NonEmptyString, value)
        "int.positive" => refinement_holds(PositiveInt, value)
        "int.nonNegative" => refinement_holds(NonNegativeInt, value)
        _ => Unknown(name)
      }
  }
}

///|
fn check_refinement(
  refinement : Refinement?,
  value : Value,
  path : String,
) -> Outcome {
  match refinement {
    None => Valid
    Some(rule) =>
      match refinement_holds(rule, value) {
        Holds => Valid
        Fails =>
          invalid(
            "contracts.refinement_failed", path, "value fails its declared refinement",
          )
        Unknown(name) =>
          Unsupported(
            diag(
              "contracts.unsupported_refinement",
              path,
              "unsupported refinement: " + name,
            ),
          )
      }
  }
}

///|
fn mismatch(value : Value, path : String, expected : String) -> Outcome {
  match value {
    VOpaque(name, _) =>
      invalid(
        "contracts.opaque_construction",
        path,
        "opaque value for " + name + " cannot be used as " + expected,
      )
    _ =>
      invalid(
        "contracts.invalid_value",
        path,
        "value does not match " + expected,
      )
  }
}

///|
fn type_key(ty : TypeExpr) -> String {
  match ty {
    TBool => "Bool"
    TInt => "Int"
    TString => "String"
    TVariable(name) => "?" + name
    TReference(name, args) =>
      name +
      "<" +
      args
      .map(a => type_key(a))
      .fold(init="", (acc, part) => {
        if acc.is_empty() {
          part
        } else {
          acc + "," + part
        }
      }) +
      ">"
    TTuple(items) =>
      "(" +
      items
      .map(a => type_key(a))
      .fold(init="", (acc, part) => {
        if acc.is_empty() {
          part
        } else {
          acc + "," + part
        }
      }) +
      ")"
    TRecord(fields) =>
      "{" +
      fields
      .map(pair => pair.0 + ":" + type_key(pair.1))
      .fold(init="", (acc, part) => {
        if acc.is_empty() {
          part
        } else {
          acc + "," + part
        }
      }) +
      "}"
    TUnion(members) =>
      "union<" +
      members
      .map(a => type_key(a))
      .fold(init="", (acc, part) => {
        if acc.is_empty() {
          part
        } else {
          acc + "|" + part
        }
      }) +
      ">"
    TList(elem) => "List<" + type_key(elem) + ">"
    TSet(elem) => "Set<" + type_key(elem) + ">"
    TDict(k, v) => "Dict<" + type_key(k) + "," + type_key(v) + ">"
    TFunction(_, _) => "Function"
    TUnsupported(name) => "Unsupported<" + name + ">"
  }
}

///|
/// Substitute type variables, charging every visited type node to the shared
/// node budget. Traversal stops as soon as the budget is exceeded, so a
/// deeply nested or widely shared generic argument cannot bypass the limits.
fn Checker::substitute(
  self : Checker,
  ty : TypeExpr,
  subst : Map[String, TypeExpr],
) -> TypeExpr {
  if self.subst_exhausted {
    return ty
  }
  self.type_nodes = self.type_nodes + 1
  if self.type_nodes > self.limits.max_value_nodes {
    self.subst_exhausted = true
    return ty
  }
  match ty {
    TVariable(name) =>
      match subst.get(name) {
        Some(found) => found
        None => ty
      }
    TReference(name, args) =>
      TReference(name, args.map(a => self.substitute(a, subst)))
    TTuple(items) => TTuple(items.map(a => self.substitute(a, subst)))
    TRecord(fields) =>
      TRecord(fields.map(pair => (pair.0, self.substitute(pair.1, subst))))
    TUnion(members) => TUnion(members.map(a => self.substitute(a, subst)))
    TList(elem) => TList(self.substitute(elem, subst))
    TSet(elem) => TSet(self.substitute(elem, subst))
    TDict(k, v) => TDict(self.substitute(k, subst), self.substitute(v, subst))
    TFunction(args, result) =>
      TFunction(
        args.map(a => self.substitute(a, subst)),
        self.substitute(result, subst),
      )
    _ => ty
  }
}

///|
fn Checker::bind_arguments(
  self : Checker,
  params : Array[String],
  args : Array[TypeExpr],
  subst : Map[String, TypeExpr],
) -> Map[String, TypeExpr] {
  let bound : Map[String, TypeExpr] = Map([])
  for i in 0..<params.length() {
    bound[params[i]] = self.substitute(args[i], subst)
  }
  bound
}

///|
/// Capability is decided before any value is admitted (C1): walk the type
/// and every reachable declaration, reporting unsupported forms, unknown
/// types, unbound variables and unknown refinements even where an empty
/// collection or an unselected constructor would visit no payload.
fn Checker::inventory(
  self : Checker,
  ty : TypeExpr,
  subst : Map[String, TypeExpr],
  visited : Array[String],
) -> Outcome {
  self.type_nodes = self.type_nodes + 1
  if self.type_nodes > self.limits.max_value_nodes {
    return Exhausted(NodeLimit)
  }
  match ty {
    TBool | TInt | TString => Valid
    TVariable(name) =>
      match subst.get(name) {
        Some(found) => self.inventory(found, subst, visited)
        None =>
          Unsupported(
            diag(
              "contracts.unbound_variable",
              "/",
              "unbound type variable: " + name,
            ),
          )
      }
    TTuple(items) | TUnion(items) => {
      for item in items {
        let outcome = self.inventory(item, subst, visited)
        if !(outcome is Valid) {
          return outcome
        }
      }
      Valid
    }
    TRecord(fields) => {
      for pair in fields {
        let outcome = self.inventory(pair.1, subst, visited)
        if !(outcome is Valid) {
          return outcome
        }
      }
      Valid
    }
    TList(elem) | TSet(elem) => self.inventory(elem, subst, visited)
    TDict(k, v) => {
      let outcome = self.inventory(k, subst, visited)
      if !(outcome is Valid) {
        return outcome
      }
      self.inventory(v, subst, visited)
    }
    TFunction(_, _) =>
      Unsupported(
        diag(
          "contracts.unsupported_type", "/", "function types are outside the bounded checking profile",
        ),
      )
    TUnsupported(name) =>
      Unsupported(
        diag("contracts.unsupported_type", "/", "unsupported type: " + name),
      )
    TReference(name, args) =>
      match self.env.declarations.get(name) {
        None =>
          Unsupported(
            diag("contracts.unknown_type", "/", "unknown type: " + name),
          )
        Some(decl) => {
          let params = match decl {
            Transparent(ps, _, _) => ps
            Opaque(ps, _, _) => ps
            Custom(ps, _) => ps
          }
          if params.length() != args.length() {
            return invalid(
              "contracts.invalid_value",
              "/",
              "type argument count does not match declaration: " + name,
            )
          }
          for arg in args {
            let outcome = self.inventory(arg, subst, visited)
            if !(outcome is Valid) {
              return outcome
            }
          }
          let key = type_key(TReference(name, args))
          if visited.contains(key) {
            return Valid
          }
          let bound = self.bind_arguments(params, args, subst)
          if self.subst_exhausted {
            return Exhausted(NodeLimit)
          }
          let visited2 = visited + [key]
          match decl {
            Transparent(_, underlying, refinement)
            | Opaque(_, underlying, refinement) => {
              match refinement {
                Some(rule) if !refinement_known(rule) =>
                  return Unsupported(
                    diag(
                      "contracts.unsupported_refinement",
                      "/",
                      "unsupported refinement on: " + name,
                    ),
                  )
                _ => ()
              }
              self.inventory(underlying, bound, visited2)
            }
            Custom(_, constructors) => {
              for pair in constructors {
                for payload in pair.1 {
                  let outcome = self.inventory(payload, bound, visited2)
                  if !(outcome is Valid) {
                    return outcome
                  }
                }
              }
              Valid
            }
          }
        }
      }
  }
}

///|
fn Checker::check(
  self : Checker,
  ty : TypeExpr,
  value : Value,
  path : String,
  depth : Int32,
  subst : Map[String, TypeExpr],
  expanding : Array[String],
) -> Outcome {
  if depth > self.limits.max_depth {
    return Exhausted(DepthLimit)
  }
  self.nodes = self.nodes + 1
  if self.nodes > self.limits.max_value_nodes {
    return Exhausted(NodeLimit)
  }
  match ty {
    TBool =>
      match value {
        VBool(_) => Valid
        _ => mismatch(value, path, "Bool")
      }
    TInt =>
      match value {
        VInt(n) => {
          let lexeme = n.to_string()
          let digits = if lexeme.has_prefix("-") {
            lexeme.length() - 1
          } else {
            lexeme.length()
          }
          if digits > self.limits.max_int_digits {
            Exhausted(IntDigitLimit)
          } else {
            Valid
          }
        }
        _ => mismatch(value, path, "Int")
      }
    TString =>
      match value {
        VString(_) => Valid
        _ => mismatch(value, path, "String")
      }
    TVariable(name) =>
      match subst.get(name) {
        Some(found) =>
          self.check(found, value, path, depth + 1, subst, expanding)
        None =>
          Unsupported(
            diag(
              "contracts.unbound_variable",
              path,
              "unbound type variable: " + name,
            ),
          )
      }
    TTuple(items) =>
      match value {
        VTuple(values) => {
          if values.length() != items.length() {
            return invalid(
              "contracts.invalid_value", path, "tuple arity does not match its declared type",
            )
          }
          for i in 0..<items.length() {
            let outcome = self.check(
              items[i],
              values[i],
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
            )
            if !(outcome is Valid) {
              return outcome
            }
          }
          Valid
        }
        _ => mismatch(value, path, "tuple")
      }
    TRecord(fields) => {
      let seen : Map[String, Bool] = Map([])
      for pair in fields {
        if seen.contains(pair.0) {
          return invalid(
            "contracts.invalid_value",
            child_path(path, pair.0),
            "duplicate record field in declared type: " + pair.0,
          )
        }
        seen[pair.0] = true
      }
      match value {
        VRecord(values) => {
          let present : Map[String, Bool] = Map([])
          for (name, field_value) in values {
            if present.contains(name) {
              return invalid(
                "contracts.invalid_value",
                child_path(path, name),
                "duplicate record field: " + name,
              )
            }
            present[name] = true
            if !seen.contains(name) {
              return invalid(
                "contracts.invalid_value",
                child_path(path, name),
                "unexpected record field: " + name,
              )
            }
            let field_ty = find_field_type(fields, name).unwrap()
            let outcome = self.check(
              field_ty,
              field_value,
              child_path(path, name),
              depth + 1,
              subst,
              [],
            )
            if !(outcome is Valid) {
              return outcome
            }
          }
          for pair in fields {
            if !present.contains(pair.0) {
              return invalid(
                "contracts.invalid_value",
                child_path(path, pair.0),
                "missing record field: " + pair.0,
              )
            }
          }
          Valid
        }
        _ => mismatch(value, path, "record")
      }
    }
    TList(elem) =>
      match value {
        VList(values) => {
          for i in 0..<values.length() {
            let outcome = self.check(
              elem,
              values[i],
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
            )
            if !(outcome is Valid) {
              return outcome
            }
          }
          Valid
        }
        _ => mismatch(value, path, "list")
      }
    TSet(elem) =>
      match value {
        VSet(values) => {
          for i in 0..<values.length() {
            let outcome = self.check(
              elem,
              values[i],
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
            )
            if !(outcome is Valid) {
              return outcome
            }
            for j in 0..<i {
              if value_equal(values[j], values[i]) {
                return invalid(
                  "contracts.invalid_value",
                  child_path(path, i.to_string()),
                  "duplicate set element",
                )
              }
            }
          }
          Valid
        }
        _ => mismatch(value, path, "set")
      }
    TDict(key_ty, value_ty) =>
      match value {
        VDict(entries) => {
          for i in 0..<entries.length() {
            let (key, entry_value) = entries[i]
            let key_outcome = self.check(
              key_ty,
              key,
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
            )
            if !(key_outcome is Valid) {
              return key_outcome
            }
            let value_outcome = self.check(
              value_ty,
              entry_value,
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
            )
            if !(value_outcome is Valid) {
              return value_outcome
            }
            for j in 0..<i {
              if value_equal(entries[j].0, key) {
                return invalid(
                  "contracts.invalid_value",
                  child_path(path, i.to_string()),
                  "duplicate dict key",
                )
              }
            }
          }
          Valid
        }
        _ => mismatch(value, path, "dict")
      }
    TUnion(members) => {
      if members.is_empty() {
        return invalid(
          "contracts.invalid_value", path, "union has no member types",
        )
      }
      let mut matched = 0
      let mut first_failure : Outcome = Valid
      for member_ty in members {
        let outcome = self.check(
          member_ty,
          value,
          path,
          depth + 1,
          subst,
          expanding,
        )
        match outcome {
          Valid => matched = matched + 1
          Unsupported(_) | Exhausted(_) => return outcome
          Invalid(diagnostics) => {
            // Ambiguity found by a nested union is a property of this
            // value, not an ordinary mismatch of one member.
            if diagnostics
              .iter()
              .any(d => d.code == "contracts.ambiguous_value") {
              return outcome
            }
            if first_failure is Valid {
              first_failure = outcome
            }
          }
        }
      }
      if matched == 1 {
        Valid
      } else if matched > 1 {
        invalid(
          "contracts.ambiguous_value", path, "value matches more than one union member",
        )
      } else {
        first_failure
      }
    }
    TFunction(_, _) =>
      Unsupported(
        diag(
          "contracts.unsupported_type", path, "function types are outside the bounded checking profile",
        ),
      )
    TUnsupported(name) =>
      Unsupported(
        diag("contracts.unsupported_type", path, "unsupported type: " + name),
      )
    TReference(name, args) =>
      match self.env.declarations.get(name) {
        None =>
          Unsupported(
            diag("contracts.unknown_type", path, "unknown type: " + name),
          )
        Some(decl) => {
          let params = match decl {
            Transparent(ps, _, _) => ps
            Opaque(ps, _, _) => ps
            Custom(ps, _) => ps
          }
          if params.length() != args.length() {
            return invalid(
              "contracts.invalid_value",
              path,
              "type argument count does not match declaration: " + name,
            )
          }
          let bound = self.bind_arguments(params, args, subst)
          if self.subst_exhausted {
            return Exhausted(NodeLimit)
          }
          match decl {
            Transparent(_, underlying, refinement) => {
              if expanding.contains(name) {
                return invalid(
                  "contracts.alias_cycle",
                  path,
                  "alias cycle reaches: " + name,
                )
              }
              let outcome = self.check(
                underlying,
                value,
                path,
                depth + 1,
                bound,
                expanding + [name],
              )
              if !(outcome is Valid) {
                return outcome
              }
              check_refinement(refinement, value, path)
            }
            Opaque(_, underlying, refinement) => {
              if expanding.contains(name) {
                return invalid(
                  "contracts.alias_cycle",
                  path,
                  "alias cycle reaches: " + name,
                )
              }
              match value {
                VOpaque(value_name, inner) => {
                  if value_name != name {
                    return invalid(
                      "contracts.opaque_construction",
                      path,
                      "opaque value for " +
                      value_name +
                      " cannot be used as " +
                      name,
                    )
                  }
                  let outcome = self.check(
                    underlying,
                    inner,
                    path,
                    depth + 1,
                    bound,
                    [],
                  )
                  if !(outcome is Valid) {
                    return outcome
                  }
                  check_refinement(refinement, inner, path)
                }
                _ =>
                  invalid(
                    "contracts.opaque_construction",
                    path,
                    "opaque type " +
                    name +
                    " requires a constructed value; its representation is hidden",
                  )
              }
            }
            Custom(_, constructors) =>
              match value {
                VConstructed(ctor, payloads) =>
                  match find_constructor(constructors, ctor) {
                    None =>
                      invalid(
                        "contracts.invalid_value",
                        path,
                        "unknown constructor: " + ctor,
                      )
                    Some(payload_tys) => {
                      if payloads.length() != payload_tys.length() {
                        return invalid(
                          "contracts.invalid_value",
                          path,
                          "constructor payload count does not match: " + ctor,
                        )
                      }
                      for i in 0..<payload_tys.length() {
                        let outcome = self.check(
                          payload_tys[i],
                          payloads[i],
                          child_path(path, i.to_string()),
                          depth + 1,
                          bound,
                          [],
                        )
                        if !(outcome is Valid) {
                          return outcome
                        }
                      }
                      Valid
                    }
                  }
                VOpaque(value_name, _) =>
                  invalid(
                    "contracts.opaque_construction",
                    path,
                    "opaque value for " +
                    value_name +
                    " cannot be used as " +
                    name,
                  )
                _ =>
                  invalid(
                    "contracts.invalid_value",
                    path,
                    "value requires a constructor of: " + name,
                  )
              }
          }
        }
      }
  }
}

///|
/// Check `value` against `ty` under `env`, bounded by `limits`.
///
/// Capability is decided first: unsupported types, unknown names, unbound
/// variables and unknown refinements are reported before any value is
/// admitted. The check itself is recursive over records, custom types,
/// generics, tuples of any arity, collections and untagged unions. It
/// respects refinements and opacity, reports ambiguous union membership,
/// and never reports `Valid` after a budget is exhausted. Generic
/// substitution is charged to the same node budget.
pub fn admit(
  env : TypeEnvironment,
  ty : TypeExpr,
  value : Value,
  limits~ : Limits = Limits::default(),
) -> Outcome {
  if env.profile != supported_profile {
    return Unsupported(
      diag(
        "contracts.unsupported_profile",
        "/",
        "unsupported fixture profile: " + env.profile,
      ),
    )
  }
  match env.declaration_error {
    Some(error) => return Invalid([error])
    None => ()
  }
  let checker : Checker = {
    env,
    limits,
    nodes: 0,
    type_nodes: 0,
    subst_exhausted: false,
  }
  let inventory = checker.inventory(ty, Map([]), [])
  if !(inventory is Valid) {
    return inventory
  }
  checker.check(ty, value, "/", 1, Map([]), [])
}

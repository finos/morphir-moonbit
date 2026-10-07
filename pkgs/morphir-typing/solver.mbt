///|
fn Solver::new(expand : (String, Array[Ty]) -> Ty?) -> Solver {
  { metas: [], rigid_classes: Map([]), expand, }
}

///|
/// A new unbound meta at `level` with the class set `classes`.
fn Solver::fresh(self : Solver, level : Int, classes : Array[String]) -> Ty {
  let id = self.metas.length()
  self.metas.push(Unbound(level~, classes~))
  Meta(id)
}

///|
/// Follows meta links. A record whose tail is solved to a record is flattened into one record, and a record
/// with no fields and an open tail is the tail.
fn Solver::prune(self : Solver, t : Ty) -> Ty {
  match t {
    Meta(id) =>
      match self.metas[id] {
        Link(target) => {
          let pruned = self.prune(target)
          self.metas[id] = Link(pruned)
          pruned
        }
        Unbound(..) => t
      }
    Rec(fields, Some(tail)) =>
      match self.prune(tail) {
        Rec(more, rest) => {
          let merged = fields.copy()
          for name, field in more {
            if !merged.contains(name) {
              merged[name] = field
            }
          }
          match rest {
            Some(tail) => row(merged, tail)
            None => Rec(merged, None)
          }
        }
        pruned => row(fields, pruned)
      }
    _ => t
  }
}

///|
/// Whether the meta `id` occurs in `t`.
fn Solver::occurs(self : Solver, id : Int, t : Ty) -> Bool {
  match self.prune(t) {
    Meta(other) => other == id
    Con(_, items) | Tup(items) => items.iter().any(fn(x) { self.occurs(id, x) })
    Fun(input, output) => self.occurs(id, input) || self.occurs(id, output)
    Rec(fields, tail) =>
      fields.values().any(fn(x) { self.occurs(id, x) }) ||
      (tail is Some(row) && self.occurs(id, row))
    Rigid(_) | Gen(_) | UnitTy => false
  }
}

///|
/// Lowers the level of every unbound meta in `t` to at most `level`.
fn Solver::adjust_levels(self : Solver, level : Int, t : Ty) -> Unit {
  match self.prune(t) {
    Meta(id) =>
      if self.metas[id] is Unbound(level=own, classes~) && own > level {
        self.metas[id] = Unbound(level~, classes~)
      }
    Con(_, items) | Tup(items) =>
      items.each(fn(x) { self.adjust_levels(level, x) })
    Fun(input, output) => {
      self.adjust_levels(level, input)
      self.adjust_levels(level, output)
    }
    Rec(fields, tail) => {
      fields.values().each(fn(x) { self.adjust_levels(level, x) })
      if tail is Some(row) {
        self.adjust_levels(level, row)
      }
    }
    Rigid(_) | Gen(_) | UnitTy => ()
  }
}

///|
/// Unifies `expected` with `found`.
fn Solver::unify(
  self : Solver,
  expected : Ty,
  found : Ty,
) -> Unit raise Mismatch {
  let e = self.prune(expected)
  let f = self.prune(found)
  match (e, f) {
    (Meta(a), Meta(b)) => self.merge(a, b, e, f)
    (Meta(a), _) => self.bind(a, f, e, f)
    (_, Meta(b)) => self.bind(b, e, e, f)
    (Rigid(a), Rigid(b)) if a == b => ()
    (Gen(a), Gen(b)) if a == b => ()
    (Con(n1, a1), Con(n2, a2)) if n1 == n2 => {
      if a1.length() != a2.length() {
        raise Mismatch("type_mismatch", e, f)
      }
      for i, x in a1 {
        self.unify(x, a2[i])
      }
    }
    (Fun(a1, r1), Fun(a2, r2)) => {
      self.unify(a1, a2)
      self.unify(r1, r2)
    }
    (Tup(x1), Tup(x2)) if x1.length() == x2.length() =>
      for i, x in x1 {
        self.unify(x, x2[i])
      }
    (UnitTy, UnitTy) => ()
    (Rec(f1, t1), Rec(f2, t2)) => self.unify_rows(f1, t1, f2, t2, e, f)
    _ => self.unify_expanded(e, f)
  }
}

///|
/// Links two different metas. The classes join and the lower level wins.
fn Solver::merge(
  self : Solver,
  a : Int,
  b : Int,
  e : Ty,
  f : Ty,
) -> Unit raise Mismatch {
  if a == b {
    return
  }
  guard self.metas[a] is Unbound(level=la, classes=ca) &&
    self.metas[b] is Unbound(level=lb, classes=cb) else {
    abort("merge: metas must be unbound after pruning")
  }
  guard join(ca, cb) is Some(classes) else {
    raise Mismatch("no_instance", e, f)
  }
  self.metas[b] = Unbound(level=if la < lb { la } else { lb }, classes~)
  self.metas[a] = Link(Meta(b))
}

///|
/// Binds the meta `id` to the non-meta type `t`.
fn Solver::bind(
  self : Solver,
  id : Int,
  t : Ty,
  e : Ty,
  f : Ty,
) -> Unit raise Mismatch {
  if self.occurs(id, t) {
    raise Mismatch("occurs", e, f)
  }
  guard self.metas[id] is Unbound(level~, classes~) else {
    abort("bind: meta must be unbound after pruning")
  }
  self.adjust_levels(level, t)
  if self.satisfies(classes, t) is Some(code) {
    raise Mismatch(code, e, f)
  }
  self.metas[id] = Link(t)
}

///|
/// The fallback when the shapes differ: expand an alias on either side and retry, else fail.
fn Solver::unify_expanded(self : Solver, e : Ty, f : Ty) -> Unit raise Mismatch {
  if e is Con(name, args) && (self.expand)(name, args) is Some(expanded) {
    return self.unify(expanded, f)
  }
  if f is Con(name, args) && (self.expand)(name, args) is Some(expanded) {
    return self.unify(e, expanded)
  }
  let code = if e is Rigid(_) || f is Rigid(_) {
    "rigid_variable"
  } else {
    "type_mismatch"
  }
  raise Mismatch(code, e, f)
}

///|
/// Unifies two records through their rows. `t1` and `t2` are pruned tails.
fn Solver::unify_rows(
  self : Solver,
  f1 : Map[String, Ty],
  t1 : Ty?,
  f2 : Map[String, Ty],
  t2 : Ty?,
  e : Ty,
  f : Ty,
) -> Unit raise Mismatch {
  let only1 = without(f1, f2)
  let only2 = without(f2, f1)
  match (t1, t2) {
    (None, None) =>
      if !only1.is_empty() || !only2.is_empty() {
        raise Mismatch("missing_field", e, f)
      }
    (Some(r1), None) => {
      if !only1.is_empty() {
        raise Mismatch("missing_field", e, f)
      }
      self.unify(r1, Rec(only2, None))
    }
    (None, Some(r2)) => {
      if !only2.is_empty() {
        raise Mismatch("missing_field", e, f)
      }
      self.unify(Rec(only1, None), r2)
    }
    (Some(r1), Some(r2)) =>
      if r1 == r2 {
        if !only1.is_empty() || !only2.is_empty() {
          raise Mismatch("type_mismatch", e, f)
        }
      } else {
        let rho = self.fresh(self.row_level(r1, r2), [])
        self.unify(r1, row(only2, rho))
        self.unify(row(only1, rho), r2)
      }
  }
  for name, field in f1 {
    if f2.get(name) is Some(other) {
      self.unify(field, other)
    }
  }
}

///|
/// The fields of `a` whose names are not in `b`, in the order of `a`.
fn without(a : Map[String, Ty], b : Map[String, Ty]) -> Map[String, Ty] {
  let out : Map[String, Ty] = Map([])
  for name, field in a {
    if !b.contains(name) {
      out[name] = field
    }
  }
  out
}

///|
/// A record of `fields` with the open tail `tail`. With no fields it is the tail itself.
fn row(fields : Map[String, Ty], tail : Ty) -> Ty {
  if fields.is_empty() {
    tail
  } else {
    Rec(fields, Some(tail))
  }
}

///|
/// The level for a fresh row between two tails: the lower level of the tails that are metas.
fn Solver::row_level(self : Solver, r1 : Ty, r2 : Ty) -> Int {
  let levels = [r1, r2].filter_map(fn(r) {
    match r {
      Meta(id) =>
        match self.metas[id] {
          Unbound(level~, ..) => Some(level)
          Link(_) => None
        }
      _ => None
    }
  })
  match levels {
    [] => 0
    [level] => level
    [a, b, ..] => if a < b { a } else { b }
  }
}

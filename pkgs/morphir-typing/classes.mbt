///|
const NUMBER = "number"

///|
const COMPARABLE = "comparable"

///|
const APPENDABLE = "appendable"

///|
const COMPAPPEND = "compappend"

///|
/// Joins two class sets. Each set has at most one class. `None` means that no type satisfies both.
fn join(a : Array[String], b : Array[String]) -> Array[String]? {
  match (a, b) {
    ([], x) | (x, []) => Some(x)
    ([x], [y]) if x == y => Some([x])
    ([x], [y]) =>
      match join_class(x, y) {
        Some(c) => Some([c])
        None => join_class(y, x).map(fn(c) { [c] })
      }
    _ => None
  }
}

///|
/// One direction of the join of two different classes.
fn join_class(x : String, y : String) -> String? {
  match (x, y) {
    (COMPARABLE, APPENDABLE) => Some(COMPAPPEND)
    (NUMBER, COMPARABLE) => Some(NUMBER)
    (COMPAPPEND, COMPARABLE) | (COMPAPPEND, APPENDABLE) => Some(COMPAPPEND)
    _ => None
  }
}

///|
/// The class of a variable from its canonical name prefix. The longest prefix is checked first.
fn class_of_text(name : String) -> Array[String] {
  for class in [COMPAPPEND, APPENDABLE, COMPARABLE, NUMBER] {
    if name.has_prefix(class) {
      return [class]
    }
  }
  []
}

///|
const INT = "morphir/SDK:basics#int"

///|
const FLOAT = "morphir/SDK:basics#float"

///|
const CHAR = "morphir/SDK:char#char"

///|
const STRING = "morphir/SDK:string#string"

///|
const LIST = "morphir/SDK:list#list"

///|
/// The declared class set of a rigid variable: from `rigid_classes`, else from its name prefix.
fn Solver::rigid_class(self : Solver, name : String) -> Array[String] {
  match self.rigid_classes.get(name) {
    Some(classes) => classes
    None => class_of_text(name)
  }
}

///|
/// Checks that `t` is an instance of every class in `classes`. Metas inside `t` take on the classes that the
/// instance needs, for example the element of a comparable list becomes comparable.
fn Solver::satisfies(self : Solver, classes : Array[String], t : Ty) -> Bool {
  match classes {
    [] => true
    [class] => self.instance(class, t)
    _ => false
  }
}

///|
fn Solver::instance(self : Solver, class : String, t : Ty) -> Bool {
  match self.prune(t) {
    Meta(id) => self.add_class(id, class)
    Rigid(name) => {
      let declared = self.rigid_class(name)
      join(declared, [class]) == Some(declared)
    }
    Con(INT, []) | Con(FLOAT, []) => class == NUMBER || class == COMPARABLE
    Con(CHAR, []) => class == COMPARABLE
    Con(STRING, []) => class != NUMBER
    Con(LIST, [element]) =>
      match class {
        APPENDABLE => true
        COMPARABLE | COMPAPPEND => self.instance(COMPARABLE, element)
        _ => false
      }
    Tup(items) if class == COMPARABLE && items.length() is (2 | 3) =>
      items.iter().all(fn(item) { self.instance(COMPARABLE, item) })
    Con(name, args) =>
      match (self.expand)(name, args) {
        Some(expanded) => self.instance(class, expanded)
        None => false
      }
    _ => false
  }
}

///|
/// Joins `class` into the class set of the unbound meta `id`.
fn Solver::add_class(self : Solver, id : Int, class : String) -> Bool {
  guard self.metas[id] is Unbound(level~, classes~) else { return false }
  match join(classes, [class]) {
    Some(joined) => {
      self.metas[id] = Unbound(level~, classes=joined)
      true
    }
    None => false
  }
}

///|
/// Internal types. `Con` names are canonical FQName text.
priv enum Ty {
  Meta(Int)
  /// A declared variable, by canonical name.
  Rigid(String)
  /// A quantified variable inside a `Poly`.
  Gen(Int)
  Con(String, Array[Ty])
  Fun(Ty, Ty)
  Tup(Array[Ty])
  /// Fields by canonical name. The tail is a `Meta` or a `Rigid`; `None` is a closed record.
  Rec(Map[String, Ty], Ty?)
  UnitTy
} derive(Eq, Debug)

///|
/// The state of a meta variable. An unbound meta has a binding level and a class set of at most one class.
priv enum MetaState {
  Unbound(level~ : Int, classes~ : Array[String])
  Link(Ty)
}

///|
/// A type scheme. `gens[i]` holds the classes of `Gen(i)`.
priv struct Poly {
  gens : Array[Array[String]]
  body : Ty
}

///|
/// A unification failure: a code, the expected type and the found type.
/// The code is `type_mismatch`, `occurs`, `rigid_variable`, `no_instance` or `missing_field`.
priv suberror Mismatch {
  Mismatch(String, Ty, Ty)
}

///|
/// The substitution and the context of unification.
priv struct Solver {
  metas : Array[MetaState]
  /// The declared class set of each rigid variable, by canonical name.
  rigid_classes : Map[String, Array[String]]
  /// Alias expansion. `None` means the type is nominal.
  expand : (String, Array[Ty]) -> Ty?
}

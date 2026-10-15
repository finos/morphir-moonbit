///|
/// Corpus projects that do not generate yet, by `<project>/<backend>`, with the start of the first engine
/// diagnostic. `moon build` and `elm make` do not check them. Each entry has a comment with its reason and bead;
/// MoonBit generic values wait for `morphir-ukvn.5.22.11`.
let gaps : Map[String, String] = Map::from_array([
  // Generic custom type `Tree a` (morphir-ukvn.5.22.11).
  ("custom-types/moonbit", "moonbit.unsupported_type"),
  // The unused let value `b = 2` keeps the `number` type of its literal (morphir-ukvn.5.22.11).
  ("lets/moonbit", "moonbit.unsupported_constraint"),
  // `++` is `basics#append`, which has no MoonBit adapter (morphir-ukvn.5.22.3.12).
  ("operators/moonbit", "moonbit.unsupported_sdk"),
  // Literal and list patterns have no MoonBit lowering (morphir-ukvn.5.22.3.13).
  ("patterns/moonbit", "moonbit.unsupported_pattern"),
  // Extensible record argument `{ a | x : Int }` (morphir-ukvn.5.22.11).
  ("records/moonbit", "moonbit.unsupported_type"),
  // `Morphir.SDK.LocalDate` has no MoonBit type (morphir-ukvn.5.22.3.14).
  ("sdk-modules/moonbit", "moonbit.unsupported_type"),
  // Generic value `swap : ( a, b ) -> ( b, a )` (morphir-ukvn.5.22.11).
  ("signatures/moonbit", "moonbit.ambiguous_type"),
  // Generic type alias `Box a` (morphir-ukvn.5.22.11).
  ("types-and-aliases/moonbit", "moonbit.unsupported_type"),
  // The unannotated value `un = 1` has the `number` type of its literal (morphir-ukvn.5.22.11).
  ("unannotated/moonbit", "moonbit.unsupported_constraint"),
])

///|
/// Corpus projects that generate but that `moon build` or `elm make` refuses, by `<project>/<backend>`, with the
/// reason. The executable leaves them out of its output, so the check script cannot see when one closes: check
/// each entry again when its bead closes. Each entry has a comment with its bead.
let build_gaps : Map[String, String] = Map::from_array([])

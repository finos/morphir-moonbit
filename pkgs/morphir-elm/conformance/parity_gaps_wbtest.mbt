///|
/// Known differences from morphir-elm make, by project. Each line needs a comment with the reason and a bead.
/// The parity test fails when a pinned difference disappears, so remove the line when the gap closes.
fn parity_gaps() -> Map[String, Array[String]] {
  Map([
    (
      "modules",
      [
        // morphir-elm writes node types with their aliases expanded; @typing keeps alias names. morphir-elm drops
        // module Sig, so neither output defines `sig#code` and the comparison cannot expand it. Bead
        // morphir-ukvn.5.22.7.3.
        "type value:parity/modules:api#is-blank/body/function: expected (morphir/SDK:string#string -> morphir/SDK:basics#bool), found (parity/modules:sig#code -> morphir/SDK:basics#bool)",
        "type value:parity/modules:api#is-blank/body/function/function: expected (morphir/SDK:string#string -> (morphir/SDK:string#string -> morphir/SDK:basics#bool)), found (parity/modules:sig#code -> (parity/modules:sig#code -> morphir/SDK:basics#bool))",
        "type value:parity/modules:api#is-blank/body/function/argument: expected morphir/SDK:string#string, found parity/modules:sig#code",
      ],
    ),
    (
      "signatures",
      [
        // @typing generalizes the let function `mark`; morphir-elm has no let-polymorphism and gives it the type
        // of its use, `a -> ( a, Bool )`. Bead morphir-ukvn.5.22.7.1.
        "type value:parity/signatures:constrained#pairs/body/definition/body: expected (a -> (tuple a morphir/SDK:basics#bool)), found (b -> (tuple b morphir/SDK:basics#bool))",
        "type value:parity/signatures:constrained#pairs/body/definition/body/pattern: expected a, found b",
        "type value:parity/signatures:constrained#pairs/body/definition/body/pattern/pattern: expected a, found b",
        "type value:parity/signatures:constrained#pairs/body/definition/body/body: expected (tuple a morphir/SDK:basics#bool), found (tuple b morphir/SDK:basics#bool)",
        "type value:parity/signatures:constrained#pairs/body/definition/body/body/items/0: expected a, found b",
      ],
    ),
    (
      "types-and-aliases",
      [
        // morphir-elm prints the row variable of an open record as `t<n>`, not as the declared `a`. Bead
        // morphir-ukvn.5.22.7.2.
        "type value:parity/types:aliases#label/body/record: expected { t-5 | label : morphir/SDK:string#string }, found (parity/types:aliases#labeled a)",
      ],
    ),
  ])
}

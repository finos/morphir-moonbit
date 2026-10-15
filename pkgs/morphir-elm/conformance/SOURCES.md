# Elm parity projects

Each directory under `projects/` is an Elm project with a `morphir.json`, its Elm sources in `src/` and
`expected/morphir-ir.json`, the output of `morphir-elm make` from npm `morphir-elm` 2.100.0 (pinned in
`pkgs/morphir-elm/scripts/package.json`).

Do not edit `expected/` or `parity_data_wbtest.mbt` by hand. After you change a project, run
`mise run elm:parity-refresh` from the repository root. It runs `morphir-elm make` on every project and
regenerates `parity_data_wbtest.mbt`.

| Project | Package | Covers | Origin | License |
| --- | --- | --- | --- | --- |
| `custom-types` | `Parity.Custom` | custom types with parameters and `comparable`, `T` and `T(..)` exports, a private type, constructor argument names, `case` on a custom type | own | Apache-2.0, this repository |
| `lambdas` | `Parity.Lambdas` | `\x y ->`, a lambda with a tuple argument, `wild _ y`, `mixed z ( a, b ) w`, `partial a = \b ->`, `paren a = (\x -> a)`, `prefix = (+)`, a value of a function alias (`handler : Handler`), a lambda passed to `List.map`: which arguments morphir-elm lifts into inputs | own | Apache-2.0, this repository |
| `lets` | `Parity.Lets` | let blocks in dependency order (`inOrder`, `reordered`, `x = 1; y = z; z = x`), a let function with and without an annotation, a destructuring let, a self-recursive let function and the `p q r s` cycle (`LetRecursion`) | own | Apache-2.0, this repository |
| `modules` | `Parity.Modules` | an exposed module that imports a module with an alias and `exposing` and uses a qualified name and an exposed type; a module reached only through a value body (kept, `Private`); a module named only in a value signature and a module used only as a constructor in a body (both dropped); an imported-but-unused module; an unreferenced module; module docs | own | Apache-2.0, this repository |
| `operators` | `Parity.Operators` | every operator that morphir-elm maps, on `Int`, `Float`, `Bool`, `String` and `List`; `\|>`, `<\|`, `>>`, `<<`; `(+)` and `(+) 1`; `-x`, `-1`, `-(f x)`, `-x ^ 2`; precedence and associativity; whole numbers in a `Float` context; hex, char and string literals with escapes | own | Apache-2.0, this repository |
| `patterns` | `Parity.Patterns` | `case` with wildcard, variable, int, hex, char, string, tuple, `[]`, `[ a ]`, `[ a, b ]`, `x :: xs`, constructor, nested and qualified (`Maybe.Just`) constructor, `as`, `()` and `True`/`False` patterns; `if` with `else if` | own | Apache-2.0, this repository |
| `records` | `Parity.Records` | a record alias, a record literal with its fields out of order, the alias constructor (`Point 1 2`, partial `Point 1`), `p.x`, `.x` passed to `List.map`, a record update of an argument and of a top-level value, a function on an extensible record | own | Apache-2.0, this repository |
| `sdk-modules` | `Parity.Sdk` | `Morphir.SDK.Decimal` and `Morphir.SDK.LocalDate` types in signatures | own | Apache-2.0, this repository |
| `signatures` | `Parity.Signatures` | variable, tuple, wildcard and unit arguments, leading lambdas (also in parentheses), a lambda with a tuple argument, partial arity, constrained variables (`number`, `comparable`, `appendable`) | own | Apache-2.0, this repository |
| `types-and-aliases` | `Parity.Types` | aliases of every type form and of the SDK types, declaration and module docs, and three doc placements: a doc directly above the first declaration of a module without imports, a `{-|` comment one blank row above a declaration, and a `{-|` comment between two declarations | own | Apache-2.0, this repository |
| `unannotated` | `Parity.Unannotated` | top-level values without an annotation (`un = 1`, `unannot a b = a`, `unannot2 a = a + 1`, `unFloat = 1.5 + 1`, `unRec r = r.x`, `useUn = unannot 1 2`) and an annotated value that uses them | own | Apache-2.0, this repository |

## Round-trip inputs

The round-trip test (`round_trip_wbtest.mbt`) uses the `expected/morphir-ir.json` of every project above and the
three classic fixtures of `pkgs/morphir-elm/fixtures`: `classic-greeting` (`v3-greeting.json`, from finos/morphir
`spec/ir/mck/node-address-fixtures`), and `classic-rentals-v1` and `classic-rentals-v2` (`v1-rentals.json` and
`v2-rentals.json`, from finos/morphir-elm `tests-integration/cli/test-data/rentals`). Their origin and license are in
`pkgs/morphir-ir/conformance/fixtures/README.md`.

## Changes to make morphir-elm build

morphir-elm 2.100.0 refuses some Elm forms, so the projects leave them out:

- `patterns` has no negative literal pattern (`-1 ->`). morphir-elm stops with a `ParserError` at the minus sign,
  and Elm 0.19.1 refuses it too ("It is not possible to pattern match on negative numbers").
- No project has a record pattern, a recursive destructuring, let-polymorphism, top-level mutual recursion or a
  tuple of more than three items. morphir-elm refuses the first four, and Elm refuses the last.

To keep `Cases.elm` under 60 lines, `patterns` matches char and string literals in one `case` on a tuple
(`textual`), and `()` and `True`/`False` in another (`flags`).

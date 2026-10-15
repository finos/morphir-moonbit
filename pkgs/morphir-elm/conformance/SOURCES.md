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
| `elm-attribute-model` | `Morphir.Attribute.Model` | the attribute model of the morphir-elm reference model: a `Bool` alias and an enumeration | finos/morphir-elm `71ca7ee`, `tests-integration/reference-model/attributemodel` | Apache-2.0, finos/morphir-elm |
| `elm-business-terms` | `Morphir.Remote.App` | the business terms of the morphir-elm CLI tests: aliases of `String`, `Int`, `Float` and `Bool` and an enumeration | finos/morphir-elm `71ca7ee`, `tests-integration/cli2-qa-test/test-data/business-terms` | Apache-2.0, finos/morphir-elm |
| `elm-decoration-model` | `Morphir.Decoration.Model` | the decoration model of the morphir-elm tests: record aliases, custom types with arguments, aliases across six modules | finos/morphir-elm `71ca7ee`, `tests-integration/decoration-model` | Apache-2.0, finos/morphir-elm |
| `elm-json-schema` | `TestModel` | the JSON Schema model of the morphir-elm tests: `Dict`, `Set`, `Result`, tuple, `Maybe` and record types, `Decimal`, `LocalDate`, `LocalTime` and `Month`, and aliases across modules | finos/morphir-elm `71ca7ee`, `tests-integration/json-schema/model` | Apache-2.0, finos/morphir-elm |
| `elm-rentals` | `Morphir.Example.App` | the rentals model of the morphir-elm CLI tests: `if`, a comparison and `Result` constructors | finos/morphir-elm `71ca7ee`, `tests-integration/cli/test-data/rentals` | Apache-2.0, finos/morphir-elm |
| `elm-snowpark` | `CompanyAssets` | the Snowpark model of the morphir-elm tests: records, enumerations, `List.map` and `List.filter` with lambdas, `case` on tuples with `Maybe` patterns, a generic value and a module that exposes some of its names | finos/morphir-elm `71ca7ee`, `tests-integration/snowpark/model` | Apache-2.0, finos/morphir-elm |
| `elm-typespec` | `TestModel` | the TypeSpec model of the morphir-elm tests: Dict, Set, Decimal, LocalDate and LocalTime types, custom types and aliases across modules | finos/morphir-elm `71ca7ee`, `tests-integration/typespec/model` | Apache-2.0, finos/morphir-elm |
| `lambdas` | `Parity.Lambdas` | `\x y ->`, a lambda with a tuple argument, `wild _ y`, `mixed z ( a, b ) w`, `partial a = \b ->`, `paren a = (\x -> a)`, `prefix = (+)`, a value of a function alias (`handler : Handler`), a lambda passed to `List.map`: which arguments morphir-elm lifts into inputs | own | Apache-2.0, this repository |
| `lets` | `Parity.Lets` | let blocks in dependency order (`inOrder`, `reordered`, `x = 1; y = z; z = x`), a let function with and without an annotation, a destructuring let, a self-recursive let function, the `p q r s` cycle (`LetRecursion`) and a let value in a `Float` context (`scaled`) | own | Apache-2.0, this repository |
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

## Changes to the projects

The projects from finos/morphir-elm keep their Elm sources as upstream has them, except for the edit listed for
`elm-decoration-model`. Their `morphir.json` has
`"sourceDirectory": "src"`, and `exposedModules` lists every module when upstream has none, because the frontend needs
at least one exposed module:

- `elm-rentals` and `elm-business-terms`: no change (the copies of rentals in `cli2/` and `cli2-qa-test/` are the
  same).
- `elm-typespec`: `exposedModules` added with all six modules.
- `elm-json-schema`: `decorations` removed; `exposedModules` added with all eight modules. The `attributemodel/`
  directory of the upstream project, which only the decoration uses, is not copied.
- `elm-snowpark`: `decorations` removed; `exposedModules` added with all four modules.
- `elm-decoration-model`: `exposedModules` added with all six modules. In `Database.elm`, `type alias Table = Table
  TableName` is changed to `type Table = Table TableName`. Upstream has a recursive type alias, which Elm 0.19.1
  refuses ("This type alias is recursive") and morphir-elm accepts; upstream should make the same change.
- `elm-attribute-model`: `exposedModules` added with both modules.

`elm-typespec` declares the constructor `Bar` twice in `UnionTypes`, which Elm refuses and morphir-elm accepts. The
project keeps it; `round_trip_gaps` pins the result.

morphir-elm 2.100.0 refuses some Elm forms, so the own projects leave them out:

- `patterns` has no negative literal pattern (`-1 ->`). morphir-elm stops with a `ParserError` at the minus sign,
  and Elm 0.19.1 refuses it too ("It is not possible to pattern match on negative numbers").
- No project has a record pattern, a recursive destructuring, let-polymorphism, top-level mutual recursion or a
  tuple of more than three items. morphir-elm refuses the first four, and Elm refuses the last.

To keep `Cases.elm` under 60 lines, `patterns` matches char and string literals in one `case` on a tuple
(`textual`), and `()` and `True`/`False` in another (`flags`).

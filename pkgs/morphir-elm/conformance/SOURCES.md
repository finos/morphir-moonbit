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
| `modules` | `Parity.Modules` | an exposed module that imports a module with an alias and `exposing` and uses a qualified name and an exposed type; a module reached only through a value body (kept, `Private`); a module named only in a value signature and a module used only as a constructor in a body (both dropped); an imported-but-unused module; an unreferenced module; module docs | own | Apache-2.0, this repository |
| `sdk-modules` | `Parity.Sdk` | `Morphir.SDK.Decimal` and `Morphir.SDK.LocalDate` types in signatures | own | Apache-2.0, this repository |
| `signatures` | `Parity.Signatures` | variable, tuple, wildcard and unit arguments, leading lambdas (also in parentheses), a lambda with a tuple argument, partial arity, constrained variables (`number`, `comparable`, `appendable`) | own | Apache-2.0, this repository |
| `types-and-aliases` | `Parity.Types` | aliases of every type form and of the SDK types, declaration and module docs, and three doc placements: a doc directly above the first declaration of a module without imports, a `{-|` comment one blank row above a declaration, and a `{-|` comment between two declarations | own | Apache-2.0, this repository |

# Morphir Elm

## Purpose

`finos/morphir-elm` generates Elm source from current Morphir IR. The package `finos/morphir-elm/backend` lowers
IR to the [elm-syntax](https://package.elm-lang.org/packages/stil4m/elm-syntax/7.3.9/) AST of
[moonrockz/krueger](https://github.com/moonrockz/krueger) and prints it in the elm-format layout.

The backend has no engine, host, filesystem, process or network imports. It takes an `IRFile` and options, and it
returns the generated files as text. The same input and options give the same output bytes. The engine registers
the backend as the generation backend `elm`.

## Use from the engine

Set the backend in `morphir.toml`. The table `[backends.elm]` holds the options. All keys are optional.

```toml
[pipeline]
backend = "elm"

[backends.elm]
profile = "model"            # "model" (default) | "literal"
placeholders = "refuse"      # "refuse" (default) | "debug-todo"
width = 120
elm_package = "finos/morphir-elm 22.0.2"

[backends.elm.mapping]
"morphir/SDK:basics#add" = { operator = "+" }
"morphir/SDK:list#map" = { function = "List.map" }
"morphir/SDK:decimal#decimal" = { type = "Decimal.Decimal", import = "MyCo.Decimal as Decimal" }
"morphir/SDK:basics#max" = {}

[backends.elm.packages]
"acme/common" = { package = "acme/common 1.0.0" }
```

- `profile` selects the profile. See [Profiles](#profiles).
- `placeholders` tells the backend what to do with a value that has no body. `refuse` stops generation with
  `elm.placeholder`. `debug-todo` writes `Debug.todo "<reason>"`.
- `width` is the line width of the printer. It must be an integer from 1 to 1000.
- `elm_package` is the Elm package that supplies unmapped `Morphir.SDK` modules. The value is
  `"author/name major.minor.patch"`. The default is `finos/morphir-elm 22.0.2`.
- `mapping` adds, replaces or removes mapping entries. See [Mapping](#mapping).
- `packages` maps a Morphir dependency package to an Elm package. An entry has only the form
  `{ package = "author/name 1.2.3" }`.

The engine checks the table before it runs the backend. An unknown key or a bad value gives `elm.invalid_option`.
A bad mapping entry gives `elm.invalid_mapping`.

The `elm` backend declares no build targets. The engine uses `pipeline.validation = "source-only"` for it, and it
refuses `"required"` with `build.unsupported_target`.

## Profiles

There are two profiles.

The `model` profile (the default) writes idiomatic Elm. A reference that has a mapping entry uses that entry. The
IR for `a + b` becomes:

```elm
add : Int -> Int -> Int
add a b =
    a + b
```

The `literal` profile ignores the mapping. Every reference stays qualified. Use it as a debug view of the IR. The
same IR becomes:

```elm
add : Morphir.SDK.Basics.Int -> Morphir.SDK.Basics.Int -> Morphir.SDK.Basics.Int
add a b =
    Morphir.SDK.Basics.add a b
```

If you set `mapping` with the `literal` profile, the backend gives a warning and ignores the entries.

## Mapping

A mapping entry tells the `model` profile how to write a Morphir reference in Elm. An entry is one of these:

- `{ operator = "+" }`: an Elm operator. With two arguments it becomes `a + b`. With fewer arguments it becomes a
  prefix operator, for example `(+) a`. An operator entry takes no `import`.
- `{ function = "List.map" }`: an Elm value or constructor, qualified or not.
- `{ type = "Dict.Dict" }`: an Elm type, qualified or not.
- `{}`: removes the entry. The reference falls back to the qualified form.

A `function` or `type` entry can have an `import`, for example `import = "MyCo.Decimal as Decimal"`. The backend
adds that line to the imports of the module. With no `import`, the backend imports the qualifier of the name, unless
Elm imports that module by default.

### The built-in table

`scripts/generate-builtin-mapping.py` writes `backend/mapping_builtin.mbt` from
`pkgs/morphir-sdk/conformance/bindings.json`. The script maps every binding whose `semanticSource` is
`elm/core 1.0.5` to the elm/core function of the same name. It adds a hand-written list of types, constructors and
operators. The table has elm/core semantics only. Other SDK references stay qualified, for example
`Morphir.SDK.LocalDate.addDays`. Do not edit `mapping_builtin.mbt` by hand. Run the script again.

Every built-in entry is fully qualified, for example `Basics.max`, `Maybe.Just` or `Basics.Int`. The backend writes
the name bare (`max`, `Just`, `Int`) only when a default import exposes it and nothing can capture it. A lower-case
name must not be a top-level value of the module or a binder in the declaration. An upper-case name must not be a type
or constructor of the module. In Elm, a module's own names win over a default import. A user entry keeps its text as
written, so a bare entry such as `{ function = "max" }` always prints bare.

The script writes each key in the canonical form that migration gives for legacy IR. It splits the Elm name at
camelCase boundaries and digit runs, and joins a run of single letters into one initialism. For example, `map2` has the
key `morphir/SDK:list#map-2` and `LT` has the key `morphir/SDK:basics#LT`.

### Namespaces

Types and values have separate namespaces in the mapping. One FQName can be a type and a function, for example
`morphir/SDK:basics#never`. A type reference looks only at type entries. A value or constructor reference looks only
at value entries.

An override goes to the namespace of its kind. A `type` entry replaces the type entry for its key. An `operator` or
`function` entry replaces the value entry for its key. An empty entry `{}` removes the key from both namespaces.

### Keys

A key is any IR FQName in canonical text form, for example `morphir/SDK:basics#add`. The key does not have to be an
SDK reference. You can map references in your own packages to existing Elm code. A key that is not a canonical FQName gives
`elm.invalid_mapping`. If the key parses but has a different spelling, the detail gives the canonical spelling.

## Output

The backend writes one Elm package project:

```
elm.json
morphir.json
src/<Package>/<Module>.elm
```

- Each IR module becomes one file in `src/`. The Elm module name is the package path followed by the module path,
  for example `Acme.Shapes.Geometry` for package `acme/shapes` and module `geometry`.
- `elm.json` has `"type": "package"`. Its name is the first part of the Morphir package path, `/`, and the other
  parts joined with `-`, for example `acme/shapes`. It exposes the public modules. If no module is public, it exposes
  all modules.
- `morphir.json` has the Morphir package name, `"sourceDirectory": "src"` and the exposed modules.

The `elm.json` is a package, not an application. An application `elm.json` must list every indirect dependency with
an exact version, and that needs a dependency solver. A package `elm.json` takes version ranges. The dependencies
are:

- `elm/core` `1.0.5 <= v < 2.0.0`, always.
- The `elm_package`, only when the code uses an unmapped `Morphir.SDK` reference.
- One entry for each dependency package that has an entry in `packages`. A dependency package with no entry gives a
  warning, not an error. `elm make` then reports the missing modules.

### Declarations

- Declarations keep the IR order. Imports are sorted.
- Public types and values are exposed. Private ones are not. A custom type with public constructors is exposed as
  `T(..)`. A custom type with private constructors is exposed as `T`.
- An opaque type specification becomes a custom type with one hidden constructor, `<Type>Opaque`.
- Module documentation becomes the module doc comment. Member documentation becomes the doc comment of the
  declaration.
- An Elm reserved word as a name gets the suffix `_`, for example `type_`.
- A type variable with a `typeclass` constraint gets the Elm prefix of that class: `number`, `comparable`,
  `appendable` or `compappend`. An unconstrained variable whose name starts with one of these prefixes gets the
  prefix `t`, so Elm does not read it as constrained.

### Attributes

Elm has no place for some IR data. The backend writes that data as attributes in an `attributes` code block in the
doc comment. The attribute value is Elm data, so krueger can read it back.

```attributes
@morphir.entry { kind = "main", name = "run" }
@morphir.annotation { fqname = "acme/api:tags#stable" }
@morphir.external { platform = "js", name = "Math.max" }
```

- `@morphir.entry` marks the target value of an entry point in an `Application`.
- `@morphir.annotation` holds an annotation of a value specification. A compact annotation has `fqname` and an
  optional `text`. A structured annotation has `fqname` and `arguments`.
- `@morphir.external` holds one binding of an `ExternalBody`.

The arguments of a structured annotation must be data: literals, unit, lists, tuples, records, constructors and
constructor applications of data. Any other value, for example a function application or a variable, gives
`elm.annotation_argument`.

### Local names

Elm rejects a local name that shadows another name in scope. The backend renames such a name with a numeric suffix,
for example `x` becomes `x_1`.

Before each top-level value, the backend resets the set of used local names to the top-level value names of the
module. Locals in different top-level values do not affect each other. Inside one top-level value, a name that two
branches or two lambdas both use gets a suffix in the second one. This output is valid Elm, but it can be less easy
to read. The suffix counter does not reset, so the numbers increase through the module.

`let` functions have no type signature. Elm reads type variables in a `let` signature as new rigid variables, so a
signature could make valid code fail.

## Refusals

The backend raises `ElmGenerationError`. `Refused` holds one `Problem`. `Failed` holds the problems of all failing
modules. A `Problem` has a `code`, a `node_path` and a `detail`. The `node_path` is the canonical FQName of the IR
node, or the option key.

Generation of a module stops at its first problem. The backend tries all modules, so one run reports every failing
module.

| Code | Cause |
| --- | --- |
| `elm.tuple_arity` | A tuple with fewer than two or more than three elements. Elm tuples have two or three. |
| `elm.derived_type` | A derived type. |
| `elm.decimal_literal` | A decimal literal. There is no decimal construction mapping yet. |
| `elm.placeholder` | A construct with no body while `placeholders = "refuse"`, a custom type with no constructors, or an incomplete type definition. |
| `elm.invalid_mapping` | A mapping entry that is not valid, for example a bad key or a constructor that maps to an operator. |
| `elm.print` | krueger could not print the AST. The path names the IR declaration. This is a backend defect. |
| `elm.int_literal` | An integer lexeme outside the Int64 range. |
| `elm.document_literal` | A document literal. Elm has no document literal. |
| `elm.literal_pattern` | A float or decimal pattern. Elm rejects these patterns. |
| `elm.unsupported_constraint` | A `typeclass` constraint that has no Elm class, or that is not text or a list of text. |
| `elm.name_collision` | Two IR names in one module give the same Elm name. |
| `elm.annotation_argument` | A structured annotation argument that is not data. |
| `elm.invalid_option` | An unknown option key or a bad option value. |
| `elm.cancelled` | The caller cancelled the generation. |

## Limits

- The backend does not write regular comments. krueger prints doc comments only.
- Derived types and decimal literals are refused (`elm.derived_type` and `elm.decimal_literal`).
- `elm make --optimize` rejects `Debug.todo`. Code generated with `placeholders = "debug-todo"` compiles only
  without `--optimize`.
- The `finos/morphir-elm` Elm package has no `Morphir.SDK.Maybe` module. An unmapped `morphir/SDK:maybe` reference,
  for example `morphir/SDK:maybe#has-value`, gives code that `elm make` rejects. Add a mapping entry for it.
- `packages` takes only Elm packages. Dependency source directories are not supported.

## Frontend

The frontend reads an Elm project and gives the v4 Morphir IR of it. The output is the same as the output of
`morphir-elm make` 2.100.0, except for value bodies.

```moonbit
pub fn compile_project(
  sources : Array[ElmSource],   // every .elm file: path relative to the source directory, and content
  package_name : String,        // the dotted package name, for example "My.Pkg"
  exposed : Array[String],      // the exposed modules relative to the package, as in morphir.json
) -> @ir.IRFile raise ElmFailed
```

The result is a `Library` with no dependencies. `ElmFailed` holds the problems of the first pass that failed. Each
pass reports all of its problems together. The passes are: parse, module rules (module name, port and effect
modules), import cycles, exposed modules, exports and imports, name references, and lowering. As in morphir-elm,
the parse and import cycle passes check every source. The other passes check only the modules that morphir-elm
processes (rule 2), also when such a module is not in the output. A problem of these kinds in a module that nothing
imports does not stop the compile. An `ElmProblem` has a `code`, a `message`, the source `path` and the `location`
in the file when it is known. An empty `exposed` list gives a problem with an empty path. A missing exposed module
gives a problem at the source path where the module must be.

There are four packages:

- `finos/morphir-elm/mapping`: Elm names to Morphir names, and the elm/core table.
- `finos/morphir-elm/frontend`: parsing, module rules, module selection, access, docs and `compile_project`.
- `finos/morphir-elm/frontend/resolve`: the project symbol table, exports, imports and name resolution.
- `finos/morphir-elm/frontend/lower`: type definitions and value signatures to IR.

| Code | Cause |
| --- | --- |
| `elm.parse` | A file does not parse. |
| `elm.module_name` | The module name does not match the file path, or does not start with the package name. |
| `elm.import_cycle` | The imports form a cycle. |
| `elm.exposed_module` | The exposed list is empty, or an exposed module has no source file. |
| `elm.unresolved_name` | A name, or an entry of an exposing list, that does not resolve. |
| `elm.ambiguous_name` | A name used in the code that two imports give with different meanings. |
| `elm.unsupported_module` | An import of a module that is not a project, elm/core, platform or `Morphir.SDK` module. |
| `elm.unsupported_value` | A reference to an elm/core value or operator that has no Morphir SDK binding. |
| `elm.unsupported` | A port, an effect module, an infix declaration, top-level destructuring, or a record pattern as a function argument. |
| `elm.unbound_type_variable` | A type variable that the type alias or custom type does not declare. |
| `elm.signature_arity` | A type annotation with fewer arguments than the definition has inputs. |

The frontend follows these morphir-elm rules (probes of `morphir-elm make` 2.100.0):

1. The `morphir.json` `exposedModules` entries are module names relative to the package name (`"Types"` for
   `My.Pkg.Types`).
2. morphir-elm processes the exposed modules and the project modules that they import, transitively. The output
   keeps the exposed modules and the processed modules that they reach in the module graph, transitively. A module
   depends on the modules of the names in its type definitions (the constructors of a custom type count, whatever
   their access) and of the value references in its value bodies: values, operators other than `<|` and `|>`, and
   `Basics.negate` for a negation of anything but a number literal. A module that is named only in value
   signatures, used only through constructors in bodies, imported and not used, or not imported, is not in the
   output. The graph compares module paths without the package, so a project module with the path of an SDK module
   that is used (for example `My.Pkg.Basics` and `Int`) is kept. Every output module keeps all of its declarations.
3. The exposed modules are `Public`. A module that is not exposed is `Public` when an exposed module shows one of
   its types: as the target of a public type alias, as a constructor argument of a public type with public
   constructors, or in the signature of a public value. This continues through the public definitions of the types
   that it reaches. morphir-elm takes the names in Elm order and follows only the first name that it finds in each
   module. All other output modules are `Private`.
4. A type exported as `T` is `Public` with `Private` constructors. `T(..)` gives `Public` constructors. A type or
   value that the module does not export is `Private`.
5. The module path is the module name without the package prefix (`My.Pkg.Types` in package `My.Pkg` is
   `["types"]`).
6. A doc keeps the raw text between `{-|` and `-}`: `{-| A point. -}` gives `" A point. "`. A declaration without a
   doc gets `""`. The module doc is the first `{-|` comment in the file that is not a declaration doc, with its
   trailing whitespace removed. A module without one has no doc.
7. A `{-|` comment is the doc of a declaration only when the declaration starts on the row directly after the row
   where the comment ends. A blank line between them makes the comment an ordinary comment. Thus a `{-|` comment
   directly above the first declaration is the doc of that declaration, not the module doc.
8. The value inputs are the function arguments, then the arguments of leading lambdas in the body, looking through
   parentheses, while each is a plain variable. The first other pattern stops the inputs. The output type is the
   annotation with one arrow removed for each input.
9. A record pattern as a function argument fails in morphir-elm. The frontend gives `elm.unsupported` for it.

Value bodies are `IncompleteBody(inputs, Some(output), Draft, None)`. Plan 2 of the frontend lowers the bodies.

## Tests

```shell
moon test pkgs/morphir-elm/backend       # unit and generation tests
moon test pkgs/morphir-elm/conformance   # frontend parity with morphir-elm make
mise run test:elm                        # elm make on the generated fixture projects
mise run elm:parity-refresh              # regenerate the parity corpus after a project change
```

The parity test compiles each Elm project in `pkgs/morphir-elm/conformance/projects` with `compile_project` and
compares the result with `expected/morphir-ir.json`, the output of the pinned npm `morphir-elm` 2.100.0. It
compares the modules, types and values, with their access and docs, the type definitions, and the value inputs
and output. It does not compare value bodies or type attributes, and a doc of `None` is the same as `""`. A known
difference goes in `parity_gaps` (in `parity_gaps_wbtest.mbt`) with its reason and a bead. The test fails when a
pinned difference goes away, so remove the line when the gap closes.

After you change a project, run `mise run elm:parity-refresh` from the repository root. It needs network access
for `npm ci`. It runs `morphir-elm make` on every project and writes `expected/morphir-ir.json` and
`parity_data_wbtest.mbt`, both with the IR as compact JSON. Commit both. CI runs the refresh in the native build job and fails when `pkgs/morphir-elm/conformance` changes.

`mise run test:elm` installs the pinned npm `elm` 0.19.1 package in `scripts/` and runs
`scripts/test-elm-make.mjs`. The script runs `pkgs/morphir-elm/acceptance`, which prints the generated projects for
the fixtures `rentals`, `shapes` and `specs` as JSON. It writes each project to a temporary directory and runs
`elm make` on its modules. The `specs` project uses `placeholders = "debug-todo"`. The first run needs network access,
because `elm make` downloads its packages. CI runs this task in the native build job.

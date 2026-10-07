# Morphir SDK for MoonBit

`finos/morphir-sdk` provides pure, synchronous runtime values and functions for generated Morphir programs. It has no host, filesystem, network, process, or Scheme dependency. The packages compile on native, JavaScript, wasm, and wasm-gc.

The root package defines `Order`, `SdkError`, UTF-16 `Text` and `Character`, and Elm-compatible lexical string ordering. Subpackages cover `integer`, `basics`, `int`, `decimal`, `char`, `string`, `list`, `maybe`, `result`, `dict`, and `set`. The general `Integer` wraps MoonBit core `BigInt`; `Int8` through `Int64` conversions check bounds. Lists, dictionaries, and sets return new values on updates. Dict and Set require a total Morphir comparator when constructed; use `@string.compare` for `Text` keys and `@sdk.string_order` for MoonBit `String` keys. Generic MoonBit `Compare` uses a different String order.

## Sources and inventory

The binding inventory is [conformance/bindings.json](conformance/bindings.json). It contains all 248 declared values, their pinned Elm specification fragments and source lines, MoonBit bindings, semantic source, and module test paths. Regenerate it with:

```sh
python3 pkgs/morphir-sdk/conformance/generate_inventory.py --elm-checkout /path/to/morphir-elm
```

The script reads `finos/morphir-elm` at commit `bc99af69a8b24d391311fae3822a87eafef3c334` with `git show`, so the checkout can be on any branch. Behavioral references are `elm/core` 1.0.5 and `chain-partners/elm-bignum` 1.0.1. The generated Unicode case tables come from Node's Unicode 17.0 ECMAScript casing; regenerate them with `node pkgs/morphir-sdk/string/tools/generate-case-tables.mjs` using a Node release that reports Unicode 17.0.

The inventory records every typed binding and its test status. All 248 canonical names have typed MoonBit bindings and Scheme adapters. The [Elm oracle corpus](conformance/elm_oracle.json) executes 245 names in the pinned Elm runtime with 310 examples, including 65 boundary cases. `Basics.never` is uninhabited. The pinned Elm `Int64` source emits invalid JavaScript for its lower bound, so `fromInt64` and `toInt64` use the separate [exact-integer extension corpus](conformance/exact_integer_extension.json). The Scheme tests embed all 310 executable Elm examples plus 14 mathematical extension cases and run on all four targets. The [conformance recipe](conformance/README.md) records how to regenerate them and what the oracle projects for opaque values.

## Semantic boundaries

- `integer.divide`, `remainder_by`, and `mod_by` truncate toward zero and raise `SdkError.DivisionByZero` for a zero divisor. The second argument is the dividend for `mod_by` and `remainder_by`.
- `basics.divide` is IEEE Double division. Nonfinite Float to Integer or Decimal conversion raises `SdkError.InvalidNumber`.
- `decimal.Decimal` is numerical: its coefficient is exact, with a minimum arithmetic and parse exponent of −32. It does not preserve an IR decimal literal's original spelling or scale. Division returns `Option`, and rounding is half to even.
- SDK String functions take `Text`, an immutable copy of UTF-16 code units. Length and slicing count code units; traversal groups surrogate pairs as Elm characters. `split("", ...)` and slices can return isolated surrogate halves. `Text::to_string` checks that all units form valid Unicode before crossing into a MoonBit `String` host or Scheme value; it raises `SdkError.UnrepresentableText` for isolated surrogates. `Text::from_string` accepts host strings.
- `Character` stores UTF-16 units because Elm Char can hold a surrogate or a case expansion. String casing uses pinned, locale-independent Unicode 17 tables. `char.to_locale_upper` and `to_locale_lower` use the same default casing; `char.to_upper` can return `SS` for `ß`.
- `char.from_code` returns U+FFFD for out-of-range values and preserves surrogate code units, matching Elm's JavaScript kernel.
- Dict and Set comparators may raise `SdkError.InvalidComparison` for unsupported keys such as NaN. Both collections retain the comparator supplied at construction; callers must use the same ordering for values of a given key type.
- The Morphir Scheme backend installs all 248 canonical SDK names as native accelerators and curried Scheme references. Higher-order callbacks call through the Scheme runtime. Scheme's own rational `/` remains a separate language operation.

## SDK specification

The `spec` package (`finos/morphir-sdk/spec`) gives the IR specification of the SDK:

- `sdk_package_name()` is `morphir/SDK`.
- `sdk_specification()` is its `@ir.PackageSpecification`: 248 values in 10 modules, with the SDK types and
  constructors.

Type inference (`finos/morphir-typing`) has no built-in SDK. Callers add this specification to its dependencies.
The package depends only on `finos/morphir-ir`.

### `sdk.scm` is the source of truth

[spec/sdk.scm](spec/sdk.scm) holds the specification in the Morphir Scheme specification notation (see the
[Morphir Scheme README](../morphir-scheme/README.md#specification-notation)). Edit `sdk.scm` by hand. Do not edit
`spec/sdk_data.mbt`: it is generated canonical v4 JSON of a `Specs` distribution, which the package decodes once,
on first use.

```sh
mise run sdk-spec:generate   # regenerate spec/sdk_data.mbt from sdk.scm
mise run sdk-spec:check      # check sdk.scm against bindings.json, and check that sdk_data.mbt is fresh
```

Both tasks run the native `sdkgen` tool of `finos/morphir-typing-tools`. `sdk-spec:check` fails when:

- a `bindings.json` signature is missing from `sdk.scm`, or `sdk.scm` has a value that `bindings.json` lacks;
- a parameter name differs, or a type differs up to a renaming of type variables;
- `sdk_data.mbt` is not what `sdk-spec:generate` would write.

The type comparison ignores attributes, and the renaming may pair any two variables. So the check does not catch
a change of constraint class, for example `number` in `bindings.json` against a plain `a` in `sdk.scm`.

Names in `sdk.scm` are migrated canonical names, such as `map-2`, `from-int-8` and `LT`. The check maps each
`bindings.json` name with the same rule as the Elm mapping generator: it splits camel case and digit runs, then
applies the `Name::from_words` initialism rule.

The IR refuses two parameters with one name, but some morphir-elm signatures have them: `Result.map3`, `map4` and
`map5` have `result2` twice. A repeated parameter name takes the next free number, so `result-1`, `result-2`,
`result-2` becomes `result-1`, `result-2`, `result-3`. The bootstrap and the check use the same rule, so these
three values have parameter names that differ from `bindings.json`.

## Check

```sh
moon fmt --check pkgs/morphir-sdk
moon test --target native
moon test --target js
moon test --target wasm
moon test --target wasm-gc
moon test --target native pkgs/morphir-scheme/backend
```

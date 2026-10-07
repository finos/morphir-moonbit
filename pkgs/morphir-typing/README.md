# Morphir Typing

`finos/morphir-typing` infers and checks the types of Morphir IR. It does not depend on a source language, and it
depends only on `finos/morphir-ir`. Any producer can use it: a frontend that does not know its types writes the
unknown marker, and this module fills in the types. A backend that needs types, such as the MoonBit generator, can
then use the IR.

The packages build and test on `wasm`, `wasm-gc`, `js` and `native`.

## The `infer` API

```moonbit
let filled = @typing.infer(file, deps, Fill) catch {
  InferenceFailed(problems) => ...
}
```

- `file` is an `@ir.IRFile`: a `Library`, an `Application` or a `Specs` distribution.
- `deps` maps each package name to its `@ir.PackageSpecification`. The file's own dependencies are added to it.
- `infer` raises `InferenceFailed(problems)` when there is any problem, in either mode. It collects the problems of
  every binding group first, and sorts them by logical path.

There are two modes:

| Mode | Result |
| --- | --- |
| `Fill` | The file with an `inferred_type` on every `Value` and `Pattern` of every body that inference walks. Each signature type that has a marked variable is replaced by its solution. |
| `Check` | The input file, unchanged. Use it to check the types that a file already has. |

In both modes, an existing `inferred_type` that does not agree with inference is `annotation_mismatch`. `Fill` does
not overwrite it silently.

A `Specs` file has no bodies. `Fill` returns it unchanged. `Check` checks that every type reference in its
signatures and type bodies resolves.

`types_equivalent(a, b)` compares two IR types up to a bijective renaming of their variables. It ignores
attributes, and it treats `Tuple []` and `Unit` as the same type. It does not expand aliases.

### The caller supplies the SDK

This module has no built-in SDK, because it depends only on `finos/morphir-ir`. Add the SDK specification to
`deps`:

```moonbit
let deps = Map::from_array([
  (@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification()),
])
```

`@sdk_spec` is the package `finos/morphir-sdk/spec`. Without it, every reference to `morphir/SDK` is
`missing_dependency`.

## The unknown marker

A type variable is *unknown* when its attributes hold `extensions["morphir.inference"] = Data::Text("unknown")`.
`@typing.unknown_type(name)` makes such a variable. Inference may solve an unknown variable to any type.

- All occurrences of one unknown name in one signature are the same variable.
- A top-level value is *declared* when it has an output type and no signature variable is unknown. Other
  values are *undeclared*.
- Classic IR has no markers, so inference checks it strictly.

## Rigid variables

Every type variable in a signature that is not unknown is *rigid*, as in an Elm annotation.

- A rigid variable stands for any type. The body must work for every type.
- When the body needs a narrower type, the problem is `rigid_variable`. For example, `id : a -> a` with the body
  `\x -> 1` fails, because `1` is a number and `a` is any type.
- A class failure at a rigid variable is also `rigid_variable`, not `no_instance`. For example, a body that needs
  `comparable` for a rigid `a` fails with `rigid_variable`. This includes a rigid inside a type, as in
  `List a` used as `comparable`.
- A rigid variable takes its class from its `typeclass` constraint, else from its name prefix.
- The rigid variables of a let annotation belong to that let. If one escapes into the type of an outer value,
  the problem is `rigid_variable`.
- A declared value is used through its scheme everywhere, also in its own body. So it can be polymorphically
  recursive.

## How inference works

Inference is constraint-based Hindley-Milner, in the manner of morphir-elm's `Morphir.Type.Infer`. It uses meta
variables, a union-find substitution, levels for generalization and an occurs check.

1. The environment holds the types, constructors and values of every dependency, and the types and constructors
   of the file.
2. Each declared signature enters the environment as a scheme before any body is solved.
3. The undeclared values form binding groups: the strongly connected components of the references between them.
   The groups are solved in dependency order. Inside a group, the undeclared values are monomorphic. They are
   generalized after the group.
4. Each group stops at its first problem. Other groups go on. A value of a failed group gets an unconstrained
   scheme, so its dependants do not report the same problem again.
5. `LetDefinition` generalizes, which is let-polymorphism. `LetRecursion` is one group. `Destructure` binds its
   variables monomorphically.

### Literals

| Literal | Type |
| --- | --- |
| Integer | A fresh `number` variable |
| Float | `Float` |
| Decimal | `decimal#decimal` |
| String | `String` |
| Char | `Char` |
| Bool | `Bool` |
| Document | `morphir/SDK:document#document` when that type is known, otherwise `unsupported` |

### Other bodies

- A `NativeBody` or an `IncompleteBody` uses its signature as declared. Inference does not walk an incomplete
  body's value.
- An `ExternalBody` checks its fallback value against the signature.
- A `Hole` has its declared type, or a fresh variable.

### Output

- Inference expands an alias only when unification needs it. So a type keeps the alias references that it got
  from a signature or a constructor.
- Variables are named in walk order: `a`, `b`, …. A constrained variable takes its class as a prefix:
  `comparable-a`. Names of rigid variables are reserved first, so a new name never captures one.
- The output is deterministic: the same input gives the same bytes.

## Constraint classes

The four classes of Elm apply to type variables. A variable's class comes from its `typeclass` constraint, else
from its name prefix (`number`, `comparable`, `appendable`, `compappend`). Classes propagate through unification.

| Class | Satisfied by |
| --- | --- |
| `number` | `Int`, `Float` |
| `comparable` | `Int`, `Float`, `Char`, `String`, `List c`, tuples of 2 or 3 comparables |
| `appendable` | `String`, `List a` |
| `compappend` | `String`, `List c` |

- `comparable` and `appendable` together give `compappend`.
- `number` and `comparable` together give `number`.
- Any other pair is `no_instance`.
- `Decimal` and `LocalDate` belong to no class.

## Records and rows

`Record` and `ExtensibleRecord` unify through row variables.

| Value | Type rule |
| --- | --- |
| `Field(v, f)` | `v : { r \| f : t }`, and the result is `t` |
| `FieldFunction f` | `{ r \| f : t } -> t` |
| `UpdateRecord` | The result has its target's type. Each field that it sets must exist with the new value's type. |
| Record literal | Closed: it has exactly its fields |

A closed record that lacks a field gives `missing_field`.

Aliases expand during unification. Opaque types and custom types are nominal. A constructor has the type
`args -> T params`.

## Diagnostics

Each problem is an `InferenceProblem { code, node, message, expected, found, source }`. `node` is a logical path.
`expected` and `found` are IR types when the problem has two types. `source` is the node's source location, if the
IR has one. Messages are short sentences with types in Elm notation.

| Code | Meaning | Example message |
| --- | --- | --- |
| `type_mismatch` | Two types do not unify | expected Int, found String |
| `occurs` | The type would be infinite | the type would be infinite: a occurs in List a |
| `rigid_variable` | A body narrows an annotated variable | the variable `a` is annotated as any type, but the body needs number |
| `no_instance` | No type satisfies the constraint class | the type String is not a number |
| `missing_field` | The record has no such field | the record has no field `count` |
| `unknown_reference` | The name is not defined, but its package is known | `x` is not defined |
| `missing_dependency` | No specification for the package of the name | there is no specification for the package of `x` |
| `arity` | A non-function is applied, or a constructor pattern has the wrong number of arguments | the type Int is not a function, so it cannot take an argument |
| `annotation_mismatch` | An existing `inferred_type` disagrees with inference | the node has the type Int, but inference gives String |
| `unsupported` | A construct that inference does not handle | inference does not support `x` |

### Cyclic aliases

An alias that refers to itself, directly or through other aliases, is `unsupported`. Examples are `A = A`,
`A = B` with `B = A`, and the growing `T a = T (List a)`. Inference cannot expand such an alias.

- The problem is at the type path `type:<package>:<module>#<name>`, in both modes.
- This includes cyclic aliases in dependencies. A file then fails even when it does not use the alias.

## Logical paths

A logical path names one `Value` or `Pattern` node. It does not depend on the JSON encoding.

- A declaration's root is `value:<package>:<module>#<name>`, with canonical names, for example
  `value:acme/app:orders#total`.
- Each step below adds `/<step>` to the path of the parent. `<i>` is a 0-based index and `<name>` is a canonical
  name.

| Child | Steps |
| --- | --- |
| A declaration's body | `/body` |
| `Apply` | `/function`, `/argument` |
| `Lambda` | `/pattern`, `/body` |
| `LetDefinition` | `/definition/body`, `/in` |
| `LetRecursion` | `/definitions/<name>/body`, `/in` |
| `Destructure` | `/pattern`, `/value`, `/in` |
| `IfThenElse` | `/condition`, `/then`, `/else` |
| `PatternMatch` | `/subject`, `/cases/<i>/pattern`, `/cases/<i>/body` |
| `Tuple`, `List` | `/items/<i>` |
| `Record` | `/fields/<name>` |
| `Field` | `/record` |
| `UpdateRecord` | `/record`, `/fields/<name>` |
| `AsPattern` | `/pattern` |
| `TuplePattern` | `/items/<i>` |
| `ConstructorPattern` | `/args/<i>` |
| `HeadTailPattern` | `/head`, `/tail` |

For example, `value:acme/app:orders#total/body/argument` is the argument of the `Apply` that is the body of
`total`. The grammar is defined in `paths.mbt`. A later plan moves it to `finos/morphir-ir/identities`.

## Out of scope

- Type classes other than the four built-in classes.
- Inference across a package whose specification is missing. That is `missing_dependency`.
- Expansion of cyclic aliases. They are `unsupported`.
- Document literals when no `morphir/SDK:document#document` type is known. The SDK specification has no such
  type today, so they are `unsupported`.
- Source languages. This module reads only IR. The engine stage, which runs inference inside the Morphir
  pipeline, comes in a later plan.

# Morphir Typing

`finos/morphir-typing` infers and checks types in Morphir IR. It does not depend on a source language. It
depends only on `finos/morphir-ir`.

## Use

```moonbit
let filled = @typing.infer(file, deps, Fill) // or Check
```

- `deps` gives the specification of each package that the file uses. The caller supplies the SDK.
- `Fill` returns the file with an `inferred_type` on every `Value` and `Pattern` of the bodies that it infers.
  Signature types that carry the unknown marker (`@typing.unknown_type`) are replaced by their solutions.
- `Check` returns the file unchanged.
- In both modes, `infer` raises `InferenceFailed` with every problem, in the order of their logical paths. An
  existing `inferred_type` that disagrees with inference is `annotation_mismatch`.
- `types_equivalent` compares two types up to a bijective renaming of their variables.

## How it works

Inference is constraint-based Hindley-Milner:

- internal types with meta variables, rigid variables and record rows;
- the constraint classes `number`, `comparable`, `appendable` and `compappend`;
- unification with an occurs check, level tracking and alias expansion;
- an environment built from package specifications and definitions, with cyclic alias detection;
- inference over values and patterns, with let-polymorphism, record rows and logical node paths;
- binding groups: the strongly connected components of the file's undeclared values, solved in dependency
  order. A declared value is used through its scheme everywhere, so it can be polymorphically recursive.

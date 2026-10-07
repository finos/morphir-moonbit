# Morphir Typing

`finos/morphir-typing` infers and checks types in Morphir IR. It does not depend on a source language. It
depends only on `finos/morphir-ir`.

The module is in progress. It has the solver at the base of a constraint-based Hindley-Milner inference:

- internal types with meta variables, rigid variables and record rows;
- the constraint classes `number`, `comparable`, `appendable` and `compappend`;
- unification with an occurs check, level tracking and alias expansion.

Expression inference and the public `infer` entry point come next.

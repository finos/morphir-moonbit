# Morphir Typing

`finos/morphir-typing` infers and checks types in Morphir IR. It does not depend on a source language. It
depends only on `finos/morphir-ir`.

The module is in progress. It has the solver at the base of a constraint-based Hindley-Milner inference:

- internal types with meta variables, rigid variables and record rows;
- the constraint classes `number`, `comparable`, `appendable` and `compappend`;
- unification with an occurs check, level tracking and alias expansion;
- an environment built from package specifications and definitions, with cyclic alias detection;
- inference over values and patterns, with let-polymorphism, record rows and logical node paths.

The public `infer` entry point comes next.

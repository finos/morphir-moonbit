---
order: 50
---

# Specification notation

The `finos/morphir-scheme/spec` package reads and writes package specifications in a small notation. This chapter
covers the notation, its forms, type expressions and naming rules, the API, and the errors it reports.

Chapters: [index](../README.mbt.md) · previous: [Transform scripts](../pipeline/README.mbt.md)

## The notation

`finos/morphir-scheme/spec` reads and writes package specifications in a small notation. The notation is data. It
is read with the Morphir Scheme reader and is never evaluated. Each file holds one package. Line comments, block
comments and datum comments are allowed. `pkgs/morphir-sdk-spec/sdk.scm` is written in this notation.

```scheme
(package "morphir/SDK"
  (module basics
    (doc "Core types.")
    (type order (custom (LT) (EQ) (GT)))
    (val add ((a number) (b number)) number)
    (val compare ((a comparable) (b comparable)) basics#order))
  (module maybe
    (type maybe (custom (just a) (nothing)) a)
    (val map ((f (-> a b)) (maybe (maybe#maybe a))) (maybe#maybe b)
      (doc "Map a value."))))
```

The API:

- `read_package(source)` returns the package name and its `PackageSpecification`, or raises
  `SpecError { line, column, message }`.
- `read_type_text(text, package_name~, module_path~)` reads one type expression.
- `print_package(name, spec)` and `print_type(t, package_name~)` write the canonical layout. Read, then print,
  then read gives the same result. The printer is lossless only for what the reader makes. It drops constructor
  argument names, `Named` annotation argument names, module and type annotations, annotation data that is not a
  literal, and `Compact` annotation text.

```mbt check
///|
test "read, print, then read gives the same result" {
  let source =
    #|(package "morphir/SDK"
    #|  (module basics
    #|    (type order (custom (LT) (EQ) (GT)))
    #|    (val add ((a number) (b number)) number)))
  let (name, spec) = @spec.read_package(source)
  let printed = @spec.print_package(name, spec)
  let (name2, spec2) = @spec.read_package(printed)
  assert_eq(name2, name)
  assert_eq(@spec.print_package(name2, spec2), printed)
}
```

### Forms

| Form | Meaning |
| --- | --- |
| `(package "pkg/path" module…)` | The whole package. The name is a canonical path. |
| `(module name item…)` | A module. `name` is a canonical module path written as a symbol, for example `json/encode`. |
| `(doc "text")` | Documentation. In a module it must be the first item. In a type it comes right after the name. In a val it must be the first trailing item. |
| `(type name body param…)` | A type. The trailing params are its type variables. |
| `(val name ((arg type)…) result item…)` | A value signature. The inputs keep their order. The trailing items are a `doc` and `annotation` forms. |
| `(annotation fqname arg…)` | An annotation of a val. The arguments are data: a string, an integer, a boolean or a list of data. `(annotation fq)` with no arguments is `Compact(fq, None)`. |

Type bodies:

| Body | Meaning |
| --- | --- |
| `(opaque)` | An opaque type |
| `(alias type)` | A type alias |
| `(custom (ctor type…)…)` | A custom type. The constructors keep their order. The notation names no constructor arguments, so they are `arg-1`, `arg-2`, …. |
| `(derived base from-fqname to-fqname)` | A derived type |

A type, a value, a constructor, a record field or a module that appears twice in its scope is refused.

### Type expressions

| Syntax | IR |
| --- | --- |
| A bare symbol, for example `a` or `comparable` | `Variable`. A name that starts with `number`, `comparable`, `appendable` or `compappend` also gets the constraint `typeclass` with that class. The longest prefix wins. |
| `module#name`, `pkg:module#name` | A `Reference` with no arguments |
| `(module#name t…)`, `(pkg:module#name t…)` | A `Reference` with arguments, for example `(list#list a)` |
| `(-> a b c)` | A curried `Function`, `a -> b -> c`. It needs at least two types. |
| `(tuple a b …)` | `Tuple`, with at least two types |
| `(record (field t)…)` | `Record` |
| `(record r (field t)…)` | `ExtensibleRecord` over the row variable `r` |
| `()` | `Unit` |

In the examples below, each block holds one type expression, read in package `my/pkg`, module `m`, and printed in the
canonical layout.

```scheme
(-> a b c)
;; => (-> a b c)
```

```scheme
(record r (name string#string) (age basics#int))
;; => (record r (name string#string) (age basics#int))
```

```scheme
(list#list a)
;; => (list#list a)
```

### The `module#name` rule

A reference is `module#name` or `pkg:module#name`. `module#name` resolves in the file's own package, for example
`basics#order` in `morphir/SDK`. `pkg:module#name` names any package. The printer writes `module#name` when the
package is the file's package, and `pkg:module#name` otherwise.

```scheme
(tuple other/pkg:list#list basics#int)
;; => (tuple other/pkg:list#list basics#int)
```

There is no `#name` form for the current module. The Scheme reader refuses a token that starts with `#`, other
than its own literals. Accepting `#name` would change the reader for every Scheme program.

### Names

Names follow the canonical v4 rules and are parsed with `Name::parse`, for example `less-than`, `map-2` and `LT`.
A name that is not canonical is refused, and the message suggests the canonical spelling. A reference must also
be canonical.

### Reserved `!` heads

A symbol that ends in `!` is reserved for macros, which a later pre-pass will expand into plain data. The reader
refuses it in any head position and as a type variable, with "`name!` is reserved for macros".

### Errors

Every refusal is a `SpecError` with the line and the column of the form that is wrong, and a short message. For
example, `read_type_text` refuses the type `(val-family! a)` at line 1, column 1, with the message
"`val-family!` is reserved for macros".

```scheme
(val-family! a)
;; error: 1:1: `val-family!` is reserved for macros
```

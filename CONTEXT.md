# Morphir IR

Morphir IR describes types, values and packages independently of a source language or execution platform.

## Language

**Format version**:
The release of the IR representation used by a document. It is independent of a tooling release.

**Current IR**:
The latest IR model supported by this implementation. Its meaning advances when support for a newer model is added.

**Versioned IR**:
An IR document whose format version remains explicit, including historical representations.

**Specification**:
The public types and value signatures of a module or package.

**Definition**:
The implementation of a type, value, module or package.

**Distribution**:
A package delivered as a library, a specification, or an application with entry points.

**Migration**:
An explicit conversion between IR format versions. A conversion that cannot retain the represented information is refused.

**Morphir Scheme**:
An embeddable language for transformation scripts and an execution target for Morphir IR.

**Pipeline**:
An ordered frontend, IR transformations and backend applied to a source by the engine.

**Project**:
A named source directory described by `morphir.json`, with optional script configuration.

**Workspace**:
An ordered collection of projects described by `morphir-workspace.json`.

**Host**:
The provider of source files. It controls I/O capabilities and persistence.

**Artifact**:
A named output returned by a backend, ready for the host to persist or consume.

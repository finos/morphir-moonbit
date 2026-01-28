# Morphir Moonbit Architecture

## Overview

This repository implements Morphir in Moonbit, organized as a monorepo with multiple interdependent packages. The architecture is designed to support both server-side (WASI) and browser-based (WASM-GC) WebAssembly targets.

## Repository Structure

```
morphir-moonbit/
├── .config/mise/              # Development tooling configuration
│   ├── config.toml           # Tool versions and environment
│   └── tasks/                # Build, test, and lint tasks
├── .github/
│   └── workflows/            # CI/CD pipelines
├── docs/                     # Documentation
├── pkgs/                     # Moonbit packages
│   ├── morphir-sdk/
│   ├── morphir-core/
│   └── morphir-moonbit-bindings/
└── moon.mod.json             # Root module configuration
```

## Package Organization

### morphir-core

**Purpose**: Core abstractions and fundamental types for the Morphir ecosystem.

**Responsibilities**:
- Define core types and interfaces
- Provide fundamental abstractions
- Establish type system foundations
- Define IR (Intermediate Representation) structures

**Dependencies**: None (foundational package)

### morphir-sdk

**Purpose**: Standard library providing functional programming primitives and data structures.

**Responsibilities**:
- Implement common data structures (List, Dict, Set, etc.)
- Provide functional utilities (map, filter, fold, etc.)
- Define standard types and interfaces
- Supply helper functions for common operations

**Dependencies**: `morphir-core`

### morphir-moonbit-bindings

**Purpose**: Foreign Function Interface (FFI) bindings for Moonbit WASM targets.

**Responsibilities**:
- Provide JavaScript interop for browser target
- Define WASI bindings for server-side target
- Expose platform-specific APIs
- Handle serialization/deserialization across boundaries

**Dependencies**: `morphir-core`, `morphir-sdk`

## Build Targets

### WASI Target (`wasm`)

- **Use Case**: Server-side applications, CLI tools, and WASI runtimes
- **Runtime**: WasmEdge, Wasmtime, or any WASI-compliant runtime
- **Features**: File system access, network I/O, system calls via WASI

### Browser Target (`wasm-gc`)

- **Use Case**: Browser-based applications
- **Runtime**: Modern browsers with WASM-GC support
- **Features**: JavaScript interop, DOM access, optimized GC integration

## Development Workflow

### Task Orchestration

All development tasks are managed through **mise** (formerly rtx), which provides:

1. **Consistent tooling**: Same tool versions across all developers
2. **Cross-platform support**: Tasks work on Linux, macOS, and Windows
3. **Simple interface**: Single command to run any task
4. **Environment management**: Automatic tool installation and PATH setup

### Task Categories

1. **Linting**: Code quality checks (YAML, Moonbit formatting)
2. **Formatting**: Automatic code formatting
3. **Building**: Compilation for different targets
4. **Testing**: Unit and integration tests
5. **Cleaning**: Remove build artifacts

## CI/CD Pipeline

### Parallel Execution Strategy

The CI pipeline is optimized for fast feedback:

```
┌─────────┐  ┌──────────────┐
│  Lint   │  │ Format Check │
└────┬────┘  └──────┬───────┘
     │              │
     └──────┬───────┘
            │
     ┌──────▼───────┐
     │   Test       │
     └──────┬───────┘
            │
     ┌──────▼───────┐
     │   Build      │
     │  (Matrix)    │
     │ - WASI       │
     │ - Browser    │
     └──────────────┘
```

### Job Descriptions

1. **Lint Job**: Validates YAML files and checks for common issues
2. **Format Check Job**: Ensures code follows formatting standards
3. **Test Job**: Runs all package tests
4. **Build Job**: Builds all packages for both targets (matrix strategy)

## Package Dependencies

```
┌──────────────────────┐
│   morphir-core       │  (No dependencies)
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│   morphir-sdk        │  (Depends on: core)
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ morphir-moonbit-     │  (Depends on: core, sdk)
│     bindings         │
└──────────────────────┘
```

## Tool Stack

### Development Tools (Managed by mise)

- **Moonbit**: Primary programming language
- **Bun**: Fast JavaScript runtime for scripting
- **yamllint**: YAML validation
- **uv**: Python package management

### CI/CD

- **GitHub Actions**: Continuous integration
- **mise-action**: Tool installation in CI

## Design Principles

1. **Minimal Dependencies**: Each package has only necessary dependencies
2. **Target Flexibility**: All packages support multiple WASM targets
3. **Task Consistency**: Same commands work locally and in CI
4. **Cross-Platform**: Works on Linux, macOS, and Windows
5. **Fast Feedback**: Parallel CI jobs for quick iteration

## Future Considerations

### Planned Additions

1. **morphir-elm-interop**: Interoperability with Elm implementations
2. **morphir-tooling**: Development tools and utilities
3. **morphir-examples**: Example applications and tutorials

### Scalability

The monorepo structure allows for:
- Easy addition of new packages
- Shared tooling and configuration
- Consistent versioning across packages
- Simplified dependency management

## References

- [Moonbit Documentation](https://www.moonbitlang.com/docs/)
- [Mise Documentation](https://mise.jdx.dev/)
- [WebAssembly Specification](https://webassembly.org/)
- [WASI Specification](https://wasi.dev/)

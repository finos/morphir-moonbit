# Morphir Moonbit Monorepo

[![FINOS - Incubating](https://cdn.jsdelivr.net/gh/finos/contrib-toolbox@master/images/badge-incubating.svg)](https://community.finos.org/docs/governance/Software-Projects/stages/incubating)
[![CI](https://github.com/finos/morphir-moonbit/actions/workflows/ci.yml/badge.svg)](https://github.com/finos/morphir-moonbit/actions/workflows/ci.yml)

A monorepo for Morphir implementation in Moonbit, providing core libraries and bindings for WebAssembly targets.

## Overview

This repository contains the Moonbit implementation of Morphir, organized as a monorepo with multiple packages:

- **morphir-sdk**: Standard library for Morphir with functional programming primitives
- **morphir-core**: Core abstractions and types for the Morphir ecosystem
- **morphir-moonbit-bindings**: FFI bindings for Moonbit WASM targets

## Prerequisites

- [mise](https://mise.jdx.dev/) - Development environment manager
- All other tools (Moonbit, Bun, yamllint, uv) are managed by mise

## Installation

1. Install mise by following the [official installation guide](https://mise.jdx.dev/getting-started.html)

2. Clone the repository:
   ```bash
   git clone https://github.com/finos/morphir-moonbit.git
   cd morphir-moonbit
   ```

3. Install tools:
   ```bash
   mise install
   ```

## Development

### Available Tasks

All development tasks are managed through mise. You can list all available tasks with:

```bash
mise tasks
```

#### Linting

```bash
# Run all linting tasks
mise run lint

# Lint YAML files only
mise run lint:yaml

# Check Moonbit code formatting
mise run lint:moonbit
```

#### Formatting

```bash
# Format all Moonbit code
mise run format
```

#### Building

```bash
# Build all packages for all targets
mise run build

# Build for WASI target only
mise run build:wasi

# Build for browser (WASM-GC) target only
mise run build:browser
```

#### Testing

```bash
# Run all tests
mise run test
```

#### Validation

```bash
# Run all validation checks (YAML lint + package structure)
mise run validate

# Verify package structure only
mise run validate:packages
```

## Project Structure

```
morphir-moonbit/
├── .config/
│   └── mise/
│       ├── config.toml          # Mise configuration
│       └── tasks/               # Task definitions
│           ├── lint/
│           ├── format/
│           ├── build/
│           └── test/
├── .github/
│   └── workflows/
│       └── ci.yml               # CI workflow
├── pkgs/                        # Moonbit packages
│   ├── morphir-sdk/
│   ├── morphir-core/
│   └── morphir-moonbit-bindings/
└── moon.mod.json                # Root module configuration
```

## Build Targets

The project supports two WebAssembly targets:

1. **WASI (wasm)**: For server-side and command-line applications
2. **Browser (wasm-gc)**: For browser-based applications with WASM-GC support

## AI Agent Skills

This repository includes AI agent skills following the [Agent Skills specification](https://agentskills.io/specification). These skills enhance AI coding assistants with project-specific knowledge.

**Available Skills**:
- **code-reviewer**: Comprehensive code review for PRs and changes

**Supported Agents**: Claude, GitHub Copilot, OpenAI Codex, Cursor, Windsurf, Google Antigravity

See [.github/AGENTS.md](.github/AGENTS.md) for more information.

## Contributing

For any questions, bugs or feature requests please open an [issue](https://github.com/finos/morphir-moonbit/issues).
For anything else please send an email to morphir@finos.org.

To submit a contribution:
1. Fork it (<https://github.com/finos/morphir-moonbit/fork>)
2. Create your feature branch (`git checkout -b feature/fooBar`)
3. Read our [contribution guidelines](.github/CONTRIBUTING.md) and [Community Code of Conduct](https://www.finos.org/code-of-conduct)
4. Commit your changes (`git commit -am 'Add some fooBar'`)
5. Push to the branch (`git push origin feature/fooBar`)
6. Create a new Pull Request

_NOTE:_ Commits and pull requests to FINOS repositories will only be accepted from those contributors with an active, executed Individual Contributor License Agreement (ICLA) with FINOS OR who are covered under an existing and active Corporate Contribution License Agreement (CCLA) executed with FINOS. Commits from individuals not covered under an ICLA or CCLA will be flagged and blocked by the FINOS Clabot tool (or [EasyCLA](https://community.finos.org/docs/governance/Software-Projects/easycla)). Please note that some CCLAs require individuals/employees to be explicitly named on the CCLA.

*Need an ICLA? Unsure if you are covered under an existing CCLA? Email [help@finos.org](mailto:help@finos.org)*

## License

Copyright 2026 FINOS

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)

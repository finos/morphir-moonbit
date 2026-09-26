# Contributing to Morphir Moonbit

Thank you for your interest in contributing to Morphir Moonbit! This document provides guidelines and instructions for setting up your development environment and contributing to this monorepo.

## Development Environment Setup

### Prerequisites

1. **Install mise**: Follow the [official installation guide](https://mise.jdx.dev/getting-started.html)

2. **Install development tools**: Run `mise install` in the repository root to install all required tools:
   - Moonbit toolchain (latest)
   - Bun 1.3.7
   - yamllint
   - uv (Python package manager)

### First-Time Setup

```bash
# Clone the repository
git clone https://github.com/finos/morphir-moonbit.git
cd morphir-moonbit

# Install all development tools
mise install
```

**Note**: Git hooks are automatically installed when you enter the directory (via mise hooks). The pre-push hook runs lint, format check, and validation before allowing any push.

### Git Hooks (Automatic Setup)

### Git Hooks (Automatic Setup)

Git hooks are **automatically installed** when you enter the directory (mise hook). You can also manually run:

```bash
mise run setup:hooks
```

This installs a pre-push hook that automatically runs lint, format check, and validation before allowing any push. This ensures you catch issues locally before they fail in CI. The setup is idempotent and runs automatically, so you don't need to worry about it.

## Pre-Push Requirements

**⚠️ CRITICAL**: All changes must pass lint, format, and validation checks before pushing.

### Required Checks Before Push

1. **Linting** - YAML and Moonbit code style
2. **Format Check** - Moonbit code formatting
3. **Validation** - Package structure and configuration

### Running Checks

```bash
# Run all checks at once
mise run check

# Or run individual checks
mise run lint           # Linting
mise run lint:moonbit   # Format check
mise run validate       # Validation
```

The pre-push hook automatically runs these checks, but you can (and should) run them manually during development to catch issues early.

### Bypassing Checks (Not Recommended)

While you can bypass the pre-push hook with `git push --no-verify`, this is **strongly discouraged** as it will cause CI failures and block your PR from being merged.

## Monorepo Structure

This repository uses a monorepo structure with multiple Moonbit packages:

```
morphir-moonbit/
├── .config/mise/          # Mise configuration and tasks
├── pkgs/                  # Moonbit packages (workspace members)
│   ├── morphir-sdk/
│   ├── morphir-core/
│   └── morphir-moonbit-bindings/
├── moon.mod               # Root module configuration
└── moon.work              # Workspace manifest (member modules)
```

## Development Workflow

### Working with Code

1. **Make your changes** in the relevant package under `pkgs/`

2. **Format your code**:
   ```bash
   mise run format
   ```

3. **Check formatting**:
   ```bash
   mise run lint:moonbit
   ```

4. **Run tests**:
   ```bash
   mise run test
   ```

### Building

Build for specific targets:

```bash
# Build for WASI (server-side, CLI)
mise run build:wasi

# Build for browser (WASM-GC)
mise run build:browser

# Build for all targets
mise run build
```

### Running Tasks

All development tasks are managed through mise:

```bash
# List all available tasks
mise tasks

# Run a specific task
mise run <task-name>

# Examples:
mise run lint          # Run all linting
mise run lint:yaml     # Lint YAML files only
mise run format        # Format all code
mise run test          # Run all tests
```

## Code Style

- **Moonbit**: Follow standard Moonbit formatting (enforced by `moon fmt`)
- **YAML**: Follow yamllint rules defined in `.yamllint.yml`
- All code must pass linting before being merged

## Testing

- Every package should have corresponding test files
- Test files should be named `*_test.mbt`
- All tests must pass in CI before merging

## Continuous Integration

Our CI workflow runs on every push and pull request:

1. **Lint Job**: Checks YAML and Moonbit code formatting
2. **Format Check Job**: Ensures code is properly formatted
3. **Build Job**: Builds for both WASI and browser targets (runs in parallel with lint)
4. **Test Job**: Runs all package tests (runs in parallel with lint)

Lint and format checks run in parallel with the test job to speed up CI.

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes following the guidelines above
4. Run `mise run lint` and `mise run test` locally
5. Commit your changes with descriptive commit messages
6. Push to your fork
7. Open a Pull Request

### Pull Request Requirements

- All CI checks must pass
- Code must be formatted (run `mise run format`)
- Tests must be included for new functionality
- Documentation should be updated if applicable

## Adding New Packages

To add a new package to the monorepo:

1. Create a new directory under `pkgs/`
2. Add a `moon.mod` file with module metadata
3. Add a `moon.pkg` file with package configuration
4. Register the module in the root `moon.work` workspace manifest
5. Add source files (`*.mbt`) and test files (`*_test.mbt`)

Example `moon.mod`:

```moonbit
name = "finos/my-new-package"

version = "0.1.0"

import {
  "finos/morphir-core@0.1.0",
}

readme = "README.md"

repository = "https://github.com/finos/morphir-moonbit"

license = "Apache-2.0"

keywords = [ "morphir", "example" ]

description = "Description of the package"
```

Example `moon.pkg` (a library package is the default, so no `pkgtype` is needed):

```moonbit
import {
  "finos/morphir-core",
}
```

Then add the module to the root `moon.work` so it is resolved from source:

```moonbit
members = [
  "./pkgs/morphir-core",
  "./pkgs/my-new-package",
]
```

## Troubleshooting

### Tool Installation Issues

If `mise install` fails:

1. Check mise version: `mise --version`
2. Update mise: `mise self-update`
3. Clear cache: `mise cache clear`
4. Try installing tools individually: `mise install bun`, `mise install yamllint`, etc.

### Build Issues

If builds fail:

1. Ensure tools are installed: `mise list`
2. Check moonbit version: `moon version`
3. Clean build artifacts: `mise run clean` (or `rm -rf _build`)
4. Try building individual packages: `moon -C pkgs/<package-name> build`

### Test Failures

If tests fail:

1. Run tests for a single module: `moon -C pkgs/<package-name> test`, or the whole workspace with `moon test`
2. Check test output for specific error messages
3. Ensure all dependencies are properly installed

## Questions?

- Open an [issue](https://github.com/finos/morphir-moonbit/issues) for bugs or feature requests
- Email morphir@finos.org for general questions
- Check existing documentation in the repository

## Code of Conduct

Please note that this project is released with a [Contributor Code of Conduct](https://www.finos.org/code-of-conduct). By participating in this project you agree to abide by its terms.

## License

By contributing to Morphir Moonbit, you agree that your contributions will be licensed under the Apache License, Version 2.0.

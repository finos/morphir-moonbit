# Mise Tasks Reference

This document provides a reference for all available mise tasks in the Morphir Moonbit monorepo.

## Task Categories

### Linting Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run lint` | Run all linting tasks | All |
| `mise run lint:yaml` | Lint YAML files | All |
| `mise run lint:moonbit` | Check Moonbit code formatting | All |

### Formatting Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run format` | Format all Moonbit code | All |

### Build Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run build` | Build all packages for all targets | All |
| `mise run build:wasi` | Build all packages for WASI target | All |
| `mise run build:browser` | Build all packages for browser (WASM-GC) target | All |
| `mise run build:js` | Build all packages for JavaScript | All |
| `mise run build:workbench` | Build the shared Rabbita browser frontend and runtime worker | All |
| `mise run build:native` | Build native release executables | All |

### Test Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run test` | Run tests for all packages | All |
| `mise run test:workbench` | Test the local pipeline, connected v1 protocol, loopback proxy and browser workflows | All |
| `mise run test:workbench-live-host -- --host-bin /absolute/path/to/morphir` | Test authenticated connected v1 workflows against an installed Rust UI host | All |
| `mise run test:conformance` | Compare versioned independent Ion expectations, live Scheme and explicitly pinned optional Rust; retain separate coverage receipts | All |
| `mise run test:cli` | Run CLI target and npm package smoke tests | All |
| `mise run test:supervision` | Verify process-tree cleanup, cancellation, deadlines and bounded diagnostics on Linux, macOS and Windows | All |
| `mise run test:embedding` | Install embedding dependencies and Chromium, then test Node, installed npm and browser hosts | All |

### Utility Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run check` | Run all checks (lint + test + build) | All |
| `mise run clean` | Clean build artifacts | All |
| `mise run validate` | Run all validation checks | All |
| `mise run validate:packages` | Verify package structure is valid | All |
| `mise run list-tasks` | List all available mise tasks | All |

### Setup Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run setup:workbench` | Install workbench npm dependencies and Chromium; `--ci` adds Linux system dependencies | All |
| `mise run setup:hooks` | Install git hooks for pre-push validation (idempotent, auto-runs on directory entry) | All |

### Beads Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run beads:plan -- <command>` | Store superpowers specs, plans and ledgers in beads and render them back, with `bd-plan` fetched from finos/morphir at a pinned commit (see [AGENTS.md](../AGENTS.md)) | All |

## Task Structure

Tasks are organized in the `.config/mise/tasks/` directory:

```
.config/mise/tasks/
├── lint/
│   ├── _default           # Main lint task (bash)
│   ├── _default.ps1       # Main lint task (PowerShell)
│   ├── yaml               # YAML linting (bash)
│   ├── yaml.ps1           # YAML linting (PowerShell)
│   ├── moonbit            # Moonbit format check (bash)
│   └── moonbit.ps1        # Moonbit format check (PowerShell)
├── format/
│   ├── _default           # Format task (bash)
│   └── _default.ps1       # Format task (PowerShell)
├── build/
│   ├── _default           # Build all (bash)
│   ├── _default.ps1       # Build all (PowerShell)
│   ├── wasi               # WASI build (bash)
│   ├── wasi.ps1           # WASI build (PowerShell)
│   ├── browser            # Browser build (bash)
│   ├── browser.ps1        # Browser build (PowerShell)
│   ├── js                # JavaScript build (bash)
│   ├── js.ps1            # JavaScript build (PowerShell)
│   ├── native            # Native release build (bash)
│   └── native.ps1        # Native release build (PowerShell)
├── test/
│   ├── _default           # Test task (bash)
│   ├── _default.ps1       # Test task (PowerShell)
│   ├── cli                # CLI smoke tests (bash)
│   └── cli.ps1            # CLI smoke tests (PowerShell)
├── validate/
│   ├── _default           # Run all validations (bash)
│   ├── _default.ps1       # Run all validations (PowerShell)
│   ├── packages           # Verify package structure (bash)
│   └── packages.ps1       # Verify package structure (PowerShell)
├── check                  # Run all checks (bash)
├── check.ps1              # Run all checks (PowerShell)
├── clean                  # Clean artifacts (bash)
├── clean.ps1              # Clean artifacts (PowerShell)
├── setup/
│   ├── hooks              # Setup git hooks (bash)
│   └── hooks.ps1          # Setup git hooks (PowerShell)
├── beads/
│   ├── plan               # Run bd-plan from finos/morphir (bash)
│   └── plan.ps1           # Run bd-plan from finos/morphir (PowerShell)
├── list-tasks             # List all tasks (bash)
└── list-tasks.ps1         # List all tasks (PowerShell)
```

## Common Workflows

### First-Time Setup

```bash
# After cloning the repository
cd morphir-moonbit
mise install
```

**Note**: The `setup:hooks` task runs automatically when you enter the directory (via mise hooks), so git hooks are set up automatically. This is idempotent and can be run multiple times safely.

### Pre-Push Validation (Automatic)

The pre-push hook automatically runs before every `git push`:

1. **Linting** (`mise run lint`)
2. **Format Check** (`mise run lint:moonbit`)
3. **Validation** (`mise run validate`)

If any check fails, the push is blocked with a clear error message.

**Bypass (not recommended)**: `git push --no-verify`

### Before Committing

```bash
# Run all checks
mise run check
```

### Quick Development Cycle

```bash
# Make changes...

# Format code
mise run format

# Check formatting and lint
mise run lint

# Run tests
mise run test
```

### Build for Specific Target

```bash
# Build only for WASI
mise run build:wasi

# Build only for browser
mise run build:browser
```

### Clean and Rebuild

```bash
# Clean all build artifacts
mise run clean

# Rebuild everything
mise run build
```

## CI/CD Integration

The lint, format-check, and configuration-validation workflows delegate to mise
tasks. The build and test jobs install the MoonBit toolchain directly through
the official installer and run `moon build` / `moon test`, because the mise
`http:moonbit` tool provides the compiler only and does not bundle the
`moonbitlang/core` standard library needed to compile.

### Main CI Workflow (`.github/workflows/ci.yml`)

- **Lint Job**: Uses `mise run lint`
- **Format Check Job**: Uses `mise run lint:moonbit`
- **Build Job**: Builds release artifacts for `wasm`, `wasm-gc`, `js`, and `native`, then runs CLI smoke tests for each target. The JavaScript job also packs, installs, and runs the npm package.
- **Test Job**: Installs MoonBit and runs `moon test`

### Validation Workflow (`.github/workflows/validate-config.yml`)

- **List Tasks**: Uses `mise run list-tasks`
- **Validate**: Uses `mise run validate`

## Adding New Tasks

To add a new task:

1. Create a bash script in `.config/mise/tasks/[category]/[name]`
2. Create a PowerShell script in `.config/mise/tasks/[category]/[name].ps1`
3. Make the bash script executable: `chmod +x .config/mise/tasks/[category]/[name]`
4. Add a description comment: `# mise description="Your description"`
5. Update this documentation

For task categories (like `lint` or `build`), the main task should be named `_default`.

## Tips

- Use `mise tasks` to list all available tasks
- Use `mise run <task> --help` for task-specific help (if implemented)
- Tasks can call other tasks using `mise run <task-name>`
- Environment variables from `.config/mise/config.toml` are available in all tasks

### IR fixtures

`mise run ir:fixtures` regenerates portable MoonBit tests from the vendored IR JSON corpus and formats the workspace. Pass `-- --morphir /path/to/morphir --morphir-elm /path/to/morphir-elm` to refresh from the pinned commits in local clones. See [the IR module](../pkgs/morphir-ir/README.md) for coverage and migration limits.

`mise run test` runs library tests on `wasm`, `wasm-gc`, `js` and `native`, followed by the CLI smoke tests.

### Workbench

`mise run setup:workbench`, `mise run build:workbench`, and `mise run test:workbench` prepare, build and verify the shared browser frontend. The JavaScript build job runs the browser workflow in Chromium. The optional Proton host has its own workspace to keep CEF out of default builds; see [desktop setup](../apps/morphir-workbench-desktop/README.md).

`mise run test:workbench-live-host -- --host-bin /absolute/path/to/morphir` verifies single-use launch authentication, native Gleam compilation/generation and workspace-model opening through the loopback proxy against a real Rust host. Supply a host with native Gleam available; see [Workbench verification](../apps/morphir-workbench/README.md#verification) for setup and version evidence. This optional check is separate from the default test suite.

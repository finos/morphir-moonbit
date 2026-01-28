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

### Test Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run test` | Run tests for all packages | All |

### Utility Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run check` | Run all checks (lint + test + build) | All |
| `mise run clean` | Clean build artifacts | All |
| `mise run validate` | Run all validation checks | All |
| `mise run validate:packages` | Verify package structure is valid | All |
| `mise run list-tasks` | List all available mise tasks | All |

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
│   └── browser.ps1        # Browser build (PowerShell)
├── test/
│   ├── _default           # Test task (bash)
│   └── _default.ps1       # Test task (PowerShell)
├── validate/
│   ├── _default           # Run all validations (bash)
│   ├── _default.ps1       # Run all validations (PowerShell)
│   ├── packages           # Verify package structure (bash)
│   └── packages.ps1       # Verify package structure (PowerShell)
├── check                  # Run all checks (bash)
├── check.ps1              # Run all checks (PowerShell)
├── clean                  # Clean artifacts (bash)
├── clean.ps1              # Clean artifacts (PowerShell)
├── list-tasks             # List all tasks (bash)
└── list-tasks.ps1         # List all tasks (PowerShell)
```

## Common Workflows

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

All GitHub Actions workflows delegate to mise tasks with **no inline scripts**. This ensures:
- Local development and CI use identical commands
- Easy troubleshooting (run the same mise command locally)
- Cross-platform consistency
- Single source of truth for all operations

### Main CI Workflow (`.github/workflows/ci.yml`)

- **Lint Job**: Uses `mise run lint`
- **Format Check Job**: Uses `mise run lint:moonbit`
- **Build Job**: Uses `mise run build:wasi` and `mise run build:browser`
- **Test Job**: Uses `mise run test`

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

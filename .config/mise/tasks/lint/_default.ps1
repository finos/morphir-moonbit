# mise description="Run all linting tasks"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Running all linting tasks..." -ForegroundColor Cyan

# Run YAML linting
mise run lint:yaml

# Run Moonbit formatting check
mise run lint:moonbit

Write-Host "✅ All linting tasks complete" -ForegroundColor Green

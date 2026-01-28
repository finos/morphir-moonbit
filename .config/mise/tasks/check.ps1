# mise description="Run all checks (lint, format check, build, test)"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Running all checks..." -ForegroundColor Cyan

# Run linting
Write-Host ""
Write-Host "=== Running lint checks ===" -ForegroundColor Yellow
mise run lint

# Run tests
Write-Host ""
Write-Host "=== Running tests ===" -ForegroundColor Yellow
mise run test

# Run builds
Write-Host ""
Write-Host "=== Building all targets ===" -ForegroundColor Yellow
mise run build

Write-Host ""
Write-Host "✅ All checks passed!" -ForegroundColor Green

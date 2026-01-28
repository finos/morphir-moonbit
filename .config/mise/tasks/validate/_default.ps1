# mise description="Run all validation checks"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Running all validation checks..." -ForegroundColor Cyan

# Validate YAML files
Write-Host ""
Write-Host "=== Validating YAML files ===" -ForegroundColor Yellow
mise run lint:yaml

# Verify package structure
Write-Host ""
Write-Host "=== Verifying package structure ===" -ForegroundColor Yellow
mise run validate:packages

Write-Host ""
Write-Host "✅ All validations passed" -ForegroundColor Green

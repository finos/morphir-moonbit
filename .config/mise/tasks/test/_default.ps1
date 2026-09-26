# mise description="Run tests for all packages"
$ErrorActionPreference = "Stop"

Write-Host "🧪 Running tests..." -ForegroundColor Cyan

# Run tests for all workspace members
moon test

Write-Host "✅ All tests passed" -ForegroundColor Green

# mise description="Check Moonbit code formatting"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Checking Moonbit code formatting..." -ForegroundColor Cyan

# Check formatting across all workspace members
moon fmt --check
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Formatting issues found. Run 'moon fmt' to fix." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Moonbit code formatting check complete" -ForegroundColor Green

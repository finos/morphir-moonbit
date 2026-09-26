# mise description="Clean build artifacts"
$ErrorActionPreference = "Stop"

Write-Host "🧹 Cleaning build artifacts..." -ForegroundColor Cyan

# Clean build artifacts for the whole workspace
moon clean
if (Test-Path "_build") {
    Remove-Item -Recurse -Force "_build"
}

Write-Host "✅ Clean complete" -ForegroundColor Green

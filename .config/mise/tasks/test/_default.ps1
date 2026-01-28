# mise description="Run tests for all packages"
$ErrorActionPreference = "Stop"

Write-Host "🧪 Running tests..." -ForegroundColor Cyan

Set-Location pkgs

$packages = @("morphir-sdk", "morphir-core", "morphir-moonbit-bindings")

foreach ($pkg in $packages) {
    if (Test-Path $pkg) {
        Write-Host "Testing $pkg..." -ForegroundColor Yellow
        Set-Location $pkg
        moon test
        Set-Location ..
    }
}

Set-Location ..

Write-Host "✅ All tests passed" -ForegroundColor Green

# mise description="Clean build artifacts"
$ErrorActionPreference = "Stop"

Write-Host "🧹 Cleaning build artifacts..." -ForegroundColor Cyan

Set-Location pkgs

$packages = @("morphir-sdk", "morphir-core", "morphir-moonbit-bindings")

foreach ($pkg in $packages) {
    if (Test-Path $pkg) {
        Write-Host "Cleaning $pkg..." -ForegroundColor Yellow
        Set-Location $pkg
        moon clean
        if (Test-Path "target") {
            Remove-Item -Recurse -Force "target"
        }
        Set-Location ..
    }
}

Set-Location ..

Write-Host "✅ Clean complete" -ForegroundColor Green

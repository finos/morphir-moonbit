# mise description="Format Moonbit code"
$ErrorActionPreference = "Stop"

Write-Host "🎨 Formatting Moonbit code..." -ForegroundColor Cyan

Set-Location pkgs

$packages = @("morphir-sdk", "morphir-core", "morphir-moonbit-bindings")

foreach ($pkg in $packages) {
    if (Test-Path $pkg) {
        Write-Host "Formatting $pkg..." -ForegroundColor Yellow
        Set-Location $pkg
        moon fmt
        Set-Location ..
    }
}

Set-Location ..

Write-Host "✅ Moonbit code formatting complete" -ForegroundColor Green

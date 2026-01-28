# mise description="Check Moonbit code formatting"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Checking Moonbit code formatting..." -ForegroundColor Cyan

Set-Location pkgs

# Check each package
$packages = @("morphir-sdk", "morphir-core", "morphir-moonbit-bindings")

foreach ($pkg in $packages) {
    if (Test-Path $pkg) {
        Write-Host "Checking $pkg..." -ForegroundColor Yellow
        Set-Location $pkg
        moon fmt --check
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Formatting issues found in $pkg. Run 'moon fmt' to fix." -ForegroundColor Red
            exit 1
        }
        Set-Location ..
    }
}

Set-Location ..

Write-Host "✅ Moonbit code formatting check complete" -ForegroundColor Green

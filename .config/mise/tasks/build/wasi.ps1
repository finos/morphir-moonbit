# mise description="Build all packages for WASI target"
$ErrorActionPreference = "Stop"

Write-Host "🔨 Building for WASI target..." -ForegroundColor Cyan

Set-Location pkgs

$packages = @("morphir-sdk", "morphir-core", "morphir-moonbit-bindings")

foreach ($pkg in $packages) {
    if (Test-Path $pkg) {
        Write-Host "Building $pkg for WASI..." -ForegroundColor Yellow
        Set-Location $pkg
        moon build --target wasm
        Set-Location ..
    }
}

Set-Location ..

Write-Host "✅ WASI build complete" -ForegroundColor Green

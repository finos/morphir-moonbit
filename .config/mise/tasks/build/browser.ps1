# mise description="Build all packages for browser (WASM-GC) target"
$ErrorActionPreference = "Stop"

Write-Host "🔨 Building for browser (WASM-GC) target..." -ForegroundColor Cyan

Set-Location pkgs

$packages = @("morphir-sdk", "morphir-core", "morphir-moonbit-bindings")

foreach ($pkg in $packages) {
    if (Test-Path $pkg) {
        Write-Host "Building $pkg for browser..." -ForegroundColor Yellow
        Set-Location $pkg
        moon build --target wasm-gc
        Set-Location ..
    }
}

Set-Location ..

Write-Host "✅ Browser build complete" -ForegroundColor Green

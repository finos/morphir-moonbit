# mise description="Build all packages for browser (WASM-GC) target"
$ErrorActionPreference = "Stop"

Write-Host "🔨 Building for browser (WASM-GC) target..." -ForegroundColor Cyan

# Build all workspace members for browser (WASM-GC)
moon build --target wasm-gc

Write-Host "✅ Browser build complete" -ForegroundColor Green

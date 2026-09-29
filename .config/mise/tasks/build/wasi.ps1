# mise description="Build all packages for WASI target"
$ErrorActionPreference = "Stop"

Write-Host "🔨 Building for WASI target..." -ForegroundColor Cyan

# Build all workspace members for WASI
moon build --target wasm

Write-Host "✅ WASI build complete" -ForegroundColor Green

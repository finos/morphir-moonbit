# mise description="Build all packages for all targets"
$ErrorActionPreference = "Stop"

Write-Host "🔨 Building all packages..." -ForegroundColor Cyan

# Build for WASI
mise run build:wasi

# Build for browser
mise run build:browser

Write-Host "✅ All builds complete" -ForegroundColor Green

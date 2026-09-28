# mise description="Build all packages for all targets"
$ErrorActionPreference = "Stop"

Write-Host "🔨 Building all packages..." -ForegroundColor Cyan

# Build for WASI
mise run build:wasi
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Build for browser
mise run build:browser
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

mise run build:js
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
mise run build:native
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "✅ All builds complete" -ForegroundColor Green

# mise description="Run tests for all packages"
$ErrorActionPreference = "Stop"

Write-Host "🧪 Running tests..." -ForegroundColor Cyan

# Run tests for all workspace members
foreach ($target in @("wasm", "wasm-gc", "js", "native")) {
    moon test --target $target
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

mise run test:cli
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "✅ All tests passed" -ForegroundColor Green

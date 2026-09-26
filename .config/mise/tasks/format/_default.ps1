# mise description="Format Moonbit code"
$ErrorActionPreference = "Stop"

Write-Host "🎨 Formatting Moonbit code..." -ForegroundColor Cyan

# Format all workspace members
moon fmt

Write-Host "✅ Moonbit code formatting complete" -ForegroundColor Green

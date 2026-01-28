# mise description="List all available mise tasks"
$ErrorActionPreference = "Stop"

Write-Host "📋 Available mise tasks:" -ForegroundColor Cyan
Write-Host ""
mise tasks

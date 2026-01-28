# mise description="Lint YAML files in the repository"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Linting YAML files..." -ForegroundColor Cyan

# Find and lint all YAML files
$yamlFiles = Get-ChildItem -Path . -Recurse -Include "*.yml", "*.yaml" -File |
    Where-Object { 
        $_.FullName -notmatch "node_modules" -and 
        $_.FullName -notmatch "\\.git" -and
        $_.FullName -notmatch "target" -and
        $_.FullName -notmatch "build"
    }

if ($yamlFiles.Count -gt 0) {
    $yamlFiles | ForEach-Object { yamllint $_.FullName }
}

Write-Host "✅ YAML linting complete" -ForegroundColor Green

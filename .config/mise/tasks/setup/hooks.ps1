# mise description="Setup git hooks for pre-push validation"
$ErrorActionPreference = "Stop"

Write-Host "🔧 Setting up git hooks..." -ForegroundColor Cyan

# Get the git hooks directory
$hooksDir = ".git/hooks"

if (-not (Test-Path $hooksDir)) {
    Write-Host "❌ Error: .git/hooks directory not found. Are you in a git repository?" -ForegroundColor Red
    exit 1
}

# Create the pre-push hook (bash script for Git Bash on Windows)
$prePushHook = Join-Path $hooksDir "pre-push"

$hookContent = @'
#!/usr/bin/env bash
# Pre-push hook: Runs lint, format check, and validation before allowing push
set -e

echo ""
echo "🔍 Running pre-push validation checks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if mise is available
if ! command -v mise &> /dev/null; then
    echo "❌ Error: mise is not installed or not in PATH"
    echo "   Please install mise: https://mise.jdx.dev/"
    exit 1
fi

# Run linting
echo "📝 Running lint checks..."
if ! mise run lint; then
    echo ""
    echo "❌ Linting failed! Please fix the issues and try again."
    echo "   Run: mise run lint"
    exit 1
fi

# Run format check
echo ""
echo "✨ Checking code formatting..."
if ! mise run lint:moonbit; then
    echo ""
    echo "❌ Format check failed! Please format your code and try again."
    echo "   Run: mise run format"
    exit 1
fi

# Run validation
echo ""
echo "🔍 Running validation checks..."
if ! mise run validate; then
    echo ""
    echo "❌ Validation failed! Please fix the issues and try again."
    echo "   Run: mise run validate"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All pre-push checks passed! Proceeding with push..."
echo ""
'@

Set-Content -Path $prePushHook -Value $hookContent -NoNewline

# On Windows with Git Bash, the hook needs to be executable
# PowerShell can't directly set Unix permissions, but Git respects the hook if it exists
Write-Host "✅ Git hooks installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Pre-push hook will now run the following checks before every push:" -ForegroundColor Yellow
Write-Host "  • Linting (mise run lint)" -ForegroundColor White
Write-Host "  • Format checking (mise run lint:moonbit)" -ForegroundColor White
Write-Host "  • Validation (mise run validate)" -ForegroundColor White
Write-Host ""
Write-Host "To bypass the hook (not recommended), use: git push --no-verify" -ForegroundColor Gray

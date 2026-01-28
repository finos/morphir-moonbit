# mise description="Setup git hooks for pre-push validation (idempotent)"
$ErrorActionPreference = "Stop"

# Skip in CI environments
if ($env:CI -eq "true" -or $env:GITHUB_ACTIONS -eq "true") {
    exit 0
}

# Get the git hooks directory
$hooksDir = ".git/hooks"

if (-not (Test-Path $hooksDir)) {
    # Not in a git repository, silently exit
    exit 0
}

# Create the pre-push hook content
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

$prePushHook = Join-Path $hooksDir "pre-push"

# Check if hook exists and is up-to-date
if (Test-Path $prePushHook) {
    $existingContent = Get-Content -Path $prePushHook -Raw
    if ($existingContent -eq $hookContent) {
        # Hook is already up-to-date, silently exit
        exit 0
    }
}

# Install or update the hook
Write-Host "🔧 Setting up git hooks..." -ForegroundColor Cyan
Set-Content -Path $prePushHook -Value $hookContent -NoNewline

Write-Host "✅ Git hooks installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Pre-push hook will now run the following checks before every push:" -ForegroundColor Yellow
Write-Host "  • Linting (mise run lint)" -ForegroundColor White
Write-Host "  • Format checking (mise run lint:moonbit)" -ForegroundColor White
Write-Host "  • Validation (mise run validate)" -ForegroundColor White
Write-Host ""
Write-Host "To bypass the hook (not recommended), use: git push --no-verify" -ForegroundColor Gray

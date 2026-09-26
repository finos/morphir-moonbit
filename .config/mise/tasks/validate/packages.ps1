# mise description="Verify package structure is valid"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Verifying package structure..." -ForegroundColor Cyan

$packages = @("morphir-sdk", "morphir-core", "morphir-moonbit-bindings")
# The workspace manifest must exist and register every member module.
$errors = 0
if (-not (Test-Path "moon.work")) {
    Write-Host "❌ ERROR: moon.work workspace manifest missing" -ForegroundColor Red
    $errors++
}

foreach ($pkg in $packages) {
    $modExists = Test-Path "pkgs/$pkg/moon.mod"
    $pkgExists = Test-Path "pkgs/$pkg/moon.pkg"

    if (-not $modExists) {
        Write-Host "❌ ERROR: moon.mod missing for $pkg" -ForegroundColor Red
        $errors++
    }

    if (-not $pkgExists) {
        Write-Host "❌ ERROR: moon.pkg missing for $pkg" -ForegroundColor Red
        $errors++
    }

    if ((Get-Content "moon.work" -Raw) -notmatch "pkgs/$pkg") {
        Write-Host "❌ ERROR: $pkg is not registered in moon.work" -ForegroundColor Red
        $errors++
    }

    if ($modExists -and $pkgExists) {
        Write-Host "✓ $pkg package configuration found" -ForegroundColor Green
    }
}

if ($errors -eq 0) {
    Write-Host "✅ All package configurations valid" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Found $errors configuration error(s)" -ForegroundColor Red
    exit 1
}

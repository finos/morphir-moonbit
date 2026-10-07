# mise description="Verify package structure is valid"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Verifying package structure..." -ForegroundColor Cyan

$packages = @("pkgs/morphir-sdk", "pkgs/morphir-ir", "pkgs/morphir-scheme", "pkgs/morphir-execution", "pkgs/morphir-engine", "pkgs/morphir-host", "pkgs/morphir-core", "pkgs/morphir-moonbit-bindings", "pkgs/morphir-moonbit", "pkgs/morphir-typing", "pkgs/morphir-sdk-spec", "apps/morphir", "apps/morphir-workbench")
# Modules whose root directory is not a package: they need moon.mod and a moon.work entry, but no moon.pkg.
$modules = @("pkgs/morphir-elm")
# The workspace manifest must exist and register every member module.
$errors = 0
$work = ""
if (-not (Test-Path "moon.work")) {
    Write-Host "❌ ERROR: moon.work workspace manifest missing" -ForegroundColor Red
    $errors++
} else {
    $work = Get-Content "moon.work" -Raw
}

foreach ($pkg in $packages) {
    $modExists = Test-Path "$pkg/moon.mod"
    $pkgExists = Test-Path "$pkg/moon.pkg"

    if (-not $modExists) {
        Write-Host "❌ ERROR: moon.mod missing for $pkg" -ForegroundColor Red
        $errors++
    }

    if (-not $pkgExists) {
        Write-Host "❌ ERROR: moon.pkg missing for $pkg" -ForegroundColor Red
        $errors++
    }

    # Match only active members: a commented-out entry starts with `#`, so it
    # will not begin (after whitespace) with a quoted path.
    if ($work -notmatch ('(?m)^\s*"(\./)?' + [regex]::Escape($pkg) + '"')) {
        Write-Host "❌ ERROR: $pkg is not an active member in moon.work" -ForegroundColor Red
        $errors++
    }

    if ($modExists -and $pkgExists) {
        Write-Host "✓ $pkg package configuration found" -ForegroundColor Green
    }
}

foreach ($module in $modules) {
    $modExists = Test-Path "$module/moon.mod"

    if (-not $modExists) {
        Write-Host "❌ ERROR: moon.mod missing for $module" -ForegroundColor Red
        $errors++
    }

    if ($work -notmatch ('(?m)^\s*"(\./)?' + [regex]::Escape($module) + '"')) {
        Write-Host "❌ ERROR: $module is not an active member in moon.work" -ForegroundColor Red
        $errors++
    }

    if ($modExists) {
        Write-Host "✓ $module module configuration found" -ForegroundColor Green
    }
}

if ($errors -eq 0) {
    Write-Host "✅ All package configurations valid" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Found $errors configuration error(s)" -ForegroundColor Red
    exit 1
}

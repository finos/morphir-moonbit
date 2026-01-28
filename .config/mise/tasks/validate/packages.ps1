# mise description="Verify package structure is valid"
$ErrorActionPreference = "Stop"

Write-Host "🔍 Verifying package structure..." -ForegroundColor Cyan

$packages = @("morphir-sdk", "morphir-core", "morphir-moonbit-bindings")
$errors = 0

foreach ($pkg in $packages) {
    $modJsonExists = Test-Path "pkgs/$pkg/moon.mod.json"
    $pkgJsonExists = Test-Path "pkgs/$pkg/moon.pkg.json"
    
    if (-not $modJsonExists) {
        Write-Host "❌ ERROR: moon.mod.json missing for $pkg" -ForegroundColor Red
        $errors++
    }
    
    if (-not $pkgJsonExists) {
        Write-Host "❌ ERROR: moon.pkg.json missing for $pkg" -ForegroundColor Red
        $errors++
    }
    
    if ($modJsonExists -and $pkgJsonExists) {
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

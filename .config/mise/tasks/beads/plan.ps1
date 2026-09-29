# mise description="Store superpowers specs, plans and ledgers in beads, and render them back (bd-plan from finos/morphir)"
# Pass the command after --, for example: mise run beads:plan -- render <plan-epic>
#
# bd-plan lives in finos/morphir (tools/bd-plan.ts) and imports only node:
# builtins, so this task fetches it at a pinned commit and runs it with Bun.
# Bump $BdPlanCommit to pick up a newer bd-plan.
$ErrorActionPreference = "Stop"

$BdPlanCommit = "d6b7cfa4cd614c85a087c009505c2856d5c73086"
$CacheRoot = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $env:LOCALAPPDATA "morphir" }
$CacheDir = Join-Path $CacheRoot "bd-plan/$BdPlanCommit"
$Script = Join-Path $CacheDir "bd-plan.ts"

if (-not (Test-Path $Script)) {
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $Tmp = "$Script.tmp"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/finos/morphir/$BdPlanCommit/tools/bd-plan.ts" -OutFile $Tmp
    Move-Item -Force $Tmp $Script
}

& bun run $Script @args
exit $LASTEXITCODE

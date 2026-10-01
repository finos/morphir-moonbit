# mise description="Install workbench dependencies and Chromium for UI verification"
$ErrorActionPreference = "Stop"
npm ci --prefix apps/morphir-workbench
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm exec --prefix apps/morphir-workbench -- playwright install chromium
exit $LASTEXITCODE

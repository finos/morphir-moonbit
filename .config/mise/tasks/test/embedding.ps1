# mise description="Test embedded MoonBit tooling in Node, npm and Chromium"
$ErrorActionPreference = "Stop"
$env:PLAYWRIGHT_SKIP_BROWSER_GC = "1"
npm --prefix pkgs/morphir-host/embedding ci --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm --prefix pkgs/morphir-host/embedding run build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm --prefix pkgs/morphir-host/embedding test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm exec --prefix pkgs/morphir-host/embedding -- playwright install chromium
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm --prefix pkgs/morphir-host/embedding run test:browser
exit $LASTEXITCODE

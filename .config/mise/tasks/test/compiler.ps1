# mise description="Compile generated libraries and validate private build leases"
$ErrorActionPreference = "Stop"
if (-not $env:MOON_HOME) { $env:MOON_HOME = Join-Path $HOME ".moon" }

node apps/morphir/build-provider/test-capability-pins.mjs
if ($LASTEXITCODE -ne 0) { throw "Compiler pin regression failed" }
node pkgs/morphir-moonbit/scripts/test-compiler.mjs pkgs/morphir-sdk
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
node apps/morphir/scripts/test-library-provider.js
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
node apps/morphir/scripts/test-execution.js
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
node apps/morphir/scripts/test-rich-execution.js
exit $LASTEXITCODE

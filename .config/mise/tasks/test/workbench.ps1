# mise description="Test the Morphir workbench runtime, protocol and browser workflows"
$ErrorActionPreference = "Stop"
moon test --target js -p finos/morphir-workbench finos/morphir-workbench/arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
node apps/morphir-workbench/scripts/build.js
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm --prefix apps/morphir-workbench test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm --prefix apps/morphir-workbench run test:browser
exit $LASTEXITCODE

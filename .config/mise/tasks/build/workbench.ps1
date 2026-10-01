# mise description="Build the shared MoonBit/Rabbita browser workbench"
$ErrorActionPreference = "Stop"
node apps/morphir-workbench/scripts/build.js
exit $LASTEXITCODE

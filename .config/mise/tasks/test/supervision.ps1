# mise description="Verify owned process-tree termination and bounded cleanup"
$ErrorActionPreference = 'Stop'
node apps/morphir/build-provider/test-supervision.mjs
exit $LASTEXITCODE

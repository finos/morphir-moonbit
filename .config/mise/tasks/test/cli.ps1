# mise description="Smoke-test the CLI on all targets and from its npm package"
$ErrorActionPreference = "Stop"

npm --prefix apps/morphir test
exit $LASTEXITCODE

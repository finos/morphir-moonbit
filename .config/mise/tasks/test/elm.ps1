# mise description="Check generated Elm projects with elm make"
$ErrorActionPreference = "Stop"

npm ci --prefix pkgs/morphir-elm/scripts
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
node pkgs/morphir-elm/scripts/test-elm-make.mjs
exit $LASTEXITCODE

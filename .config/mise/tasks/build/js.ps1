# mise description="Build all packages for JavaScript"
$ErrorActionPreference = "Stop"

moon build --target js
exit $LASTEXITCODE

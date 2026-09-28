# mise description="Build all packages as native executables"
$ErrorActionPreference = "Stop"

moon build --target native --release
exit $LASTEXITCODE

# mise description="Regenerate pinned IR fixture tests; optionally refresh from local upstream clones"
$ErrorActionPreference = "Stop"
uv run --no-cache --no-project python scripts/refresh-ir-fixtures.py @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
moon fmt
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

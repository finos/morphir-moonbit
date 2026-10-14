#!/usr/bin/env bash
# Tests for code-changed.sh. Run: bash .github/scripts/code-changed.test.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
failures=0

expect() {
  local want=$1; shift
  local got
  got="$(printf '%s\n' "$@" | bash "$here/code-changed.sh")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: expected $want for: $*, got $got"
    failures=$((failures + 1))
  fi
}

expect false docs/ARCHITECTURE.md
expect false site/site.json site/pages/index.html site/blog/2026-10-13-post.md
expect false apps/morphir-site/views/pages.mbt apps/morphir-site/scripts/build.js
expect false .github/workflows/site.yml
expect false README.md pkgs/morphir-ir/README.md AGENTS.md .github/AGENTS.md
expect true pkgs/morphir-ir/README.mbt.md
expect true pkgs/morphir-ir/ir.mbt
expect true docs/ARCHITECTURE.md apps/morphir-workbench/browser/main.mbt
expect true .github/workflows/ci.yml
expect true .github/scripts/code-changed.sh
expect true moon.work
expect true apps/morphir-sitex/main.mbt
# No changed files: run everything rather than guess.
expect true

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "code-changed.sh: all cases pass"

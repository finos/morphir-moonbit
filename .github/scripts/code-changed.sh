#!/usr/bin/env bash
# Reads changed paths, one per line, on stdin. Prints `false` when every path is
# documentation or project-site work, and `true` otherwise. CI skips its long jobs on
# `false`; the Site workflow builds and tests the site. No paths prints `true`.
set -euo pipefail

docs_like() {
  case "$1" in
    *.mbt.md) return 1 ;; # MoonBit literate tests
    docs/* | site/* | apps/morphir-site/* | .github/workflows/site.yml | *.md) return 0 ;;
    *) return 1 ;;
  esac
}

seen=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  seen=1
  if ! docs_like "$path"; then
    echo true
    exit 0
  fi
done
if [ "$seen" -eq 1 ]; then echo false; else echo true; fi

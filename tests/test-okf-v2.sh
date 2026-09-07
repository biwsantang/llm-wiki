#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/scripts/llm-wiki-okf.py"
FIXTURE="$ROOT/tests/fixtures/golden-wiki"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

python3 -c 'import yaml' 2>/dev/null || {
  echo "PyYAML is required: python3 -m pip install -r requirements-okf.txt" >&2
  exit 2
}

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name" >&2
    exit 1
  fi
}

if python3 "$TOOL" validate "$FIXTURE" >"$TMPDIR/legacy.out" 2>&1; then
  echo "FAIL: legacy fixture must not already validate as OKF" >&2
  exit 1
fi
check "legacy diagnostic identifies custom indexes" grep -q '_index.md' "$TMPDIR/legacy.out"

python3 "$TOOL" migrate "$FIXTURE" "$TMPDIR/converted" --dry-run >"$TMPDIR/dry-run.out"
check "dry-run leaves destination absent" test ! -e "$TMPDIR/converted"
python3 "$TOOL" migrate "$FIXTURE" "$TMPDIR/converted"
check "converted bundle validates" python3 "$TOOL" validate "$TMPDIR/converted"
check "main helper delegates OKF validation" python3 "$ROOT/scripts/llm-wiki" okf validate "$TMPDIR/converted"
check "all custom indexes renamed" test -z "$(find "$TMPDIR/converted" -name '_index.md' -print -quit)"
check "root index declares OKF version" grep -q 'okf_version: ' "$TMPDIR/converted/index.md"
check "compiled article has OKF type" grep -q '^type: Concept$' "$TMPDIR/converted/wiki/concepts/sample-concept.md"
check "compiled article has structured source" grep -q '^- resource: /raw/articles/' "$TMPDIR/converted/wiki/concepts/sample-concept.md"
check "log uses newest-first OKF headings" grep -q '^## 2026-01-10$' "$TMPDIR/converted/log.md"

echo "Result: PASS"

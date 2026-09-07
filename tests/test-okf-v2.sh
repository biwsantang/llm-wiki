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

expect_fail() {
  local name="$1"
  shift
  if "$@"; then
    echo "FAIL: $name" >&2
    exit 1
  else
    echo "PASS: $name"
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

runtime_source="$TMPDIR/runtime-source"
cp -R "$FIXTURE" "$runtime_source"
printf '{"private": true}\n' >"$runtime_source/.research-session.json"
printf '{"event": "private"}\n' >"$runtime_source/.session-events.jsonl"
mkdir -p "$runtime_source/.git"
printf '[core]\nrepositoryformatversion = 0\n' >"$runtime_source/.git/config"
python3 "$TOOL" migrate "$runtime_source" "$TMPDIR/runtime-converted"
check "root operational JSON is excluded" test ! -e "$TMPDIR/runtime-converted/.research-session.json"
check "root operational JSONL is excluded" test ! -e "$TMPDIR/runtime-converted/.session-events.jsonl"
check "nested Git metadata is excluded" test ! -e "$TMPDIR/runtime-converted/.git"

inside_source="$TMPDIR/inside-source"
cp -R "$FIXTURE" "$inside_source"
expect_fail "target inside source is rejected" python3 "$TOOL" migrate "$inside_source" "$inside_source/converted"
check "inside-source target was never created" test ! -e "$inside_source/converted"

collision_source="$TMPDIR/collision-source"
mkdir -p "$collision_source"
printf '# Legacy index\n' >"$collision_source/_index.md"
printf '# Existing index\n' >"$collision_source/index.md"
expect_fail "index destination collisions are rejected" python3 "$TOOL" migrate "$collision_source" "$TMPDIR/collision-converted"
check "collision leaves no target" test ! -e "$TMPDIR/collision-converted"

index_metadata_source="$TMPDIR/index-metadata-source"
mkdir -p "$index_metadata_source"
printf '%s\n' '---' 'title: Legacy index metadata' '---' '' '# Legacy index' >"$index_metadata_source/_index.md"
expect_fail "index frontmatter requires manual review" python3 "$TOOL" migrate "$index_metadata_source" "$TMPDIR/index-metadata-converted"
check "index-frontmatter failure leaves no target" test ! -e "$TMPDIR/index-metadata-converted"

broken_source="$TMPDIR/broken-source"
mkdir -p "$broken_source"
printf '%s\n' '---' 'title: missing closing delimiter' >"$broken_source/broken.md"
expect_fail "dry-run parses malformed frontmatter" python3 "$TOOL" migrate "$broken_source" "$TMPDIR/broken-converted" --dry-run
check "failed preflight leaves no target" test ! -e "$TMPDIR/broken-converted"

preserve_source="$TMPDIR/preserve-source"
mkdir -p "$preserve_source"
printf '# Legacy index\n' >"$preserve_source/_index.md"
printf '%s\n' '---' 'title: Preserve me' 'sources: legacy-source' 'custom_field: important' '---' '' '# Preserve' >"$preserve_source/preserve.md"
python3 "$TOOL" migrate "$preserve_source" "$TMPDIR/preserve-converted"
check "malformed legacy sources are retained" grep -q 'legacy_sources:' "$TMPDIR/preserve-converted/preserve.md"
check "unknown legacy frontmatter is retained" grep -q 'legacy_frontmatter:' "$TMPDIR/preserve-converted/preserve.md"

v01_source="$TMPDIR/v01-source"
mkdir -p "$v01_source"
printf '# Legacy index\n' >"$v01_source/_index.md"
printf '%s\n' '---' 'title: Legacy provenance' "timestamp: '2026-01-03T04:05:06+00:00'" '---' '' '# Definition' 'Legacy content.' '' '# Citations' '- https://example.test/source' >"$v01_source/legacy.md"
python3 "$TOOL" migrate "$v01_source" "$TMPDIR/v01-converted"
check "legacy timestamp becomes generated timestamp" grep -q '2026-01-03T04:05:06Z' "$TMPDIR/v01-converted/legacy.md"
check "legacy citations become structured sources" grep -q 'resource: https://example.test/source' "$TMPDIR/v01-converted/legacy.md"

mixed_log_source="$TMPDIR/mixed-log-source"
mkdir -p "$mixed_log_source"
printf '# Legacy index\n' >"$mixed_log_source/_index.md"
printf '%s\n' '# Update Log' '- 2024-12-31: Dated bullet remains.' '## [2025-01-01] ingest | Added legacy source' '## 2025-01-02' '* Modern entry remains.' >"$mixed_log_source/log.md"
python3 "$TOOL" migrate "$mixed_log_source" "$TMPDIR/mixed-log-converted"
check "dated bullet log entries are preserved" grep -q 'Dated bullet remains' "$TMPDIR/mixed-log-converted/log.md"
check "legacy log entries are preserved" grep -q 'Added legacy source' "$TMPDIR/mixed-log-converted/log.md"
check "modern log entries are preserved" grep -q 'Modern entry remains' "$TMPDIR/mixed-log-converted/log.md"

symlink_source="$TMPDIR/symlink-source"
mkdir -p "$symlink_source"
printf '# Legacy index\n' >"$symlink_source/_index.md"
printf 'outside bundle\n' >"$TMPDIR/secret.txt"
ln -s "$TMPDIR/secret.txt" "$symlink_source/linked.txt"
expect_fail "symlinked files are rejected" python3 "$TOOL" migrate "$symlink_source" "$TMPDIR/symlink-converted"
check "symlink failure leaves no target" test ! -e "$TMPDIR/symlink-converted"

expect_fail "validation rejects a missing bundle directory" python3 "$TOOL" validate "$TMPDIR/no-such-bundle"

echo "Result: PASS"

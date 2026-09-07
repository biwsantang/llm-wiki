#!/bin/bash
# Validate plugin manifest and command/skill frontmatter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGIN_DIR="$PROJECT_ROOT/claude-plugin"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
PASS=0
FAIL=0
TOTAL=0
REFERENCE_NAMES="adapters archive audit checkpoints command-prelude compilation datasets feedback hub-resolution ideas indexing ingestion inventory librarian linting okf-v2 portfolio projects query-lite research-infrastructure sessions specialists wiki-structure"

log_pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf "  \033[32mPASS\033[0m: %s\n" "$1"; }
log_fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf "  \033[31mFAIL\033[0m: %s — %s\n" "$1" "$2"; }

echo "=== Plugin Validation ==="

# plugin.json
if [ -f "$PLUGIN_JSON" ]; then
  log_pass "plugin.json exists"
  if python3 -c "import json; json.load(open('$PLUGIN_JSON'))" 2>/dev/null; then
    log_pass "plugin.json is valid JSON"
  else
    log_fail "plugin.json is invalid JSON" "parse error"
  fi
else
  log_fail "plugin.json not found at $PLUGIN_JSON" "missing file"
fi

# Every command .md has frontmatter (starts with ---)
echo ""
echo "--- Command frontmatter ---"
for cmd in "$PLUGIN_DIR"/commands/*.md; do
  basename=$(basename "$cmd")
  if head -1 "$cmd" | grep -q "^---$"; then
    log_pass "frontmatter in commands/$basename"
  else
    log_fail "no frontmatter in commands/$basename" "missing ---"
  fi
done

# The lessons-learned command writes a raw note, so its embedded template must
# use the same frontmatter schema that lint accepts for raw/notes/*.md.
LL_COMMAND="$PLUGIN_DIR/commands/ll.md"
if grep -q '^type: notes$' "$LL_COMMAND" \
  && grep -q '^ingested: YYYY-MM-DD$' "$LL_COMMAND" \
  && grep -q '^lesson_kind: lessons-learned$' "$LL_COMMAND" \
  && ! grep -q '^type: lessons-learned$' "$LL_COMMAND" \
  && ! grep -q '^date: YYYY-MM-DD$' "$LL_COMMAND"; then
  log_pass "commands/ll.md raw-note template matches lint schema"
else
  log_fail "commands/ll.md raw-note template schema drift" "expected type: notes, ingested, and lesson_kind"
fi

# Topic guides must influence every runtime through the shared compilation
# protocol without becoming a second schema or hiding raw-source coverage.
COMPILE_COMMAND="$PLUGIN_DIR/commands/compile.md"
COMPILATION_REFERENCE="$PLUGIN_DIR/skills/wiki-manager/references/compilation.md"
WIKI_STRUCTURE_REFERENCE="$PLUGIN_DIR/skills/wiki-manager/references/wiki-structure.md"
if grep -q 'references/compilation.md.*Topic-guide preflight' "$COMPILE_COMMAND" \
  && grep -q '^### Step 0: Topic-guide preflight$' "$COMPILATION_REFERENCE" \
  && grep -q 'cannot mark' "$COMPILATION_REFERENCE" \
  && grep -q 'For `schema_state: strict`, stop' "$COMPILATION_REFERENCE" \
  && grep -q 'Every runtime.*compilation workflow reads' "$WIKI_STRUCTURE_REFERENCE" \
  && grep -q 'does not satisfy C6' "$WIKI_STRUCTURE_REFERENCE" \
  && grep -q 'Topic-guide preflight' "$PROJECT_ROOT/AGENTS.md"; then
  log_pass "topic-guide compilation is runtime-neutral and preserves coverage"
else
  log_fail "topic-guide compilation contract drift" "expected shared planning guidance, strict confirmation, and C6 coverage"
fi

# Portfolio must remain a derived, read-only cross-topic view rather than a new
# hub content layer or an inferred Idea/Project relationship store.
PORTFOLIO_COMMAND="$PLUGIN_DIR/commands/portfolio.md"
PORTFOLIO_REFERENCE="$PLUGIN_DIR/skills/wiki-manager/references/portfolio.md"
if grep -q 'read-only' "$PORTFOLIO_COMMAND" \
  && grep -q 'inventory/ideas/_index.md' "$PORTFOLIO_COMMAND" \
  && grep -q 'output/projects/\*/WHY.md' "$PORTFOLIO_COMMAND" \
  && grep -q 'Never infer lineage' "$PORTFOLIO_COMMAND" \
  && grep -q 'catch-all topic' "$PORTFOLIO_REFERENCE" \
  && grep -q 'duplicate records' "$PORTFOLIO_REFERENCE"; then
  log_pass "portfolio command preserves distributed source-of-truth invariants"
else
  log_fail "portfolio command invariant drift" "expected read-only index-first Ideas/Projects view"
fi

# Project Knowledge Checkpoints must remain comprehensive, cross-topic,
# review-first, and privacy-sealed. A generic summary or optional scan is not
# equivalent.
CHECKPOINT_COMMAND="$PLUGIN_DIR/commands/checkpoint.md"
CHECKPOINT_REFERENCE="$PLUGIN_DIR/skills/wiki-manager/references/checkpoints.md"
if grep -q 'dry-run by default' "$CHECKPOINT_COMMAND" \
  && grep -q 'semantic privacy minimization' "$CHECKPOINT_COMMAND" \
  && grep -q 'checkpoint seal' "$CHECKPOINT_COMMAND" \
  && grep -q 'There is no option to disable privacy scanning' "$CHECKPOINT_COMMAND" \
  && grep -q 'Mandatory comprehensive coverage' "$CHECKPOINT_COMMAND" \
  && grep -q 'privacy-report.json' "$CHECKPOINT_REFERENCE" \
  && grep -q 'Default to comprehensive' "$CHECKPOINT_REFERENCE" \
  && grep -q 'There is no `--no-scan` or global bypass' "$CHECKPOINT_REFERENCE" \
  && grep -q 'Project Knowledge Checkpoint' "$PLUGIN_DIR/commands/wiki.md" \
  && grep -q 'Project checkpoints need comprehensive coverage and a privacy seal' "$PLUGIN_DIR/skills/wiki-manager/SKILL.md" \
  && grep -q 'Project checkpoints are comprehensive and privacy-sealed' "$PROJECT_ROOT/AGENTS.md"; then
  log_pass "checkpoint workflow preserves comprehensive coverage, privacy, and approval gates"
else
  log_fail "checkpoint workflow invariant drift" "expected comprehensive coverage plus mandatory staged seal/verify and exact overrides"
fi

# SKILL.md exists
echo ""
echo "--- Skill files ---"
if [ -f "$PLUGIN_DIR/skills/wiki-manager/SKILL.md" ]; then
  log_pass "SKILL.md exists"
  if head -1 "$PLUGIN_DIR/skills/wiki-manager/SKILL.md" | grep -q "^---$"; then
    log_pass "SKILL.md has frontmatter"
  else
    log_fail "SKILL.md has no frontmatter" "missing ---"
  fi
else
  log_fail "SKILL.md not found" "missing file"
fi

# External action intents must use provider-neutral manifest routing before
# generic URL ingestion on every maintained instruction surface.
ADAPTER_REFERENCE="$PLUGIN_DIR/skills/wiki-manager/references/adapters.md"
if grep -q '## Adapter Routing' "$PLUGIN_DIR/skills/wiki-manager/SKILL.md" \
  && grep -q 'adapter route --intent' "$PLUGIN_DIR/skills/wiki-manager/SKILL.md" \
  && grep -q '## Intent routing' "$ADAPTER_REFERENCE" \
  && grep -q 'adapter-owned workflow' "$ADAPTER_REFERENCE" \
  && grep -q '"routes"' "$ADAPTER_REFERENCE" \
  && grep -q '## Explicit named adapter invocation' "$ADAPTER_REFERENCE" \
  && grep -q 'wiki skill-factory' "$PLUGIN_DIR/skills/wiki-manager/SKILL.md" \
  && grep -q 'Skill Factory Adapter' "$PLUGIN_DIR/commands/wiki.md" \
  && grep -q 'wiki skill-factory' "$PROJECT_ROOT/AGENTS.md" \
  && grep -q 'External Adapter Route' "$PLUGIN_DIR/commands/wiki.md" \
  && grep -q '## Declarative intent routing' "$PLUGIN_DIR/commands/adapter.md" \
  && grep -q 'Route external actions before ingestion' "$PROJECT_ROOT/AGENTS.md" \
  && ! grep -Eqi 'google docs|google-docs|docs\.google\.com|google picker|native messaging|find.and.replace' \
    "$PLUGIN_DIR/skills/wiki-manager/SKILL.md" "$ADAPTER_REFERENCE" \
    "$PLUGIN_DIR/commands/wiki.md" "$PLUGIN_DIR/commands/adapter.md" "$PROJECT_ROOT/AGENTS.md"; then
  log_pass "external action intent routes through provider-neutral adapter metadata"
else
  log_fail "private adapter routing drift" "expected manifest route discovery and no provider-specific workflow in public instruction surfaces"
fi

# Personal specialists are bounded instruction packages, not simulated
# credentials or a tool-authority mechanism.
SPECIALIST_COMMAND="$PLUGIN_DIR/commands/specialist.md"
SPECIALIST_REFERENCE="$PLUGIN_DIR/skills/wiki-manager/references/specialists.md"
if grep -q '## Local storage and sharing boundary' "$SPECIALIST_REFERENCE" \
  && grep -q 'Instruction-only package contract' "$SPECIALIST_REFERENCE" \
  && grep -q 'There is no global default' "$SPECIALIST_REFERENCE" \
  && grep -q 'never grants tools' "$SPECIALIST_REFERENCE" \
  && grep -q '## `suggest`' "$SPECIALIST_COMMAND" \
  && grep -q '## `apply`' "$SPECIALIST_COMMAND" \
  && grep -q 'Specialists are bounded methods, not credentials' "$PLUGIN_DIR/skills/wiki-manager/SKILL.md" \
  && grep -q 'Personal Specialist' "$PLUGIN_DIR/commands/wiki.md" \
  && grep -q 'optional `.sessions/` and `.skills/`' "$PROJECT_ROOT/AGENTS.md"; then
  log_pass "personal specialists preserve allowlists, instruction-only safety, and non-credential boundaries"
else
  log_fail "personal specialist invariant drift" "expected hub library, topic allowlists, bounded methods, and no tool grants"
fi

# Reference files exist
echo ""
echo "--- Reference files ---"
for ref in $REFERENCE_NAMES; do
  reffile="$PLUGIN_DIR/skills/wiki-manager/references/${ref}.md"
  if [ -f "$reffile" ]; then
    log_pass "references/$ref.md exists"
  else
    log_fail "references/$ref.md missing" "missing file"
  fi
done

# AGENTS.md exists at project root
echo ""
echo "--- Project files ---"
if [ -f "$PROJECT_ROOT/AGENTS.md" ]; then
  log_pass "AGENTS.md exists"
else
  log_fail "AGENTS.md missing" "missing file"
fi

CLAUDE_LOCAL_CLI="$PLUGIN_DIR/bin/llm-wiki"
if [ -x "$CLAUDE_LOCAL_CLI" ] \
  && cmp -s "$CLAUDE_LOCAL_CLI" "$PROJECT_ROOT/scripts/llm-wiki"; then
  log_pass "Claude plugin bundles the current deterministic llm-wiki CLI"
else
  log_fail "Claude bundled llm-wiki CLI missing or stale" "run a plugin sync script"
fi

# Codex mirror validation — the artifacts that Codex installs from this repo.
# Drift between Claude source and this mirror is covered by test-codex-sync.sh;
# what's checked here is whether the mirror itself is well-formed.
echo ""
echo "=== Codex Mirror Validation ==="
CODEX_PLUGIN="$PROJECT_ROOT/plugins/llm-wiki"
CODEX_SKILL="$CODEX_PLUGIN/skills/wiki"
CODEX_QUERY_SKILL="$CODEX_PLUGIN/skills/wiki-query"

# Codex copies references into the generated tree because the marketplace cache
# needs real files, not a symlink back into the repo checkout.
echo ""
echo "--- Codex references copy ---"
REFS_DIR="$CODEX_SKILL/references"
if [ -d "$REFS_DIR" ] && [ ! -L "$REFS_DIR" ]; then
  log_pass "Codex references directory exists"
  for ref in $REFERENCE_NAMES; do
    if [ -f "$REFS_DIR/${ref}.md" ]; then
      log_pass "Codex references/$ref.md exists"
    else
      log_fail "Codex references/$ref.md missing" "missing copied reference file"
    fi
  done
else
  log_fail "Codex references directory invalid" "expected copied files under plugins/llm-wiki/skills/wiki/references"
fi

# Codex plugin manifest
echo ""
echo "--- Codex plugin manifest ---"
CODEX_MANIFEST="$CODEX_PLUGIN/.codex-plugin/plugin.json"
if [ -f "$CODEX_MANIFEST" ]; then
  log_pass ".codex-plugin/plugin.json exists"
  if python3 -c "import json; m=json.load(open('$CODEX_MANIFEST')); assert m.get('name') and m.get('version'), 'missing name or version'" 2>/dev/null; then
    log_pass ".codex-plugin/plugin.json parses with name + version"
  else
    log_fail ".codex-plugin/plugin.json invalid" "parse error or missing required field"
  fi
else
  log_fail ".codex-plugin/plugin.json not found" "missing file"
fi


# Codex bundled hooks for opt-in automated session capture.
echo ""
echo "--- Codex bundled hooks ---"
CODEX_HOOKS="$CODEX_PLUGIN/hooks/hooks.json"
CODEX_SESSION_HELPER="$CODEX_PLUGIN/hooks/llm_wiki_session.py"
if [ -f "$CODEX_HOOKS" ]; then
  log_pass "Codex hooks/hooks.json exists"
  if python3 -c "import json; json.load(open('$CODEX_HOOKS'))" 2>/dev/null; then
    log_pass "Codex hooks/hooks.json is valid JSON"
  else
    log_fail "Codex hooks/hooks.json invalid" "parse error"
  fi
else
  log_fail "Codex hooks/hooks.json missing" "missing file"
fi
if [ -x "$CODEX_SESSION_HELPER" ]; then
  log_pass "Codex session hook helper exists and is executable"
else
  log_fail "Codex session hook helper missing" "expected executable hooks/llm_wiki_session.py"
fi

# Codex marketplace entry
MARKETPLACE="$PROJECT_ROOT/.agents/plugins/marketplace.json"
if [ -f "$MARKETPLACE" ]; then
  log_pass ".agents/plugins/marketplace.json exists"
  if python3 -c "import json; json.load(open('$MARKETPLACE'))" 2>/dev/null; then
    log_pass ".agents/plugins/marketplace.json is valid JSON"
  else
    log_fail ".agents/plugins/marketplace.json invalid JSON" "parse error"
  fi
else
  log_fail ".agents/plugins/marketplace.json not found" "missing file"
fi

# Codex SKILL.md
echo ""
echo "--- Codex skill files ---"
if [ -f "$CODEX_SKILL/SKILL.md" ]; then
  log_pass "Codex SKILL.md exists"
  if head -1 "$CODEX_SKILL/SKILL.md" | grep -q "^---$"; then
    log_pass "Codex SKILL.md has frontmatter"
  else
    log_fail "Codex SKILL.md has no frontmatter" "missing ---"
  fi
  if grep -q "^name: wiki$" "$CODEX_SKILL/SKILL.md"; then
    log_pass "Codex SKILL.md uses the wiki skill name"
  else
    log_fail "Codex SKILL.md uses the wrong skill name" "expected 'name: wiki'"
  fi
  if sed -n '2,/^---$/p' "$CODEX_SKILL/SKILL.md" | grep -q 'external resource'; then
    log_pass "Codex implicit skill metadata advertises external adapter routing"
  else
    log_fail "Codex adapter invocation metadata missing" "expected external resource in frontmatter"
  fi
  if sed -n '2,/^---$/p' "$CODEX_SKILL/SKILL.md" | grep -q 'skill-factory'; then
    log_pass "Codex implicit skill metadata advertises declarative skill factory"
  else
    log_fail "Codex skill factory metadata missing" "expected skill factory in frontmatter"
  fi
else
  log_fail "Codex SKILL.md not found" "missing file"
fi

# Codex agents/openai.yaml — minimal grep check (no PyYAML dep) for the two
# top-level keys the sync script writes.
OPENAI_YAML="$CODEX_SKILL/agents/openai.yaml"
if [ -f "$OPENAI_YAML" ]; then
  log_pass "agents/openai.yaml exists"
  if grep -q "^interface:" "$OPENAI_YAML" && grep -q "^policy:" "$OPENAI_YAML"; then
    log_pass "agents/openai.yaml has interface + policy keys"
  else
    log_fail "agents/openai.yaml missing required keys" "expected interface: and policy:"
  fi
else
  log_fail "agents/openai.yaml not found" "missing file"
fi

# The explicit query preset is deliberately separate from the full implicit
# skill so users can opt into a much smaller, read-only context surface.
if [ -f "$CODEX_QUERY_SKILL/SKILL.md" ]; then
  log_pass "Codex wiki-query/SKILL.md exists"
  if head -1 "$CODEX_QUERY_SKILL/SKILL.md" | grep -q "^---$" \
    && grep -q "^name: wiki-query$" "$CODEX_QUERY_SKILL/SKILL.md"; then
    log_pass "Codex wiki-query/SKILL.md has valid frontmatter"
  else
    log_fail "Codex wiki-query/SKILL.md frontmatter invalid" "expected name: wiki-query"
  fi
else
  log_fail "Codex wiki-query/SKILL.md not found" "missing query preset"
fi

CODEX_QUERY_YAML="$CODEX_QUERY_SKILL/agents/openai.yaml"
if [ -f "$CODEX_QUERY_YAML" ] \
  && grep -q "^interface:" "$CODEX_QUERY_YAML" \
  && grep -q "^policy:" "$CODEX_QUERY_YAML" \
  && grep -q "allow_implicit_invocation: false" "$CODEX_QUERY_YAML"; then
  log_pass "Codex wiki-query metadata is explicit-only"
else
  log_fail "Codex wiki-query metadata invalid" "expected interface and explicit-only policy"
fi

CODEX_LOCAL_CLI="$CODEX_PLUGIN/bin/llm-wiki"
if [ -x "$CODEX_LOCAL_CLI" ] \
  && cmp -s "$CODEX_LOCAL_CLI" "$PROJECT_ROOT/scripts/llm-wiki"; then
  log_pass "Codex plugin bundles the current deterministic llm-wiki CLI"
else
  log_fail "Codex bundled llm-wiki CLI missing or stale" "run scripts/sync-codex-plugin.sh"
fi

# OpenCode mirror validation — the artifacts that OpenCode loads via the
# "instructions" key in opencode.json. Drift between Claude source and this
# mirror is covered by test-opencode-sync.sh; what's checked here is whether
# the mirror itself is well-formed.
echo ""
echo "=== OpenCode Mirror Validation ==="
OPENCODE_PLUGIN="$PROJECT_ROOT/plugins/llm-wiki-opencode"
OPENCODE_SKILL="$OPENCODE_PLUGIN/skills/wiki-manager"
OPENCODE_QUERY_SKILL="$OPENCODE_PLUGIN/skills/wiki-query"

# References symlink
echo ""
echo "--- OpenCode references symlink ---"
OC_REFS_LINK="$OPENCODE_SKILL/references"
if [ -L "$OC_REFS_LINK" ]; then
  log_pass "OpenCode references is a symlink"
  if [ -e "$OC_REFS_LINK" ]; then
    log_pass "OpenCode references symlink resolves"
    for ref in $REFERENCE_NAMES; do
      if [ -f "$OC_REFS_LINK/${ref}.md" ]; then
        log_pass "OpenCode references/$ref.md reachable via symlink"
      else
        log_fail "OpenCode references/$ref.md not reachable via symlink" "broken target"
      fi
    done
  else
    log_fail "OpenCode references symlink target does not exist" "$(readlink "$OC_REFS_LINK")"
  fi
else
  log_fail "OpenCode references is not a symlink" "expected symlink to claude-plugin source"
fi

# OpenCode SKILL.md
echo ""
echo "--- OpenCode skill files ---"
if [ -f "$OPENCODE_SKILL/SKILL.md" ]; then
  log_pass "OpenCode SKILL.md exists"
  if head -1 "$OPENCODE_SKILL/SKILL.md" | grep -q "^---$"; then
    log_pass "OpenCode SKILL.md has frontmatter"
  else
    log_fail "OpenCode SKILL.md has no frontmatter" "missing ---"
  fi
  # Verify no Claude Code references leaked through
  if ! grep -q "Claude Code" "$OPENCODE_SKILL/SKILL.md"; then
    log_pass "OpenCode SKILL.md has no 'Claude Code' references"
  else
    log_fail "OpenCode SKILL.md contains 'Claude Code'" "sync script missed a replacement"
  fi
  if sed -n '2,/^---$/p' "$OPENCODE_SKILL/SKILL.md" | grep -q 'external resource'; then
    log_pass "OpenCode skill metadata advertises external adapter routing"
  else
    log_fail "OpenCode adapter invocation metadata missing" "expected external resource in frontmatter"
  fi
else
  log_fail "OpenCode SKILL.md not found" "missing file"
fi

if [ -f "$OPENCODE_QUERY_SKILL/SKILL.md" ]; then
  log_pass "OpenCode wiki-query/SKILL.md exists"
  if head -1 "$OPENCODE_QUERY_SKILL/SKILL.md" | grep -q "^---$" \
    && grep -q "^name: wiki-query$" "$OPENCODE_QUERY_SKILL/SKILL.md"; then
    log_pass "OpenCode wiki-query/SKILL.md has valid frontmatter"
  else
    log_fail "OpenCode wiki-query/SKILL.md frontmatter invalid" "expected name: wiki-query"
  fi
else
  log_fail "OpenCode wiki-query/SKILL.md not found" "missing best-effort query preset"
fi

# OpenCode README
if [ -f "$OPENCODE_PLUGIN/README.md" ]; then
  log_pass "OpenCode README.md exists"
else
  log_fail "OpenCode README.md not found" "missing file"
fi

OPENCODE_LOCAL_CLI="$OPENCODE_PLUGIN/bin/llm-wiki"
if [ -x "$OPENCODE_LOCAL_CLI" ] \
  && cmp -s "$OPENCODE_LOCAL_CLI" "$PROJECT_ROOT/scripts/llm-wiki"; then
  log_pass "OpenCode plugin bundles the current deterministic llm-wiki CLI"
else
  log_fail "OpenCode bundled llm-wiki CLI missing or stale" "run scripts/sync-opencode-plugin.sh"
fi

echo ""
echo "==========================================="
printf "Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m, %d total\n" "$PASS" "$FAIL" "$TOTAL"
echo "==========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

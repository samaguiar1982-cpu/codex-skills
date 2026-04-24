#!/bin/bash
# scheduled-task-validator v2.1.0
# Audits SF-chain scheduled tasks under /Users/samaguiar/Documents/Claude/Scheduled/
# Portable: macOS bash 3.2 + BSD userland. No associative arrays, no GNU-only flags.
# Reproducible: no args, no env deps. Run: bash validate.sh

set -u

VERSION="2.1.0"

# --- Self-integrity check (Q-W2, 2026-04-24) ---
# Pin a SHA256 of this script (excluding the EXPECTED_HASH line itself).
# If the on-disk script doesn\'t match, abort. This catches the v1.1.5
# "claimed-but-never-written" failure mode and any unauthorized edits.
EXPECTED_HASH="74f1588d7ae4b71af02c99a12eeb8b6a881c6d83e0d95c00cbb57e5b0fcaf561"  # SELF_HASH_SENTINEL
SELF_PATH="/Users/samaguiar/Documents/Projects/Skills/scheduled-task-validator/validate.sh"
if [ -f "$SELF_PATH" ]; then
  COMPUTED_HASH="$(grep -v 'SELF_HASH_SENTINEL' "$SELF_PATH" | shasum -a 256 | awk '{print $1}')"
  if [ "$EXPECTED_HASH" != "$COMPUTED_HASH" ] && [ "$EXPECTED_HASH" != "REPLACE_WITH_REAL_HASH" ]; then
    echo "FAIL: validate.sh integrity check failed." >&2
    echo "  expected: $EXPECTED_HASH" >&2
    echo "  computed: $COMPUTED_HASH" >&2
    echo "  Script was modified without updating EXPECTED_HASH. Refusing to run." >&2
    exit 2
  fi
fi
# --- end self-integrity check ---

SCHED_DIR="/Users/samaguiar/Documents/Claude/Scheduled"
GUARDS_README="$SCHED_DIR/_guards/README.md"
QA_REFLECTION="$SCHED_DIR/_post-run-qa-reflection.md"
NOTION_DSID="13d5d9db-4588-41bc-afa9-45ce9e23e56c"
REPORT_DIR="/Users/samaguiar/Documents/Codex/validator-runs"
TODAY="$(date +%Y-%m-%d)"
REPORT="$REPORT_DIR/${TODAY}.md"

TASKS="screaming-frog-ingest technical-seo-crawl-audit weekly-orphan-fixer weekly-cannibalization-fix"

# Per-task expected values (parallel arrays + case statements; no associative arrays)
expected_ttl() {
  case "$1" in
    screaming-frog-ingest) echo 30 ;;
    technical-seo-crawl-audit) echo 192 ;;
    weekly-orphan-fixer) echo 192 ;;
    weekly-cannibalization-fix) echo 192 ;;
    *) echo "" ;;
  esac
}

expected_allow_missing() {
  case "$1" in
    technical-seo-crawl-audit) echo "present" ;;
    *) echo "absent" ;;
  esac
}

mkdir -p "$REPORT_DIR"

TOTAL_PASS=0
TOTAL_WARN=0
TOTAL_FAIL=0

# --- Header ---
{
  echo "# scheduled-task-validator run — $TODAY"
  echo
  echo "**Validator version:** $VERSION"
  echo "**Tasks scanned:** 4"
  echo "**Scaffolding source-of-truth:**"
  echo
  echo "- Guards README: `$GUARDS_README`"
  echo "- QA reflection: `$QA_REFLECTION`"
  echo "- Notion SAIL KB data source: `$NOTION_DSID`"
  echo
  echo "Legend: PASS = check satisfied. WARN = soft issue, no abort. FAIL = required scaffolding missing."
  echo
  echo "---"
  echo
} > "$REPORT"

# --- Per-task checks ---
for TASK in $TASKS; do
  SKILL="$SCHED_DIR/$TASK/SKILL.md"
  EXP_TTL="$(expected_ttl "$TASK")"
  EXP_AM="$(expected_allow_missing "$TASK")"

  {
    echo "## $TASK"
    echo
    echo "**Path:** `$SKILL`"
    echo
    echo "| Status | Check | Detail |"
    echo "|--------|-------|--------|"
  } >> "$REPORT"

  if [ ! -f "$SKILL" ]; then
    echo "| FAIL | 0. SKILL.md exists | File not found at $SKILL |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    echo >> "$REPORT"
    echo "---" >> "$REPORT"
    echo >> "$REPORT"
    continue
  fi

  # Check 1: PREFLIGHT block present
  if grep -q "PREFLIGHT" "$SKILL"; then
    echo "| PASS | 1. PREFLIGHT block present | Heading found |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| FAIL | 1. PREFLIGHT block present | No PREFLIGHT heading |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi

  # Check 2: Staleness guard invocation
  if grep -q "staleness-guard.sh" "$SKILL"; then
    echo "| PASS | 2. Staleness guard invocation | staleness-guard.sh referenced |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| FAIL | 2. Staleness guard invocation | staleness-guard.sh missing |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi

  # Check 3: Guard ttl matches expected
  TTL_FOUND=""
  TTL_FOUND="$(grep -A 4 "staleness-guard.sh" "$SKILL" | grep -oE '\b[0-9]+\b' | head -1)"
  if [ "$TTL_FOUND" = "$EXP_TTL" ]; then
    echo "| PASS | 3. Guard ttl matches expected | ttl=$TTL_FOUND |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| FAIL | 3. Guard ttl matches expected | expected=$EXP_TTL got=$TTL_FOUND |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi

  # Check 4: --allow-missing usage (scoped to actual bash invocation block)
  INVOCATION_BLOCK="$(awk '
    /^bash .*staleness-guard\.sh/ { in_block=1; print; next }
    in_block==1 {
      print
      if ($0 !~ /\[[:space:]]*$/) { in_block=0 }
    }
  ' "$SKILL")"
  if printf "%s" "$INVOCATION_BLOCK" | grep -q -- "--allow-missing"; then
    AM_ACTUAL="present"
  else
    AM_ACTUAL="absent"
  fi
  if [ "$AM_ACTUAL" = "$EXP_AM" ]; then
    echo "| PASS | 4. --allow-missing usage | $AM_ACTUAL (expected) |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| FAIL | 4. --allow-missing usage | expected=$EXP_AM got=$AM_ACTUAL |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi

  # Check 5: Guard-contract pointer
  if grep -q "_guards/README.md" "$SKILL"; then
    echo "| PASS | 5. Guard-contract pointer | Found |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| FAIL | 5. Guard-contract pointer | Missing _guards/README.md reference |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi

  # Check 6: Post-run QA reflection load
  if grep -q "_post-run-qa-reflection.md" "$SKILL"; then
    echo "| PASS | 6. Post-run QA reflection load | Found |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| FAIL | 6. Post-run QA reflection load | Missing _post-run-qa-reflection.md reference |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi

  # Check 7: Notion data source ID
  if grep -q "$NOTION_DSID" "$SKILL"; then
    echo "| PASS | 7. Notion data source ID | Found |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| FAIL | 7. Notion data source ID | Missing $NOTION_DSID |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi

  # Check 8: JSON-encoded string note
  if grep -q "JSON-encoded" "$SKILL"; then
    echo "| PASS | 8. JSON-encoded string note | Found |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| WARN | 8. JSON-encoded string note | No 'JSON-encoded' phrase found |" >> "$REPORT"
    TOTAL_WARN=$((TOTAL_WARN + 1))
  fi

  # Check 9: Reconstruction preamble cleared
  if grep -q "reconstructed on " "$SKILL"; then
    echo "| FAIL | 9. Reconstruction preamble cleared | Body still carries 'reconstructed on' note |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  else
    echo "| PASS | 9. Reconstruction preamble cleared | Body clean |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  fi

  # Check 10: Frontmatter sanity (name: matches dir)
  FM_NAME="$(awk '/^---$/{c++; next} c==1 && /^name:/ {sub(/^name: */, ""); print; exit}' "$SKILL")"
  if [ "$FM_NAME" = "$TASK" ]; then
    echo "| PASS | 10. Frontmatter sanity | name: $FM_NAME matches dir |" >> "$REPORT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "| FAIL | 10. Frontmatter sanity | name='$FM_NAME' expected='$TASK' |" >> "$REPORT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi

  echo >> "$REPORT"
  echo "---" >> "$REPORT"
  echo >> "$REPORT"
done

# --- Summary ---
TOTAL_CHECKS=$((TOTAL_PASS + TOTAL_WARN + TOTAL_FAIL))
RESULT="PASS"
if [ "$TOTAL_FAIL" -gt 0 ]; then RESULT="FAIL"; fi

{
  echo "## Summary"
  echo
  echo "**Totals across 4 tasks:** $TOTAL_PASS PASS, $TOTAL_WARN WARN, $TOTAL_FAIL FAIL (of $TOTAL_CHECKS checks)."
  echo
  echo "Result: **$RESULT**."
  echo
  echo "Report written: `$REPORT`"
  echo
  echo "---"
  echo
  echo "## Validator metadata"
  echo
  echo "- **Version:** $VERSION"
  echo "- **Skill path:** `/Users/samaguiar/Documents/Projects/Skills/scheduled-task-validator/SKILL.md`"
  echo "- **Script path:** `/Users/samaguiar/Documents/Projects/Skills/scheduled-task-validator/validate.sh`"
  echo "- **Reproducibility:** A fresh `bash validate.sh` (no args) reproduces this run 1:1 unless any of the 4 SKILL.md files changed."
} >> "$REPORT"

echo "Validator $VERSION done: $TOTAL_PASS PASS, $TOTAL_WARN WARN, $TOTAL_FAIL FAIL. Report: $REPORT"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0

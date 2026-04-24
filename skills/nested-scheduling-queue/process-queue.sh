#!/bin/bash
# nested-scheduling-queue v1.0.0
# Drains JSON requests from /Users/samaguiar/Documents/Codex/scheduled-task-requests/pending/
# Validates each one and prints a READY plan line for the Claude orchestrator to act on.
# Portable: macOS bash 3.2 + BSD userland.
# Run: bash process-queue.sh             (list mode — default)
#      bash process-queue.sh --commit <filename> <task_id> <scheduled_for>
#      bash process-queue.sh --fail   <filename> "<error message>"

set -u

VERSION="1.0.0"
ROOT="/Users/samaguiar/Documents/Codex/scheduled-task-requests"
PENDING="$ROOT/pending"
PROCESSED="$ROOT/processed"
FAILED="$ROOT/failed"
LOG_DIR="/Users/samaguiar/Documents/Codex/nested-scheduling-runs"
TODAY="$(date +%Y-%m-%d)"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG="$LOG_DIR/${TODAY}.md"

mkdir -p "$PENDING" "$PROCESSED/$TODAY" "$FAILED/$TODAY" "$LOG_DIR"

# --- Helpers ---

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq is required (brew install jq)" >&2
    exit 2
  fi
}

log_line() {
  printf "%s | %s\n" "$NOW_UTC" "$1" >> "$LOG"
}

ensure_log_header() {
  if [ ! -f "$LOG" ]; then
    {
      echo "# nested-scheduling-queue run log — $TODAY"
      echo
      echo "**Processor version:** $VERSION"
      echo "**Queue root:** \`$ROOT\`"
      echo
      echo "Format: \`<UTC timestamp> | <event> | <filename> [details]\`"
      echo
    } > "$LOG"
  fi
}

# --- Subcommand: --commit ---

if [ "${1:-}" = "--commit" ]; then
  require_jq
  ensure_log_header
  FILE="${2:-}"
  TASK_ID="${3:-}"
  SCHED="${4:-}"
  if [ -z "$FILE" ] || [ -z "$TASK_ID" ] || [ -z "$SCHED" ]; then
    echo "FAIL: --commit requires <filename> <task_id> <scheduled_for>" >&2
    exit 2
  fi
  SRC="$PENDING/$FILE"
  if [ ! -f "$SRC" ]; then
    echo "FAIL: $SRC not found" >&2
    exit 2
  fi
  DEST="$PROCESSED/$TODAY/$FILE"
  mv "$SRC" "$DEST"
  RESP="${DEST%.json}.response.json"
  cat > "$RESP" <<EOF
{
  "committedAtUtc": "$NOW_UTC",
  "taskId": "$TASK_ID",
  "scheduledFor": "$SCHED",
  "processorVersion": "$VERSION"
}
EOF
  log_line "COMMIT | $FILE | taskId=$TASK_ID scheduledFor=$SCHED"
  echo "OK committed $FILE -> $DEST"
  exit 0
fi

# --- Subcommand: --fail ---

if [ "${1:-}" = "--fail" ]; then
  ensure_log_header
  FILE="${2:-}"
  ERR="${3:-unspecified}"
  if [ -z "$FILE" ]; then
    echo "FAIL: --fail requires <filename> \"<error message>\"" >&2
    exit 2
  fi
  SRC="$PENDING/$FILE"
  if [ ! -f "$SRC" ]; then
    echo "FAIL: $SRC not found in pending/" >&2
    exit 2
  fi
  DEST="$FAILED/$TODAY/$FILE"
  mv "$SRC" "$DEST"
  ERRFILE="${DEST%.json}.error.txt"
  printf "%s\n%s\n" "$NOW_UTC" "$ERR" > "$ERRFILE"
  log_line "FAIL | $FILE | $ERR"
  echo "Marked failed: $FILE -> $DEST"
  exit 0
fi

# --- Default: list-and-validate mode ---

require_jq
ensure_log_header

COUNT=0
READY=0
INVALID=0

for SRC in "$PENDING"/*.json; do
  [ -f "$SRC" ] || continue
  COUNT=$((COUNT + 1))
  FILE="$(basename "$SRC")"

  # 1. Valid JSON?
  if ! python3 -m json.tool "$SRC" >/dev/null 2>&1; then
    echo "INVALID $FILE -> JSON parse error"
    log_line "INVALID | $FILE | JSON parse error"
    INVALID=$((INVALID + 1))
    continue
  fi

  # 2. Required fields
  SCHEMA="$(jq -r '.schemaVersion // empty' "$SRC")"
  CREATED_BY="$(jq -r '.createdBy // empty' "$SRC")"
  DESC="$(jq -r '.description // empty' "$SRC")"
  PROMPT="$(jq -r '.prompt // empty' "$SRC")"
  FIRE_AT="$(jq -r '.fireAtUtc // empty' "$SRC")"
  CRON="$(jq -r '.cron // empty' "$SRC")"

  if [ "$SCHEMA" != "1" ]; then
    echo "INVALID $FILE -> schemaVersion must be 1 (got '$SCHEMA')"
    log_line "INVALID | $FILE | schemaVersion=$SCHEMA"
    INVALID=$((INVALID + 1))
    continue
  fi
  if [ -z "$CREATED_BY" ] || [ -z "$DESC" ] || [ -z "$PROMPT" ]; then
    echo "INVALID $FILE -> missing required field (createdBy / description / prompt)"
    log_line "INVALID | $FILE | missing required field"
    INVALID=$((INVALID + 1))
    continue
  fi

  # 3. Exactly one of fireAtUtc / cron
  if [ -n "$FIRE_AT" ] && [ -n "$CRON" ]; then
    echo "INVALID $FILE -> both fireAtUtc and cron set (must be exactly one)"
    log_line "INVALID | $FILE | both fireAtUtc and cron set"
    INVALID=$((INVALID + 1))
    continue
  fi
  if [ -z "$FIRE_AT" ] && [ -z "$CRON" ]; then
    echo "INVALID $FILE -> neither fireAtUtc nor cron set"
    log_line "INVALID | $FILE | neither fireAtUtc nor cron set"
    INVALID=$((INVALID + 1))
    continue
  fi

  # 4. fireAtUtc not already in the past (only when fireAtUtc is set)
  if [ -n "$FIRE_AT" ]; then
    # BSD date: -j parses, -f format, +%s epoch
    FIRE_EPOCH="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$FIRE_AT" +%s 2>/dev/null || echo 0)"
    NOW_EPOCH="$(date -u +%s)"
    if [ "$FIRE_EPOCH" = "0" ]; then
      echo "INVALID $FILE -> fireAtUtc unparseable: $FIRE_AT"
      log_line "INVALID | $FILE | fireAtUtc unparseable"
      INVALID=$((INVALID + 1))
      continue
    fi
    if [ "$FIRE_EPOCH" -le "$NOW_EPOCH" ]; then
      echo "INVALID $FILE -> fireAtUtc is in the past: $FIRE_AT"
      log_line "INVALID | $FILE | fireAtUtc in past"
      INVALID=$((INVALID + 1))
      continue
    fi
  fi

  # 5. Ready
  if [ -n "$FIRE_AT" ]; then
    echo "READY $FILE -> create_scheduled_task(\"$DESC\", fireAtUtc=$FIRE_AT)"
    log_line "READY | $FILE | fireAtUtc=$FIRE_AT createdBy=$CREATED_BY"
  else
    echo "READY $FILE -> create_scheduled_task(\"$DESC\", cron=$CRON)"
    log_line "READY | $FILE | cron=$CRON createdBy=$CREATED_BY"
  fi
  READY=$((READY + 1))
done

# --- Summary ---

{
  echo
  echo "## Summary $NOW_UTC"
  echo
  echo "- Pending scanned: $COUNT"
  echo "- READY: $READY"
  echo "- INVALID: $INVALID"
  echo
} >> "$LOG"

echo "process-queue $VERSION done: scanned=$COUNT ready=$READY invalid=$INVALID. Log: $LOG"
exit 0

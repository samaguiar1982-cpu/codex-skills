---
name: nested-scheduling-queue
description: Workaround for the scheduled-tasks MCP refusing to call create_scheduled_task from inside a scheduled session. A scheduled task drops a JSON request file into /Users/samaguiar/Documents/Codex/scheduled-task-requests/pending/, and a non-scheduled processor (run by Sam in a normal session, or by launchd / Codex remote) drains the queue and creates the actual scheduled tasks. Use whenever a scheduled SF-chain task or weekly skill needs to enqueue a follow-up scheduled task, when the scheduled-tasks MCP returns the "cannot create from scheduled session" error, or when designing any new SF-chain step that may need to spawn downstream timed work.
---

# nested-scheduling-queue

Sam pick **Q-W3=Other** on 2026-04-24: "do whatever necessary to nix anything keeping us from creating scheduled tasks within a scheduled session." This skill is the workaround. It does not patch the MCP server (we don't own that code); it routes around the restriction with a queue + processor pattern.

## The problem

`mcp__scheduled-tasks__create_scheduled_task` refuses execution when the caller is itself running inside a scheduled session. SF-chain tasks (screaming-frog-ingest, technical-seo-crawl-audit, weekly-orphan-fixer, weekly-cannibalization-fix) sometimes legitimately need to enqueue a downstream scheduled task — for example, a one-shot retry, a follow-up audit two hours later, or a Notion-export deferral. Today those calls fail.

## The workaround

Two directories + one processor script + a 4-field JSON contract.

**Directories** (already created):

- `/Users/samaguiar/Documents/Codex/scheduled-task-requests/pending/` — drop new requests here as JSON files
- `/Users/samaguiar/Documents/Codex/scheduled-task-requests/processed/YYYY-MM-DD/` — successful requests are moved here (with the create_scheduled_task response appended as `<filename>.response.json`)
- `/Users/samaguiar/Documents/Codex/scheduled-task-requests/failed/YYYY-MM-DD/` — requests that failed validation or the MCP call land here with an `<filename>.error.txt`

**Filename convention:** `<UTC ISO timestamp>__<slug>.json` (e.g. `20260424T180000Z__retry-orphan-fixer.json`). The leading timestamp keeps `ls` ordering chronological.

## The JSON contract

Every queued request is a JSON object with exactly these fields:

```json
{
  "schemaVersion": 1,
  "createdBy": "screaming-frog-ingest",
  "createdAtUtc": "2026-04-24T18:00:00Z",
  "description": "Retry technical-seo-crawl-audit at 19:00 if the 18:00 run flagged ttl FAIL",
  "prompt": "Run /technical-seo-crawl-audit. PREFLIGHT: respect _guards/staleness-guard.sh ttl=192. Post-run QA reflection per _post-run-qa-reflection.md. Notion export to SAIL KB 13d5d9db-4588-41bc-afa9-45ce9e23e56c.",
  "fireAtUtc": "2026-04-24T19:00:00Z",
  "cron": null,
  "notes": "One-shot retry. cron must be null when fireAtUtc is set."
}
```

Rules the producer (the scheduled task dropping the request) must follow:

1. Either `fireAtUtc` OR `cron` is non-null; never both.
2. `prompt` must be self-contained — the queued task wakes up in a fresh session with no shared memory.
3. `prompt` must include the same scaffolding the SF-chain validator checks for (PREFLIGHT, staleness-guard.sh ttl, _guards/README.md pointer, _post-run-qa-reflection.md load, Notion SAIL KB data source ID, JSON-encoded string note for Tags/Project).
4. JSON must be valid and `schemaVersion` must be `1`.
5. Tags/Project on the eventual Notion page (set by the queued task, not by the processor) must be JSON-encoded strings, not literal arrays — same recurring trap that Notion validation hits.

## The processor

`/Users/samaguiar/Documents/Projects/Skills/nested-scheduling-queue/process-queue.sh`

Runs from a non-scheduled context (a normal Claude session, or — once Q-W1 lands — a GitHub Actions cron with the scheduled-tasks MCP available). For each `*.json` in `pending/`:

1. Validate JSON (`python3 -m json.tool`) and required fields (jq).
2. Print a single-line plan: `READY <filename> -> create_scheduled_task(<description>, <fireAtUtc|cron>)`.
3. The Claude orchestrator (not the bash script) calls `mcp__scheduled-tasks__create_scheduled_task` with the request payload.
4. On success, move the JSON to `processed/YYYY-MM-DD/` and write a sibling `.response.json` capturing the MCP response (taskId, scheduledFor).
5. On failure, move the JSON to `failed/YYYY-MM-DD/` and write a sibling `.error.txt` with the failure reason.

**Important:** the bash script alone CANNOT create the scheduled task — only Claude can call MCP tools. The script's job is validation + listing. The Claude session that runs it then iterates the printed plan and makes the actual MCP calls.

## Quick run

```
bash /Users/samaguiar/Documents/Projects/Skills/nested-scheduling-queue/process-queue.sh
```

Prints a list of pending requests. The Claude orchestrator that runs this skill then:

1. Reads each `READY` line.
2. Calls `mcp__scheduled-tasks__create_scheduled_task` with the parsed payload.
3. On success, runs `bash process-queue.sh --commit <filename> <task_id> <scheduled_for>` to move the file and write the response.
4. On failure, runs `bash process-queue.sh --fail <filename> "<error message>"`.

## How an SF-chain task uses this

Inside a scheduled SF-chain run, instead of attempting `mcp__scheduled-tasks__create_scheduled_task` directly (which fails), write a JSON request to `pending/`:

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"
SLUG="retry-orphan-fixer"
cat > "/Users/samaguiar/Documents/Codex/scheduled-task-requests/pending/${TS}__${SLUG}.json" <<EOF
{
  "schemaVersion": 1,
  "createdBy": "weekly-orphan-fixer",
  "createdAtUtc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "description": "Retry weekly-orphan-fixer 90 minutes from now after thin-shell guard cleared",
  "prompt": "Run /weekly-orphan-fixer. PREFLIGHT: staleness-guard.sh ttl=192 (consume screaming-frog-ingest output). Guard contract: see _guards/README.md. Post-run QA reflection: load _post-run-qa-reflection.md. Notion SAIL KB export to data source 13d5d9db-4588-41bc-afa9-45ce9e23e56c. Tags/Project must be JSON-encoded strings, not literal arrays.",
  "fireAtUtc": "$(date -u -v+90M +%Y-%m-%dT%H:%M:%SZ)",
  "cron": null,
  "notes": "Auto-retry after thin-shell guard FAIL"
}
EOF
```

The producer never needs the scheduled-tasks MCP. The processor handles that on a non-scheduled rail.

## Constraints (per Sam pick Q-V6=A on 2026-04-23)

- **macOS bash 3.2 + BSD userland.** No associative arrays, no GNU `grep -P`, no `sed -i` without backup suffix, no `date -d`, no `find -printf`.
- **`date -u -v+90M`** for UTC arithmetic (BSD, not GNU `date -d "+90 minutes"`).
- **`mv` not `rename`.** `rename` is GNU-only.
- **No nested scheduling inside the processor either.** If the processor itself runs from a scheduled session, the create_scheduled_task call still fails. Run the processor from a normal Claude session, OR from the Q-W1 GitHub Actions remote (which is not a scheduled-session caller from the MCP's perspective).
- **Mirror to GitHub.** When this skill changes, mirror to `samaguiar1982-cpu/codex-skills` under `skills/nested-scheduling-queue/`.

## Failure modes the processor catches

1. **Invalid JSON** → moved to `failed/`, error.txt notes the parse error.
2. **Missing required field** → moved to `failed/`, error.txt names the missing field.
3. **Both `fireAtUtc` and `cron` set, or neither** → failed/.
4. **`fireAtUtc` already in the past** → failed/ with error noting drift; producer should resubmit.
5. **`schemaVersion != 1`** → failed/, prevents future-format silent acceptance.
6. **MCP call returns an error** → failed/, error.txt captures the MCP error verbatim.

## Output

`process-queue.sh` writes a one-line summary to stdout for the orchestrator + a structured run log to `/Users/samaguiar/Documents/Codex/nested-scheduling-runs/YYYY-MM-DD.md`.

## Version history

- **v1.0.0 (2026-04-24):** Initial workaround per Sam pick Q-W3=Other on 2026-04-24. Queue + processor pattern with bash-only validation; Claude orchestrator handles the MCP calls. Mirrored to GitHub `samaguiar1982-cpu/codex-skills/skills/nested-scheduling-queue/`.

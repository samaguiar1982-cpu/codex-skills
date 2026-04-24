---
name: scheduled-task-validator
description: Validates that scheduled-task SKILL.md files in /Users/samaguiar/Documents/Claude/Scheduled/ carry the required scaffolding (PREFLIGHT staleness guard, guard-contract pointer, post-run QA reflection load, Notion SAIL KB data source, JSON-encoded string note, frontmatter sanity, reconstruction preamble cleared). Use when auditing scheduled-task scaffolding, after Wave-2 changes, before kicking off the SF chain, or on the weekly Monday cadence.
---

# scheduled-task-validator

Audits the SF-chain scheduled tasks under `/Users/samaguiar/Documents/Claude/Scheduled/` against a 10-check rubric so scaffolding drift is caught before the chain runs.

This file is a v2.0 rebuild (2026-04-24) after on-disk verification confirmed the v1.1.5 claim from the prior session was a false positive. Substance of the rubric matches what the prior run report described, but Sam should treat this as a fresh start.

## What this skill does

1. Iterates the 4 SF-chain tasks: `screaming-frog-ingest`, `technical-seo-crawl-audit`, `weekly-orphan-fixer`, `weekly-cannibalization-fix`.
2. Runs 10 PASS/WARN/FAIL checks per task.
3. Writes a single Markdown report to `/Users/samaguiar/Documents/Codex/validator-runs/YYYY-MM-DD.md`.
4. Exits 0 (PASS) only when every required check passes across every task.

## Quick run

```
bash /Users/samaguiar/Documents/Projects/Skills/scheduled-task-validator/validate.sh
```

No arguments. Idempotent. A fresh `bash validate.sh` reproduces the previous run 1:1 unless any of the 4 SKILL.md files changed.

## The 10 checks

For each of the 4 SF-chain SKILL.md files:

1. **PREFLIGHT block present.** A heading containing "PREFLIGHT" exists in the file body.
2. **Staleness guard invocation.** The literal string `staleness-guard.sh` appears (the guard is invoked, not just referenced).
3. **Guard ttl matches expected.** The numeric TTL passed to `staleness-guard.sh` matches the per-task expected value (table below).
4. **--allow-missing usage.** Either present or absent matching the per-task expected value (table below).
5. **Guard-contract pointer.** The literal string `_guards/README.md` appears (so consumers stay synced with the guard contract).
6. **Post-run QA reflection load.** The literal string `_post-run-qa-reflection.md` appears (the post-run reflection block is loaded).
7. **Notion data source ID.** The literal string `13d5d9db-4588-41bc-afa9-45ce9e23e56c` appears (so Notion exports land in SAIL KB).
8. **JSON-encoded string note.** A note explaining Tags/Project must be JSON-encoded strings, not literal arrays (catches the recurring Notion validation failure).
9. **Reconstruction preamble cleared.** No leftover "This prompt was reconstructed on YYYY-MM-DD" preamble in the body (Q3=A auto-clear rule from 2026-04-23).
10. **Frontmatter sanity.** The YAML frontmatter contains a `name:` key matching the directory name.

## Per-task expected values

| Task | Expected ttl | Expected --allow-missing |
|------|--------------|--------------------------|
| screaming-frog-ingest | 30 | absent (this is the producer, not a consumer) |
| technical-seo-crawl-audit | 192 | present (only task with a fallback path) |
| weekly-orphan-fixer | 192 | absent |
| weekly-cannibalization-fix | 192 | absent |

## Constraints (per Sam pick Q-V6=A on 2026-04-23)

This script must run on macOS (bash 3.2 + BSD userland). Specifically:

- **No associative arrays.** Use case statements or parallel indexed arrays.
- **No `grep -P`, `\d`, `\s`, `\w`.** Use POSIX classes (`[[:digit:]]`, `[[:space:]]`).
- **BSD grep caps `.{1,N}` at 255.** Avoid wide quantifiers; split the regex.
- **No `sed -i` without backup suffix.** Write to temp file and `mv`.
- **No `date -d`, no `find -printf`, no `readlink -f`, no `stat -c`.** See bash-portability-checklist skill for replacements.
- **No nested scheduling.** This script must NOT call `mcp__scheduled-tasks__create_scheduled_task` from within a scheduled session — the API refuses.
- **Mirroring.** When the validator changes, mirror to GitHub `samaguiar1982-cpu/codex-skills` under `skills/scheduled-task-validator/`. Don't rely on the host disk being the only copy.

## Output format

Single Markdown report written to `/Users/samaguiar/Documents/Codex/validator-runs/YYYY-MM-DD.md` with:

- Header (validator version, tasks scanned, scaffolding source-of-truth paths)
- One section per task with a 10-row PASS/WARN/FAIL table
- Summary totals
- Validator metadata block (script path, version, reproducibility note)

## Post-run QA reflection

Load and follow `/Users/samaguiar/Documents/Claude/Scheduled/_post-run-qa-reflection.md`. Append `## QA Recommendations Pending Approval` (4-way MC, A=recommended) to the run report and the Codex QA queue file. Tag QA: Open or QA: Clean.

## Self-integrity check (v2.1.0+)

Per Sam pick Q-W2=A on 2026-04-24, validate.sh hashes itself on every run and aborts with exit code 2 if the on-disk script does not match the pinned `EXPECTED_HASH` constant.

- The hash excludes the line containing `SELF_HASH_SENTINEL` (so the constant itself is not part of what's hashed; otherwise updating the hash would break the hash).
- Procedure to legitimately edit validate.sh: make the edit, recompute the hash via `grep -v SELF_HASH_SENTINEL validate.sh | shasum -a 256`, write that value into `EXPECTED_HASH`, commit.
- Skipped only when `EXPECTED_HASH` is the literal placeholder `REPLACE_WITH_REAL_HASH` (so a fresh-cloned-but-unpinned script doesn't false-fail).
- Catches the v1.1.5 "claimed-but-never-written" failure mode AND any unauthorized edits.

Current pinned hash (v2.2.0): `8fc43f94059848de09ff39ed272a77d8de7288d4e5cf3098a2393405228c5417` (also see `EXPECTED_HASH` near the top of validate.sh).

## Env vars (v2.2.0+)

| Var | Default | Use case |
|-----|---------|----------|
| `SAIL_SCHED_DIR` | `/Users/samaguiar/Documents/Claude/Scheduled` | Point validator at a checkout (e.g., `$GITHUB_WORKSPACE/sail-scheduled-tasks`) on CI runners. |
| `SAIL_REPORT_DIR` | `/Users/samaguiar/Documents/Codex/validator-runs` | Point report writes at a workflow artifact dir. |

Set them inline: `SAIL_SCHED_DIR=/tmp/sched bash validate.sh`

## Version history

- **v2.2.0 (2026-04-24):** Added env-var-driven path config (Q-W8=A). `SAIL_SCHED_DIR` overrides `~/Documents/Claude/Scheduled`; `SAIL_REPORT_DIR` overrides `~/Documents/Codex/validator-runs`. Defaults preserve v2.1.0 behavior on Sam\'s iMac. Removes the symlink/sudo/chown dance from the GitHub Actions workflow. Self-integrity hash recomputed and pinned: `8fc43f94059848de09ff39ed272a77d8de7288d4e5cf3098a2393405228c5417`. Verified 40/40 PASS on 2026-04-24.
- **v2.1.0 (2026-04-24):** Added SHA256 self-integrity check (Q-W2=A). Script hashes itself on every run and aborts (exit 2) if pinned `EXPECTED_HASH` doesn\'t match computed hash. Negative test verified: tampered script returns exit 2 with clear FAIL message. Pinned hash on 2026-04-24: `74f1588d7ae4b71af02c99a12eeb8b6a881c6d83e0d95c00cbb57e5b0fcaf561`.
- **v2.0.1 (2026-04-24):** Patched check 4 (`--allow-missing` usage). v2.0 grep\'d the entire file and falsely flagged 3 tasks because the Guard-contract pointer comment also mentions `--allow-missing` in prose. v2.0.1 scopes the check to the actual `bash ... staleness-guard.sh` invocation block (plus any `\` continuation lines). Verified 40/40 PASS on 2026-04-24.
- **v2.0 (2026-04-24):** Fresh rebuild after on-disk verification showed v1.1.5 was a false positive. Substance preserved from the v1.1.5 report rubric. Constraints section added per Sam pick Q-V6=A (2026-04-23).
- v1.1.5 (claimed 2026-04-23): Listed in prior run report at /Users/samaguiar/Documents/Codex/validator-runs/2026-04-23.md but never written to disk. Confirmed via Desktop_Commander get_file_info ENOENT and full-disk search.
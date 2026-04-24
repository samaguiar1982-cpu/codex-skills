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
8. **JSON-encoded string note.** A note explaining Tags/Project must be JSON-encoded strings, not literal arrays.
9. **Reconstruction preamble cleared.** No leftover "This prompt was reconstructed on YYYY-MM-DD" preamble in the body.
10. **Frontmatter sanity.** The YAML frontmatter contains a `name:` key matching the directory name.

## Per-task expected values

| Task | Expected ttl | Expected --allow-missing |
|------|--------------|--------------------------|
| screaming-frog-ingest | 30 | absent |
| technical-seo-crawl-audit | 192 | present |
| weekly-orphan-fixer | 192 | absent |
| weekly-cannibalization-fix | 192 | absent |

## Constraints

- macOS bash 3.2 + BSD userland. No associative arrays. No `grep -P`, `\d`, `\s`, `\w`. POSIX classes only. No `sed -i` without backup suffix.
- **No nested scheduling.** Per the scheduled-tasks MCP, `create_scheduled_task` refuses to fire from inside a scheduled session. See `nested-scheduling-queue` skill for the queue-based workaround (Q-W3, 2026-04-24).
- **Mirroring.** Mirror to GitHub `samaguiar1982-cpu/codex-skills` under `skills/scheduled-task-validator/` whenever the validator changes.

## Self-integrity check (v2.1.0+)

Per Sam pick Q-W2=A on 2026-04-24, validate.sh hashes itself on every run and aborts with exit code 2 if the on-disk script does not match the pinned `EXPECTED_HASH` constant.

- The hash excludes the line containing `SELF_HASH_SENTINEL`.
- Procedure to legitimately edit validate.sh: edit, recompute via `grep -v SELF_HASH_SENTINEL validate.sh | shasum -a 256`, write that value into `EXPECTED_HASH`, commit.
- Skipped only when `EXPECTED_HASH` is the literal placeholder `REPLACE_WITH_REAL_HASH`.
- Catches the v1.1.5 "claimed-but-never-written" failure mode AND any unauthorized edits.

Current pinned hash: `74f1588d7ae4b71af02c99a12eeb8b6a881c6d83e0d95c00cbb57e5b0fcaf561`.

## launchd weekly schedule (Mondays 11:00 local)

Loaded as user agent `com.sam.validator.weekly` (plist at `~/Library/LaunchAgents/com.sam.validator.weekly.plist`, mirror in this skill folder).

**Known TCC blocker (2026-04-24, Q-W4 smoke test):** the launchd-spawned `/bin/bash` lacks Full Disk Access for `~/Documents/`, so the agent fires but the script returns "Operation not permitted." Stderr log: `/Users/samaguiar/Documents/Codex/validator-runs/_launchd-stderr.log`. Manual `bash validate.sh` works because the user's interactive shell inherits FDA. Resolution paths:

1. Grant `/bin/bash` Full Disk Access via System Settings → Privacy & Security → Full Disk Access.
2. Relocate validator infrastructure outside `~/Documents/`, to a non-TCC-protected path.
3. Run weekly via the GitHub Actions remote runner (Q-W1) which sidesteps macOS TCC entirely.

## Version history

- **v2.1.0 (2026-04-24):** Added SHA256 self-integrity check (Q-W2=A). Pinned hash: `74f1588d7ae4b71af02c99a12eeb8b6a881c6d83e0d95c00cbb57e5b0fcaf561`. Negative test verified: tampered script returns exit 2.
- **v2.0.1 (2026-04-24):** Patched check 4 (`--allow-missing` usage) — scoped to actual bash invocation block, not the whole file. Verified 40/40 PASS.
- **v2.0 (2026-04-24):** Fresh rebuild after on-disk verification showed v1.1.5 was a false positive.
- v1.1.5 (claimed 2026-04-23): Listed in prior run report but never written to disk. Confirmed via Desktop_Commander get_file_info ENOENT.

End of file content.
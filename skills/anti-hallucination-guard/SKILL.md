# Anti-Hallucination Guard v2.0

> Auto-activate on session start. Setup.sh merges rules into AGENT_RULES.md with markers.
> Compatible with cascade-guard: Rule 1-14 (AHG) + Rule C-1..C-9 (Cascade) coexist.
> Three-mode architecture: DISCOVER (proactive) -> GENERATE (atomic) -> VERIFY (enforce).

## Purpose

Prevent AI agent from hallucinating, looping, or faking activity
in Z.ai sandbox environments. Prevent documentation from drifting
away from actual codebase state. Prevent agents from bypassing
anti-hallucination mechanisms.

## Activation

This skill MUST auto-activate at the beginning of every session.
Agent must read AGENT_RULES.md and worklog.md before any work.

## Three-mode architecture

### DISCOVER (proactive -- no config required)

Auto-scans the project and reports issues without needing verify-docs.json:
- Finds all files containing version numbers, checks if they are in sync
- Finds CHANGELOG files, verifies freshness (latest entry matches current version)
- Scans source directories for code files not mentioned in documentation
- Compares current file list against baseline (detects deleted files)

```bash
bash scripts/ahg.sh discover
```

Runs automatically as fallback in pre-commit hook when verify-docs.json does not exist.

### GENERATE (atomic changes)

Updates versions and generates configuration atomically:
- `ahg bump X.Y.Z` -- updates ALL discovered version files at once + CHANGELOG entry
- `ahg init` -- generates verify-docs.json from auto-discover results
- `ahg baseline` -- creates .ahg-baseline.json for deletion tracking

```bash
bash scripts/ahg.sh bump 2.1.0
bash scripts/ahg.sh bump 2.1.0 --dry-run  # preview
bash scripts/ahg.sh init
bash scripts/ahg.sh baseline
```

### VERIFY (enforce existing checks)

Cross-checks documentation against the codebase using verify-docs.json config:

```bash
bash scripts/ahg.sh verify
bash scripts/ahg.sh verify --ci
```

## Setup Procedure

Execute these steps IN ORDER before any other work:

### Step 1: Merge AHG rules into AGENT_RULES.md

Setup.sh uses marker-based merging (`<!-- AHG:START -->` / `<!-- AHG:END -->`).
If cascade-guard is also installed, its block (`<!-- CASCADE-GUARD:START -->` / `<!-- CASCADE-GUARD:END -->`)
will coexist without conflict.

AHG rules (Rule 1-14): worklog, read-before-write, no-loops, honest reporting, work structure, sandbox verification, session start protocol, documentation sync, integrity protection, anti-monolith, ahg bump, pre-commit checklist, unicode policy.
Cascade rules (C-1 to C-9): source-of-truth, start-protocol, deps, priorities, acceptance verification.

### Step 2: Create worklog.md

Create /worklog.md in project root if not exists.

### Step 3: Setup pre-commit hook

Create .git/hooks/pre-commit from .git-hooks/pre-commit. Five phases:
1. Integrity check (core.hooksPath detection, self-check)
2. Worklog checks (exists, fresh <10min, >50 bytes, >2 blocks)
2.5. sync-task-state (cascade-state auto-sync, non-blocking)
3. verify-docs (if verify-docs.json exists, blocking)
3.5. auto-discover fallback (if no config, blocking)

If a pre-commit hook already exists (e.g. from cascade-guard), AHG checks are appended.

### Step 4: Setup pre-push hook

Create .git/hooks/pre-push from .git-hooks/pre-push:
- Run validate.sh to check module purity
- Block push if foreign files detected

If a pre-push hook already exists, AHG validation is appended (not overwritten).

### Step 5: Install monitoring scripts

Deploy to scripts/:
- ahg.sh -- unified CLI entry point for all AHG commands
- check-agent.sh -- activity monitor (cron or manual)
- audit.sh -- post-session audit with score
- validate.sh -- module purity + Unicode policy checker
- sync-task-state.sh -- auto-sync task statuses based on implementation files
- check-hooks-snapshot.sh -- create integrity snapshot
- check-hooks-verify.sh -- verify against snapshot (anti-tampering)

### Step 6: Cascade-guard integration (auto-detect)

If cascade-guard is detected (via .gitmodules or find), setup.sh automatically:
- Adds cascade-state.json freshness checks to pre-commit hook
- Confirms rule namespacing: Rule 1-14 (AHG) + C-1..C-9 (Cascade)
- Both marker blocks coexist in AGENT_RULES.md

### Step 7: Initialize git (if needed)

```bash
git init 2>/dev/null
git add -A
git commit -m "init: anti-hallucination guard setup"
```

### Step 8: Verify

- AGENT_RULES.md exists with AHG markers: YES
- worklog.md exists: YES
- pre-commit hook exists and executable: YES
- pre-push hook exists and executable: YES
- git initialized: YES
- auto-discover runs without errors: YES

## Runtime Rules (14 Rules)

During work execution, these rules are NON-NEGOTIABLE:

| Rule | Purpose |
|------|---------|
| 1 | worklog -- BEFORE and AFTER every action |
| 2 | Read before write |
| 3 | One logical block -- one commit |
| 4 | No loops (stop after 3rd attempt) |
| 5 | Honest reporting |
| 6 | Work structure (read rules -> step -> execute -> log -> commit) |
| 7 | Sandbox verification (no fake setup) |
| 8 | Session Start Protocol (scan, compare, fix drift) |
| 9 | Documentation sync (no code without docs) |
| 10 | Integrity protection (never bypass mechanisms) |
| 11 | Anti-monolith (no file over 250 lines) |
| 12 | ahg bump (atomic version updates) |
| 13 | Pre-commit mandatory checklist |
| 14 | UNICODE_POLICY (ASCII-only, no emoji, no Unicode graphics) |

## verify-docs Engine (5 Sections + auto-discover)

verify-docs cross-checks documentation against the actual codebase across 5 dimensions:

| Section | What it checks | Config key |
|---------|---------------|------------|
| 1. README vs Code | Numbers in docs match actual counts | `checks` |
| 2. Cross-repo | Values consistent across sibling repos | `crossRepo` |
| 3. Version sync | Version matches across all docs | `versionSync` |
| 4. Feature status | Stub markers don't contradict existing code | `featureStatus` |
| 5. Doc coverage | Code files are mentioned in documentation | `docCoverage` |

Auto-discover modules (no config required):
- `discover-versions.ts` -- finds all files with version patterns
- `discover-changelog.ts` -- finds CHANGELOG files, checks freshness
- `discover-coverage.ts` -- finds source dirs, checks doc mentions
- `discover-baseline.ts` -- creates/checks file baselines for deletion detection

## Baseline tracking

Records which files exist at setup time. Detects deleted files on subsequent runs.

```bash
bash scripts/ahg.sh baseline           # create baseline
bash scripts/ahg.sh baseline --check   # check for deleted files
```

## sync-task-state.sh

Automatically updates task statuses in cascade-state.json (or any JSON
state file) based on the existence of implementation files.

Each task should have an `implementationFiles` array listing files that
prove the task is implemented. If ALL files exist, the task status is
automatically changed from "pending" to "implemented".

Integrated into pre-commit hook Phase 2.5.

```bash
bash scripts/ahg.sh sync               # default: cascade-state.json
bash scripts/ahg.sh sync --dry-run     # preview without writing
```

## Compatibility with Cascade-guard

When both modules are installed:

| Aspect | AHG | Cascade-guard |
|--------|-----|---------------|
| Rule namespace | Rule 1-14 | C-1 to C-9 |
| AGENT_RULES.md markers | `<!-- AHG:START/END -->` | `<!-- CASCADE-GUARD:START/END -->` |
| State file | worklog.md | cascade-state.json |
| Pre-commit checks | worklog + discover + verify | cascade-state.json validity |
| Pre-push checks | validate.sh (module purity) | validate.sh (module purity) |
| Hook strategy | Append if foreign exists | Append if foreign exists |

Both hooks work together: pre-commit checks worklog FIRST, then cascade-state.
Pre-push runs both validate.sh scripts.

## Detection Patterns

Flag these behaviors as potential hallucination:
- Same file edited 3+ times without progress
- "Fixed" claimed but error persists
- worklog not updated for >10 minutes
- Circular git messages (same commit msg repeated)
- Claims file exists but Glob/LS shows otherwise
- Documentation says "stub" but implementation files exist
- Version in docs differs from source of truth
- New modules not mentioned in ARCHITECTURE.md
- Hooks modified or replaced (integrity check fails)
- core.hooksPath set to bypass hooks
- verify-docs.json checks removed to avoid failures
- File exceeds 250 lines (anti-monolith violation)
- Version updated manually instead of ahg bump
- Unicode graphics or emoji in code output

## check-hooks integrity system

Split into two scripts for anti-monolith compliance:
- `check-hooks-snapshot.sh` -- creates SHA256 fingerprints
- `check-hooks-verify.sh` -- compares against snapshot, detects tampering, offers repair

```bash
bash scripts/ahg.sh snapshot              # create integrity snapshot
bash scripts/ahg.sh integrity             # verify against snapshot
bash scripts/ahg.sh integrity --repair    # re-install from module
```

## Triggers

Activate when:
- Session starts (auto)
- User mentions: anti-hallucination, guard, rules, discipline, ahg
- Agent seems to loop or stall
- worklog not updated for extended period
- Documentation drift detected by verify-docs or auto-discover
- Version mismatch detected across files
- File exceeds 250 lines

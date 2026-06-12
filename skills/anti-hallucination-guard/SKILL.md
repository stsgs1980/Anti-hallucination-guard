# Anti-Hallucination Guard v1.4

> Auto-activate on session start. Setup.sh merges rules into AGENT_RULES.md with markers.
> Compatible with cascade-guard: Rule 1-10 (AHG) + Rule C-1..C-9 (Cascade) coexist.

## Purpose

Prevent AI agent from hallucinating, looping, or faking activity
in Z.ai sandbox environments. Prevent documentation from drifting
away from actual codebase state.

## Activation

This skill MUST auto-activate at the beginning of every session.
Agent must read AGENT_RULES.md and worklog.md before any work.

## Setup Procedure

Execute these steps IN ORDER before any other work:

### Step 1: Merge AHG rules into AGENT_RULES.md

Setup.sh uses marker-based merging (`<!-- AHG:START -->` / `<!-- AHG:END -->`).
If cascade-guard is also installed, its block (`<!-- CASCADE-GUARD:START -->` / `<!-- CASCADE-GUARD:END -->`)
will coexist without conflict.

AHG rules (Rule 1-10): worklog, read-before-write, no-loops, honest reporting, work structure, sandbox verification, session start protocol, documentation sync, integrity protection.
Cascade rules (C-1 to C-9): source-of-truth, start-protocol, deps, priorities, acceptance verification.

### Step 2: Create worklog.md

Create /worklog.md in project root if not exists.

### Step 3: Setup pre-commit hook

Create .git/hooks/pre-commit from .git-hooks/pre-commit:
- Check worklog.md exists
- Check worklog.md updated within 10 minutes
- Check worklog.md has proper block format
- Block commit if any check fails
- Cross-platform: works on Linux and macOS
- chmod +x the hook

If a pre-commit hook already exists (e.g. from cascade-guard), AHG checks are appended.

### Step 4: Setup pre-push hook

Create .git/hooks/pre-push from .git-hooks/pre-push:
- Run validate.sh to check module purity
- Block push if foreign files detected

If a pre-push hook already exists, AHG validation is appended (not overwritten).

### Step 5: Install monitoring scripts

Deploy to scripts/:
- check-agent.sh -- activity monitor (cron or manual)
- audit.sh -- post-session audit with score
- validate.sh -- module purity checker
- sync-task-state.sh -- auto-sync task statuses based on implementation files
- check-hooks-integrity.sh -- detect hook tampering / bypass attempts

### Step 6: Cascade-guard integration (auto-detect)

If cascade-guard is detected (via .gitmodules or find), setup.sh automatically:
- Adds cascade-state.json freshness checks to pre-commit hook
- Confirms rule namespacing: Rule 1-10 (AHG) + C-1..C-9 (Cascade)
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

## Runtime Rules

During work execution, these rules are NON-NEGOTIABLE:

1. BEFORE any file write: Read the file first
2. AFTER any file write: Update worklog.md
3. AFTER logical block: git commit (blocked if worklog stale)
4. ON 3rd repeat: STOP and notify user
5. NEVER claim completion without verification
6. SESSION START: scan project structure, compare with docs, fix drift first
7. DOC SYNC: no new code without updating documentation
8. INTEGRITY: never disable, bypass, or weaken anti-hallucination mechanisms

## verify-docs Engine (5 Sections)

verify-docs cross-checks documentation against the actual codebase across 5 dimensions:

| Section | What it checks | Config key |
|---------|---------------|------------|
| 1. README vs Code | Numbers in docs match actual counts | `checks` |
| 2. Cross-repo | Values consistent across sibling repos | `crossRepo` |
| 3. Version sync | Version matches across all docs | `versionSync` |
| 4. Feature status | Stub markers don't contradict existing code | `featureStatus` |
| 5. Doc coverage | Code files are mentioned in documentation | `docCoverage` |

### Section 3: Version Synchronization

Prevents the common problem where README, ARCHITECTURE, and other docs
each carry their own version that diverges over time.

Config: define one source of truth (e.g. manifest.json or package.json),
and list target files that must match.

```json
"versionSync": {
  "source": "file:package.json",
  "extractPattern": "\"version\":\\s*\"([\\d.]+)\"",
  "targets": [
    { "file": "README.md", "pattern": "v([\\d.]+)" },
    { "file": "ARCHITECTURE.md", "pattern": "version:\\s*([\\d.]+)" }
  ]
}
```

### Section 4: Feature Status (Stub Detection)

Detects features documented as "stubs / not implemented / TODO"
but which actually have implementation files in the codebase.

```json
"featureStatus": [
  {
    "name": "Feature name",
    "stubPatterns": ["stub", "TODO", "not implemented"],
    "docFile": "README.md",
    "contextPattern": "feature.name",
    "implementationFiles": ["src/lib/feature.js"],
    "implementedPatterns": ["implemented", "working"]
  }
]
```

### Section 5: Documentation Coverage

Scans a source directory for files, then checks whether each file
is mentioned in a documentation file (e.g. ARCHITECTURE.md).

```json
"docCoverage": [
  {
    "name": "ARCHITECTURE.md coverage",
    "sourceDir": "src/lib",
    "glob": "*.js",
    "docFile": "ARCHITECTURE.md",
    "requiredMention": true,
    "severity": "warn",
    "excludePatterns": ["index.js", "*.test.js"]
  }
]
```

## sync-task-state.sh

Automatically updates task statuses in cascade-state.json (or any JSON
state file) based on the existence of implementation files.

Each task should have an `implementationFiles` array listing files that
prove the task is implemented. If ALL files exist, the task status is
automatically changed from "pending" to "implemented".

```bash
bash scripts/sync-task-state.sh                  # default: cascade-state.json
bash scripts/sync-task-state.sh my-state.json    # custom file
bash scripts/sync-task-state.sh --dry-run        # preview without writing
```

## Compatibility with Cascade-guard

When both modules are installed:

| Aspect | AHG | Cascade-guard |
|--------|-----|---------------|
| Rule namespace | Rule 1-10 | C-1 to C-9 |
| AGENT_RULES.md markers | `<!-- AHG:START/END -->` | `<!-- CASCADE-GUARD:START/END -->` |
| State file | worklog.md | cascade-state.json |
| Pre-commit checks | worklog freshness | cascade-state.json validity |
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

## check-hooks-integrity.sh

Detects tampering with git hooks and key configuration files.
Uses SHA256 fingerprints to verify hooks have not been replaced or modified.

```bash
bash scripts/check-hooks-integrity.sh --snapshot  # save fingerprints
bash scripts/check-hooks-integrity.sh --check     # verify integrity
bash scripts/check-hooks-integrity.sh --repair    # re-install from module
```

Automatically creates a snapshot during setup.sh.
The pre-commit hook also runs a quick self-check (detects core.hooksPath bypass).

## Triggers

Activate when:
- Session starts (auto)
- User mentions: anti-hallucination, guard, rules, discipline
- Agent seems to loop or stall
- worklog not updated for extended period
- Documentation drift detected by verify-docs

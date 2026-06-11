# Anti-Hallucination Guard v1.1

> Auto-activate on session start. Setup.sh merges rules into AGENT_RULES.md with markers.
> Compatible with cascade-guard: Rule 1-6 (AHG) + Rule C-1..C-9 (Cascade) coexist.

## Purpose

Prevent AI agent from hallucinating, looping, or faking activity
in Z.ai sandbox environments.

## Activation

This skill MUST auto-activate at the beginning of every session.
Agent must read AGENT_RULES.md and worklog.md before any work.

## Setup Procedure

Execute these steps IN ORDER before any other work:

### Step 1: Merge AHG rules into AGENT_RULES.md

Setup.sh uses marker-based merging (`<!-- AHG:START -->` / `<!-- AHG:END -->`).
If cascade-guard is also installed, its block (`<!-- CASCADE-GUARD:START -->` / `<!-- CASCADE-GUARD:END -->`)
will coexist without conflict.

AHG rules (Rule 1-6): worklog, read-before-write, no-loops, honest reporting, work structure.
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

### Step 6: Cascade-guard integration (auto-detect)

If cascade-guard is detected (via .gitmodules or find), setup.sh automatically:
- Adds cascade-state.json freshness checks to pre-commit hook
- Confirms rule namespacing: Rule 1-6 (AHG) + C-1..C-9 (Cascade)
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

## Compatibility with Cascade-guard

When both modules are installed:

| Aspect | AHG | Cascade-guard |
|--------|-----|---------------|
| Rule namespace | Rule 1-6 | C-1 to C-9 |
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

## Triggers

Activate when:
- Session starts (auto)
- User mentions: anti-hallucination, guard, rules, discipline
- Agent seems to loop or stall
- worklog not updated for extended period

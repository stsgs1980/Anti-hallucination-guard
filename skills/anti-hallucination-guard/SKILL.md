# Anti-Hallucination Guard v1.0

> Auto-activate on session start. Копируется setup.sh в skills/ проекта.

## Purpose

Prevent AI agent from hallucinating, looping, or faking activity
in Z.ai sandbox environments.

## Activation

This skill MUST auto-activate at the beginning of every session.
Agent must read AGENT_RULES.md and worklog.md before any work.

## Setup Procedure

Execute these steps IN ORDER before any other work:

### Step 1: Create AGENT_RULES.md

Create /AGENT_RULES.md in project root with mandatory rules:
- READ BEFORE WRITE: never write a file without reading it first
- worklog after EVERY file change
- git commit after each logical block
- STOP after 3 failed attempts on same step
- Honest reporting: no "done" unless verified

### Step 2: Create worklog.md

Create /worklog.md in project root if not exists.

### Step 3: Setup pre-commit hook

Create .git/hooks/pre-commit from .git-hooks/pre-commit:
- Check worklog.md exists
- Check worklog.md updated within 10 minutes
- Check worklog.md has proper block format
- Block commit if any check fails
- chmod +x the hook

### Step 4: Initialize git (if needed)

```bash
git init 2>/dev/null
git add -A
git commit -m "init: anti-hallucination guard setup"
```

### Step 5: Verify

- AGENT_RULES.md exists: YES
- worklog.md exists: YES
- pre-commit hook exists and executable: YES
- git initialized: YES

## Runtime Rules

During work execution, these rules are NON-NEGOTIABLE:

1. BEFORE any file write: Read the file first
2. AFTER any file write: Update worklog.md
3. AFTER logical block: git commit (blocked if worklog stale)
4. ON 3rd repeat: STOP and notify user
5. NEVER claim completion without verification

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

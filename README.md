# anti-hallucination-guard

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Version 1.4](https://img.shields.io/badge/v1.4-2026--06--12-green.svg)]()
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-verify--docs-3178C6.svg?logo=typescript&logoColor=white)]()
[![Git Hooks](https://img.shields.io/badge/Git-Hooks-FF6600.svg?logo=git&logoColor=white)]()
[![Idempotent](https://img.shields.io/badge/Setup-Idempotent-success.svg)]()

Git module for preventing "illusion of activity" by AI agents in Z.ai sandbox environments.
Includes built-in **verify-docs** -- 5-section automatic documentation consistency checker.

## What it does

Physically enforces that the agent:
- Logs every action in worklog
- Reads files before modifying them
- Commits per logical block
- Stops when looping
- Reports results honestly
- Scans project structure at session start (drift prevention)
- Keeps documentation in sync with code

Plus automatic documentation verification:
- Numbers in README are cross-checked with actual code
- Version numbers are synced across all docs (single source of truth)
- Stub markers in docs are verified against existing code
- Documentation coverage is checked (new modules must be documented)
- Push is blocked on mismatch
- Supports cross-repo consistency checks

## Installation

### Option 1: Git submodule (recommended)

```bash
cd /path/to/your/project
git submodule add https://github.com/stsgs1980/Anti-hallucination-guard.git anti-hallucination-guard
git submodule update --init --recursive
bash anti-hallucination-guard/setup.sh
git add .gitmodules anti-hallucination-guard AGENT_RULES.md worklog.md scripts/
git commit -m "feat: add anti-hallucination-guard"
```

Updating to latest version:
```bash
bash anti-hallucination-guard/update.sh
# update.sh does: git pull + setup.sh + reminder to commit
# After update.sh, commit the submodule pointer in your project:
git add anti-hallucination-guard && git commit -m "update: anti-hallucination-guard"
```

> **Why commit the submodule pointer?** A git submodule is just a pointer to a specific commit.
> When you update the submodule (pull new code), your project still points to the old version
> until you `git add` + `git commit` the new pointer. Without this step, other developers
> cloning your project will get the old version of anti-hallucination-guard.

After `git clone` of a project using the guard:
```bash
git submodule update --init --recursive
bash anti-hallucination-guard/setup.sh
```

### Option 2: Simple copy

```bash
cp -r /path/to/anti-hallucination-guard /path/to/your/project/
cd /path/to/your/project
bash anti-hallucination-guard/setup.sh
```

## What setup.sh installs

| File | Purpose |
|---|---|
| `AGENT_RULES.md` | Agent work rules with 9 rules (copied to project root) |
| `worklog.md` | Mandatory work log (copied to project root) |
| `.git/hooks/pre-commit` | Blocks commit without updated worklog + verify-docs |
| `.git/hooks/pre-push` | Blocks push with foreign files |
| `scripts/check-agent.sh` | Activity monitor (cron or manual) |
| `scripts/audit.sh` | Post-session audit with score |
| `scripts/validate.sh` | Module purity checker |
| `scripts/sync-task-state.sh` | Auto-sync task statuses based on implementation files |
| `scripts/check-hooks-integrity.sh` | Detect hook tampering / bypass attempts |
| `tools/verify-docs/` | 5-section doc consistency checker (requires bun) |

## verify-docs (built-in) -- 5 Sections

Automatically installed if `bun` is available on the system.
Runs 5 independent verification sections:

| Section | What it checks | Config key |
|---------|---------------|------------|
| **1. README vs Code** | Numbers in docs match actual counts | `checks` |
| **2. Cross-repo** | Values consistent across sibling repos | `crossRepo` |
| **3. Version sync** | Version matches across all docs (single source of truth) | `versionSync` |
| **4. Feature status** | Stub markers don't contradict existing code | `featureStatus` |
| **5. Doc coverage** | Code files are mentioned in documentation | `docCoverage` |

### Section 1: README vs Code

Cross-checks numbers in README against actual code:

```json
{
  "readme": "README.md",
  "checks": [
    {
      "name": "Components",
      "source": "glob:src/components/**/*.tsx",
      "readmePattern": "(\\d+) components"
    },
    {
      "name": "Models",
      "source": "file:prisma/schema.prisma",
      "countPattern": "^model \\w+",
      "readmePattern": "(\\d+) models"
    }
  ]
}
```

Data sources: `file:`, `glob:`, `git:HEAD`, `custom:` (plugins).

### Section 3: Version Synchronization

Prevents the common problem where README, ARCHITECTURE, and other docs
each carry their own version that diverges over time. Define one source
of truth and list targets that must match:

```json
"versionSync": {
  "source": "file:package.json",
  "extractPattern": "\"version\":\\s*\"([\\d.]+)\"",
  "targets": [
    { "file": "README.md", "pattern": "v([\\d.]+)" },
    { "file": "ARCHITECTURE.md", "pattern": "version:\\s*([\\d.]+)" },
    { "file": "TASK-CASCADE.md", "pattern": "version:\\s*([\\d.]+)" }
  ]
}
```

### Section 4: Feature Status (Stub Detection)

Detects features documented as "stubs / not implemented / TODO"
but which actually have implementation files in the codebase:

```json
"featureStatus": [
  {
    "name": "Vacancy detail parser",
    "stubPatterns": ["stub", "TODO", "not implemented"],
    "docFile": "README.md",
    "contextPattern": "vacancy.detail",
    "implementationFiles": ["src/parsers/vacancy-detail.js"],
    "implementedPatterns": ["implemented", "working"]
  }
]
```

Checks:
- Doc says stub + code exists -> **ERR** (stale stub marker)
- Doc says implemented + no code -> **ERR** (false claim)
- Doc says stub + no code -> **OK** (honest stub)

### Section 5: Documentation Coverage

Scans a source directory for files, then checks whether each file
is mentioned in a documentation file:

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

### Running verify-docs

Create `verify-docs.json` in your project root and run:
```bash
bun run tools/verify-docs/src/cli.ts
```

Or auto-generate a config:
```bash
bun run tools/verify-docs/src/init.ts
```

## sync-task-state.sh

Automatically updates task statuses in JSON state files (cascade-state.json
or any compatible format) based on the existence of implementation files.

Each task should have an `implementationFiles` array listing files that
prove the task is implemented. If ALL files exist, the task status is
automatically changed from "pending" to "implemented".

```bash
bash scripts/sync-task-state.sh                  # default: cascade-state.json
bash scripts/sync-task-state.sh my-state.json    # custom file
bash scripts/sync-task-state.sh --dry-run        # preview without writing
```

Example task structure in state file:
```json
{
  "id": "F1.1",
  "title": "Feature name",
  "status": "pending",
  "implementationFiles": ["src/lib/feature.js", "src/parsers/feature.js"]
}
```

## AGENT_RULES.md (9 Rules)

| Rule | Purpose |
|------|---------|
| Rule 1 | worklog -- BEFORE and AFTER every action |
| Rule 2 | Read before write |
| Rule 3 | One logical block -- one commit |
| Rule 4 | No loops (stop after 3rd attempt) |
| Rule 5 | Honest reporting |
| Rule 6 | Work structure |
| Rule 7 | Sandbox verification (no fake setup) |
| Rule 8 | **Session Start Protocol** (drift prevention) |
| Rule 9 | **Documentation sync** (no code without docs) |
| Rule 10 | **Integrity protection** (no self-sabotage) |

### Rule 8: Session Start Protocol

Before ANY work in a new session, the agent must:
1. Scan project structure (list source files)
2. Read version source of truth
3. Compare actual structure with documentation
4. If drift > 3 items: UPDATE DOCUMENTATION FIRST, then do the task
5. Record scan results in worklog.md

### Rule 9: Documentation Sync

When changing the codebase:
1. New file -> add to ARCHITECTURE.md + update file counts
2. New functionality -> remove from "stubs" section
3. Deleted/renamed file -> update all references
4. Version change -> update ONLY the source of truth

### Rule 10: Integrity Protection

Agents MUST NOT disable, bypass, or weaken the anti-hallucination mechanisms:

- `git commit --no-verify` is forbidden
- Modifying `.git/hooks/` to remove checks is forbidden
- Setting `core.hooksPath` to bypass hooks is forbidden
- Removing rules from AGENT_RULES.md is forbidden
- Removing checks from verify-docs.json to avoid failures is forbidden

Detection: `check-hooks-integrity.sh` fingerprints hooks and configs.
CI pipeline runs verify-docs independently (cannot be bypassed locally).

## check-hooks-integrity.sh

Detects tampering with git hooks and key configuration files.
Uses SHA256 fingerprints to verify that hooks have not been replaced
or modified by an AI agent trying to bypass safeguards.

```bash
bash scripts/check-hooks-integrity.sh --snapshot  # save fingerprints
bash scripts/check-hooks-integrity.sh --check     # verify integrity
bash scripts/check-hooks-integrity.sh --repair    # re-install from module
```

Automatically creates a snapshot during `setup.sh` and after hook installation.
The pre-commit hook also runs a quick self-check.

## Usage

### At the start of each session

```
Before starting work, read /AGENT_RULES.md and /worklog.md.
(Rule 8: also scan project structure and check for drift)
```

### During work

- Before modifying a file -> Read tool
- After modifying -> update worklog.md
- After a logical block -> git commit (blocked without worklog)
- On 3rd failed attempt -> STOP, write in chat
- New code without doc update -> Rule 9 violation

### After session ends

```bash
bash scripts/audit.sh              # work quality score
bash scripts/sync-task-state.sh    # auto-update task statuses
git push                            # persist results
```

## For maintainers: adding files to the module

When you add a new file to the module, make sure it is allowed by both:

1. **`.gitignore`** -- must NOT be ignored (no matching pattern)
2. **`scripts/validate.sh`** -- must be in the `ALLOWED` array

The `.gitignore` uses a whitelist-negative pattern for `skills/` to prevent sandbox artifacts from leaking in:

```
# Ignore everything in skills/ ...
skills/*
# ... except our own skill
!skills/anti-hallucination-guard/
!skills/anti-hallucination-guard/**
```

This means `git add -A` is safe to use inside the module -- it will only pick up module files, not hundreds of sandbox skill files that may exist on disk.

**Workflow for adding a new script:**

```bash
# 1. Create the file
touch scripts/new-check.sh

# 2. Add it to validate.sh ALLOWED array
#    "scripts/new-check.sh"

# 3. Verify it is picked up (not ignored)
git add -A
git diff --cached --name-only   # should show only your new file
```

## Removal

```bash
rm AGENT_RULES.md worklog.md verify-docs.json
rm .git/hooks/pre-commit .git/hooks/pre-push
rm -r scripts/ tools/verify-docs/
rm -r anti-hallucination-guard/
```

## Module structure

```
anti-hallucination-guard/
  setup.sh                          -- project installer (thin orchestrator)
  setup/                            -- modular setup steps
    _lib.sh                        -- shared variables and logging functions
    01-deploy-agent-rules.sh       -- AGENT_RULES.md marker merge
    02-create-worklog.sh           -- worklog.md initialization
    03-install-pre-commit-hook.sh  -- worklog freshness check
    04-install-pre-push-hook.sh    -- module purity protection
    05-deploy-monitoring-scripts.sh -- check-agent, audit, validate, sync-task-state
    06-deploy-skill.sh             -- Z.ai skill definition
    07-install-verify-docs.sh       -- README checker (optional, needs bun)
    08-integrate-cascade-guard.sh  -- cascade-state.json freshness
    09-git-staging.sh              -- git add installed files
  AGENT_RULES.md                    -- agent rules template (9 rules)
  .git-hooks/
    pre-commit                      -- pre-commit hook (worklog + verify-docs)
    pre-push                        -- pre-push hook (foreign file protection)
  scripts/
    check-agent.sh                  -- activity monitor
    audit.sh                        -- post-session audit
    validate.sh                     -- module purity checker
    branch-protect.sh                -- branch protection (orchestrator)
    branch-protect-lib.sh           -- branch protection (config + helpers)
    sync-task-state.sh              -- auto-sync task statuses
    check-hooks-integrity.sh        -- detect hook tampering / bypass
  tools/
    verify-docs/                    -- built-in verify-docs (5 sections)
      src/
        types.ts                   -- type definitions
        resolvers.ts               -- source resolver registry
        resolve-check.ts           -- single check resolver
        verify-section1.ts         -- README vs Code verification
        verify-section2.ts         -- cross-repo consistency
        verify-section3.ts         -- version synchronization
        verify-section4.ts         -- feature status (stub detection)
        verify-section5.ts         -- documentation coverage
        engine.ts                  -- verification engine (orchestrator)
        cli.ts                     -- CLI entry point
        init.ts                    -- auto config generator
      templates/
        pre-push                    -- hook template for verify-docs
        verify.yml                  -- GitHub Actions workflow
        install-hooks.ts            -- hook installer
      examples/
        simple/                     -- basic config
        monorepo/                   -- config with plugins and cross-repo
      package.json
  skills/
    anti-hallucination-guard/
      SKILL.md                      -- Z.ai skill definition
  .gitignore
  README.md                         -- this file
```

---

v1.4 | 2026-06-12 | MIT

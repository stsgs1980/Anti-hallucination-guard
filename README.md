# anti-hallucination-guard

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Version 2.0.0](https://img.shields.io/badge/v2.0.0-2026--06--13-green.svg)]()
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-verify--docs-3178C6.svg?logo=typescript&logoColor=white)]()
[![Git Hooks](https://img.shields.io/badge/Git-Hooks-FF6600.svg?logo=git&logoColor=white)]()
[![Idempotent](https://img.shields.io/badge/Setup-Idempotent-success.svg)]()

Git module for preventing "illusion of activity" by AI agents in Z.ai sandbox environments.
Includes built-in **verify-docs** -- 5-section automatic documentation consistency checker
with **auto-discover** (no config required), **atomic version bump**, and **baseline tracking**.

## What it does

Physically enforces that the agent:
- Logs every action in worklog
- Reads files before modifying them
- Commits per logical block
- Stops when looping
- Reports results honestly
- Scans project structure at session start (drift prevention)
- Keeps documentation in sync with code
- Never disables or bypasses anti-hallucination mechanisms
- Keeps files under 250 lines (anti-monolith)

Plus automatic documentation verification (three modes):
- **DISCOVER**: auto-scan project without config (finds versions, CHANGELOG, coverage gaps)
- **VERIFY**: cross-check docs against config (5 sections)
- **GENERATE**: atomic version bump + CHANGELOG entry via `ahg bump`

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
| `AGENT_RULES.md` | Agent work rules (14 rules, copied to project root) |
| `worklog.md` | Mandatory work log (copied to project root) |
| `.git/hooks/pre-commit` | Blocks commit without updated worklog + verify-docs + auto-discover fallback |
| `.git/hooks/pre-push` | Blocks push with foreign files |
| `scripts/ahg.sh` | Unified CLI for all AHG commands |
| `scripts/check-agent.sh` | Activity monitor (cron or manual) |
| `scripts/audit.sh` | Post-session audit with score |
| `scripts/validate.sh` | Module purity checker + Unicode policy enforcement |
| `scripts/sync-task-state.sh` | Auto-sync task statuses based on implementation files |
| `scripts/check-hooks-snapshot.sh` | Create integrity snapshot of hooks/configs |
| `scripts/check-hooks-verify.sh` | Verify hooks/configs against snapshot (anti-tampering) |
| `tools/verify-docs/` | 5-section doc consistency checker with auto-discover (requires bun) |

## Unified CLI: ahg.sh

All AHG commands are accessible through a single entry point:

```bash
bash scripts/ahg.sh <command> [args]
```

| Command | Description |
|---------|-------------|
| `verify [--ci]` | Verify docs against config |
| `discover` | Auto-scan project (no config needed) |
| `bump <version>` | Update version in all files atomically |
| `bump <version> --dry-run` | Preview bump without writing |
| `init` | Generate verify-docs.json from discover |
| `baseline` | Create .ahg-baseline.json |
| `baseline --check` | Check current files vs baseline |
| `snapshot` | Manage hook integrity snapshots |
| `integrity [--repair]` | Check or repair hook integrity |
| `sync [--dry-run]` | Auto-sync task statuses |
| `audit` | Post-session audit |
| `validate` | Repository purity + Unicode policy check |

The CLI wrapper fixes CWD issues by always `cd`ing to the project root before executing any command. This makes it safe to call from any directory.

## Three-mode architecture: DISCOVER / GENERATE / VERIFY

AHG v2.0 operates in three modes, solving the root cause of documentation drift
(where v1.0 was reactive-only and "0 errors" actually meant "0 checks"):

### DISCOVER mode (proactive -- no config required)

Auto-scans the project and reports issues without needing verify-docs.json:
- Finds all files containing version numbers and checks if they are in sync
- Finds CHANGELOG files and verifies freshness (latest entry matches current version)
- Scans source directories for code files not mentioned in documentation
- Compares current file list against baseline (detects deleted files)

```bash
bash scripts/ahg.sh discover
```

Runs automatically as a fallback in the pre-commit hook when verify-docs.json does not exist.

### GENERATE mode (atomic changes)

Updates versions and generates configuration atomically:
- `ahg bump X.Y.Z` -- updates version in ALL discovered files at once
- `ahg init` -- generates verify-docs.json from auto-discover results
- `ahg baseline` -- creates .ahg-baseline.json for deletion tracking

```bash
bash scripts/ahg.sh bump 2.1.0          # update all version files + CHANGELOG
bash scripts/ahg.sh bump 2.1.0 --dry-run  # preview without writing
bash scripts/ahg.sh init                  # generate verify-docs.json
bash scripts/ahg.sh baseline              # create file baseline
```

### VERIFY mode (existing checks)

Cross-checks documentation against the codebase using verify-docs.json config:

```bash
bash scripts/ahg.sh verify              # full verification
bash scripts/ahg.sh verify --ci         # CI mode (skip cross-repo)
```

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

Or use `ahg bump` to update ALL version files atomically without manual config.

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

## Baseline tracking (.ahg-baseline.json)

Records which files exist at the time of setup. On subsequent runs,
deleted files are detected by comparing current state against the baseline.
This prevents the "silent deletion" problem where files disappear unnoticed.

```bash
bash scripts/ahg.sh baseline           # create baseline
bash scripts/ahg.sh baseline --check   # check for deleted files
```

## sync-task-state.sh

Automatically updates task statuses in JSON state files (cascade-state.json
or any compatible format) based on the existence of implementation files.

Each task should have an `implementationFiles` array listing files that
prove the task is implemented. If ALL files exist, the task status is
automatically changed from "pending" to "implemented".

Integrated into the pre-commit hook (Phase 2.5): runs automatically
before every commit when cascade-state.json exists.

```bash
bash scripts/ahg.sh sync               # default: cascade-state.json
bash scripts/ahg.sh sync --dry-run     # preview without writing
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

## AGENT_RULES.md (14 Rules)

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
| Rule 11 | **Anti-monolith** (no file over 250 lines) |
| Rule 12 | **ahg bump** (atomic version updates, no manual edits) |
| Rule 13 | **Pre-commit checklist** (mandatory before every commit) |
| Rule 14 | **UNICODE_POLICY** (ASCII-only output, no emoji, no Unicode graphics) |

### Rule 8: Session Start Protocol

Before ANY work in a new session, the agent must:
1. Scan project structure (list source files)
2. Read version source of truth
3. Compare actual structure with documentation
4. If drift > 3 items: UPDATE DOCUMENTATION FIRST, then do the task
5. Record scan results in worklog.md

### Rule 10: Integrity Protection

Agents MUST NOT disable, bypass, or weaken the anti-hallucination mechanisms:

- `git commit --no-verify` is forbidden
- Modifying `.git/hooks/` to remove checks is forbidden
- Setting `core.hooksPath` to bypass hooks is forbidden
- Removing rules from AGENT_RULES.md is forbidden
- Removing checks from verify-docs.json to avoid failures is forbidden

Detection: `check-hooks-verify.sh` fingerprints hooks and configs.
CI pipeline runs verify-docs independently (cannot be bypassed locally).

### Rule 11: Anti-monolith

Every file MUST stay under 250 lines. When a file crosses this threshold,
the agent MUST stop writing, split the file, and continue with smaller modules.
Functions must stay under 50 lines. Auto-activation: do not wait to be asked.

### Rule 12: ahg bump

When changing the project version, use `bash scripts/ahg.sh bump X.Y.Z` instead
of manual edits. This command auto-discovers ALL files containing version numbers
and updates them atomically. Manual updates cause version drift.

### Rule 14: UNICODE_POLICY

All AHG output must comply with No-Unicode Policy v2.1. No emoji, no Unicode
pictograms, no box-drawing characters. Status markers: [OK], [ERR], [WARN], [INFO].
Section dividers in comments: `// --` or `# --` (not Unicode dashes).

## check-hooks integrity system

Detects tampering with git hooks and key configuration files.
Split into two scripts for anti-monolith compliance:

```bash
bash scripts/ahg.sh snapshot              # create integrity snapshot
bash scripts/ahg.sh integrity             # verify against snapshot
bash scripts/ahg.sh integrity --repair    # re-install from module
```

- `check-hooks-snapshot.sh` -- creates SHA256 fingerprints of hooks, AGENT_RULES.md, verify-docs.json
- `check-hooks-verify.sh` -- compares current state against snapshot, detects tampering, offers repair

Automatically creates a snapshot during `setup.sh` and after hook installation.
The pre-commit hook also runs a quick self-check (detects core.hooksPath bypass).

## Pre-commit hook phases

The pre-commit hook runs in multiple phases:

| Phase | Check | Blocking |
|-------|-------|----------|
| 1 | Integrity check (core.hooksPath, self-check) | Yes |
| 2 | Worklog checks (exists, fresh <10min, >50 bytes, >2 blocks) | Yes |
| 2.5 | sync-task-state (cascade-state auto-sync) | No (warn) |
| 3 | verify-docs (if verify-docs.json exists) | Yes |
| 3.5 | auto-discover fallback (if no config) | Yes |

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
- Version change -> use `ahg bump` (Rule 12)

### After session ends

```bash
bash scripts/ahg.sh audit              # work quality score
bash scripts/ahg.sh sync               # auto-update task statuses
git push                                # persist results
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
rm AGENT_RULES.md worklog.md verify-docs.json .ahg-baseline.json
rm .git/hooks/pre-commit .git/hooks/pre-push
rm -r scripts/ tools/verify-docs/
rm -r anti-hallucination-guard/
```

## Module structure

```
anti-hallucination-guard/
  setup.sh                          -- project installer (thin orchestrator)
  update.sh                         -- pull + reinstall + commit reminder
  setup/                            -- modular setup steps
    _lib.sh                        -- shared variables and logging functions
    01-deploy-agent-rules.sh       -- AGENT_RULES.md marker merge
    02-create-worklog.sh           -- worklog.md initialization
    03-install-pre-commit-hook.sh  -- worklog + verify-docs + discover
    04-install-pre-push-hook.sh    -- module purity protection
    05-deploy-monitoring-scripts.sh -- check-agent, audit, validate, sync, ahg
    06-deploy-skill.sh             -- Z.ai skill definition
    07-install-verify-docs.sh       -- README checker (optional, needs bun)
    08-integrate-cascade-guard.sh  -- cascade-state.json freshness
    09-git-staging.sh              -- git add installed files
  AGENT_RULES.md                    -- agent rules template (14 rules)
  .git-hooks/
    pre-commit                      -- pre-commit hook (5 phases)
    pre-push                        -- pre-push hook (foreign file protection)
  scripts/
    ahg.sh                          -- unified CLI entry point
    check-agent.sh                  -- activity monitor
    audit.sh                        -- post-session audit
    validate.sh                     -- module purity + Unicode policy checker
    branch-protect.sh               -- branch protection (orchestrator)
    branch-protect-lib.sh           -- branch protection (config + helpers)
    sync-task-state.sh              -- auto-sync task statuses
    check-hooks-lib.sh              -- shared functions for integrity checks
    check-hooks-snapshot.sh         -- create integrity snapshot
    check-hooks-verify.sh           -- verify against snapshot (anti-tampering)
  tools/
    verify-docs/                    -- built-in verify-docs (5 sections + discover + bump)
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
        cli.ts                     -- CLI entry point (5 modes)
        init.ts                    -- quick config generator
        discover.ts                -- auto-discover orchestrator
        discover-versions.ts       -- find version files automatically
        discover-changelog.ts      -- find and verify CHANGELOG freshness
        discover-coverage.ts       -- find doc coverage gaps
        discover-baseline.ts       -- create/check file baselines
        bump.ts                    -- atomic version bump
      templates/
        pre-push                   -- hook template for verify-docs
        verify.yml                 -- GitHub Actions workflow
        install-hooks.ts           -- hook installer
      examples/
        simple/                    -- basic config
        monorepo/                  -- config with plugins and cross-repo
      package.json
  skills/
    anti-hallucination-guard/
      SKILL.md                      -- Z.ai skill definition
  .gitignore
  README.md                         -- this file
```

---

v2.0.0 | 2026-06-13 | MIT

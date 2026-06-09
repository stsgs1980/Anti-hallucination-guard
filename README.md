# anti-hallucination-guard

Git module for preventing "illusion of activity" by AI agents in Z.ai sandbox environments.
Includes built-in **verify-docs** -- automatic README vs code consistency checker.

## What it does

Physically enforces that the agent:
- Logs every action in worklog
- Reads files before modifying them
- Commits per logical block
- Stops when looping
- Reports results honestly

Plus automatic documentation verification:
- Numbers in README are cross-checked with actual code
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
cd anti-hallucination-guard && git pull origin main
cd ..
bash anti-hallucination-guard/setup.sh
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
| `AGENT_RULES.md` | Agent work rules (copied to project root) |
| `worklog.md` | Mandatory work log (copied to project root) |
| `.git/hooks/pre-commit` | Blocks commit without updated worklog + verify-docs |
| `.git/hooks/pre-push` | Blocks push with foreign files |
| `scripts/check-agent.sh` | Activity monitor (cron or manual) |
| `scripts/audit.sh` | Post-session audit with score |
| `scripts/validate.sh` | Module purity checker |
| `tools/verify-docs/` | README number checker (requires bun) |

## verify-docs (built-in)

Automatically installed if `bun` is available on the system.
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

Create `verify-docs.json` in your project root and run:
```bash
bun run tools/verify-docs/src/cli.ts
```

Or auto-generate a config:
```bash
bun run tools/verify-docs/src/init.ts
```

Data sources: `file:`, `glob:`, `git:HEAD`, `custom:` (plugins).
Details: see the verify-docs source in `tools/verify-docs/`.

## Usage

### At the start of each session

```
Before starting work, read /AGENT_RULES.md and /worklog.md.
```

### During work

- Before modifying a file -> Read tool
- After modifying -> update worklog.md
- After a logical block -> git commit (blocked without worklog)
- On 3rd failed attempt -> STOP, write in chat

### After session ends

```bash
bash scripts/audit.sh   # work quality score
git push                 # persist results
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
  setup.sh                          -- project installer
  AGENT_RULES.md                    -- agent rules template
  .git-hooks/
    pre-commit                      -- pre-commit hook (worklog + verify-docs)
    pre-push                        -- pre-push hook (foreign file protection)
  scripts/
    check-agent.sh                  -- activity monitor
    audit.sh                        -- post-session audit
    validate.sh                     -- module purity checker
  tools/
    verify-docs/                    -- built-in verify-docs
      src/
        engine.ts                   -- verification engine
        cli.ts                      -- CLI entry point
        init.ts                     -- auto config generator
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

v1.1 | 2026-06-09 | MIT

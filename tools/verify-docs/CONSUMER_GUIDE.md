# verify-docs: Guide for Consumer Projects

This guide explains how to configure `verify-docs.json` in projects that use
Anti-Hallucination-Guard as a submodule. The default `--init` generates a
minimal config that covers `README.md` only. Real projects often have
additional documentation (WORKFLOW.md, ARCHITECTURE.md, CHANGELOG.md, wiki
pages) that also contains numbers derived from code. This guide shows how to
protect those files from drifting.

## Quick Start

```bash
# Auto-generate a starter config (README.md only)
bun run anti-hallucination-guard/tools/verify-docs/src/cli.ts --init

# Edit the generated verify-docs.json to add your project's checks
```

## Why README.md Is Not Enough

`verify-docs` uses the `"readme"` field as the primary document for Section 1
checks (code vs docs). If your project has WORKFLOW.md, ARCHITECTURE.md, or
other docs with counts, versions, or feature lists derived from code, those
files are **not protected** by the default config. When someone adds a wiki
page, an ESLint rule, or a model, the pre-commit hook will only catch README
drift — not drift in other docs.

The fix is not to change the tool — it already supports multi-doc coverage
through `docCoverage`, `versionSync`, and `featureStatus`. You just need to
configure it.

---

## Section 1: Code Counts vs Docs

**Purpose:** Count items in code (glob, file, git) and compare with a number
in the documentation.

### Basic: Count shell scripts, compare with README

```json
{
  "name": "Shell scripts",
  "source": "glob:scripts/*.sh",
  "readmePattern": "(\\d+) shell scripts"
}
```

- `glob:scripts/*.sh` counts all `.sh` files in `scripts/`
- `(\\d+) shell scripts` extracts the number from README
- If they don't match → error

### Info-only: Just show the count, don't enforce

```json
{
  "name": "Shell scripts",
  "source": "glob:scripts/*.sh",
  "readmePattern": null,
  "infoOnly": true
}
```

Useful during setup — you see the real counts without blocking commits.

### Count with regex pattern inside a file

```json
{
  "name": "ESLint rules",
  "source": "file:packages/eslint-plugin/src/index.ts",
  "countPattern": "createRule",
  "readmePattern": "(\\d+) custom rules"
}
```

- Counts lines matching `createRule` in the source file
- Compares with the number in README

### Count models in Prisma schema

```json
{
  "name": "Prisma models",
  "source": "file:prisma/schema.prisma",
  "countPattern": "^model \\w+",
  "readmePattern": "(\\d+) database models"
}
```

### Git commits with tolerance

```json
{
  "name": "Commits",
  "source": "git:HEAD",
  "readmePattern": "(\\d+) commits",
  "tolerance": 5
}
```

- `tolerance: 5` allows up to 5 difference (commits change frequently)

### Exclude files from glob

```json
{
  "name": "Components",
  "source": "glob:src/components/**/*.tsx",
  "exclude": ["test", "spec", ".stories"],
  "readmePattern": "(\\d+) components"
}
```

---

## Section 3: Version Synchronization

**Purpose:** One source of truth for the version number; all other files must
match.

### Simple: README → package.json, lock file

```json
{
  "versionSync": {
    "source": "file:package.json",
    "extractPattern": "\"version\"\\s*:\\s*\"([\\d.]+)\"",
    "targets": [
      { "file": "README.md", "pattern": "v([\\d.]+)" },
      { "file": "package-lock.json", "pattern": "\"version\"\\s*:\\s*\"([\\d.]+)\"" }
    ]
  }
}
```

### Multi-file: Sync version across 5 files

```json
{
  "versionSync": {
    "source": "file:README.md",
    "extractPattern": "v([\\d.]+)",
    "targets": [
      { "file": "package.json", "pattern": "\"version\"\\s*:\\s*\"([\\d.]+)\"" },
      { "file": "registry.json", "pattern": "\"version\"\\s*:\\s*\"([\\d.]+)\"" },
      { "file": "CHANGELOG.md", "pattern": "## \\[([\\d.]+)\\]" },
      { "file": "website/index.html", "pattern": "VERSION\\s*=\\s*['\"]([\\d.]+)['\"]" }
    ]
  }
}
```

---

## Section 5: Documentation Coverage

**Purpose:** Verify that code files are mentioned in documentation. This is the
key section for protecting non-README docs.

### Single doc file (README)

```json
{
  "docCoverage": [
    {
      "name": "scripts/ in docs",
      "sourceDir": "scripts",
      "docFile": "README.md",
      "requiredMention": false,
      "severity": "warn"
    }
  ]
}
```

### Multiple doc files (README + WORKFLOW + ARCHITECTURE)

This is how you protect WORKFLOW.md and other docs from going stale:

```json
{
  "docCoverage": [
    {
      "name": "scripts/ in README",
      "sourceDir": "scripts",
      "docFile": "README.md",
      "requiredMention": false,
      "severity": "warn"
    },
    {
      "name": "features/ in WORKFLOW",
      "sourceDir": "src/features",
      "docFile": "WORKFLOW.md",
      "requiredMention": false,
      "severity": "warn"
    },
    {
      "name": "packages/ in ARCHITECTURE",
      "sourceDir": "packages",
      "glob": "package.json",
      "docFile": "ARCHITECTURE.md",
      "requiredMention": true,
      "severity": "err",
      "excludePatterns": ["test-utils", "eslint-config"]
    }
  ]
}
```

### How docCoverage prevents drift

When someone adds a new file to `src/features/` but doesn't mention it in
WORKFLOW.md, the next commit will show:

```
[ERR] Doc coverage: 14/16 files mentioned (88%) in WORKFLOW.md
      MISSING: new-feature.tsx, another-feature.tsx
```

With `severity: "err"` this blocks the commit. With `severity: "warn"` it
prints a warning but allows the commit.

---

## Section 4: Feature Status (Stub Detection)

**Purpose:** Detect when documentation says a feature is a "stub" or "TODO"
but the code actually implements it.

```json
{
  "featureStatus": [
    {
      "name": "Wiki pages",
      "stubPatterns": ["stub", "TODO", "not implemented"],
      "docFile": "WORKFLOW.md",
      "contextPattern": "wiki",
      "implementationFiles": ["src/features/wiki/pages/index.tsx"],
      "implementedPatterns": ["implemented", "working", "done"]
    },
    {
      "name": "Payment processing",
      "stubPatterns": ["stub", "planned"],
      "docFile": "ARCHITECTURE.md",
      "implementationFiles": ["src/services/payment.ts"],
      "implementedPatterns": ["done", "live"]
    }
  ]
}
```

This catches the common pattern where docs say "wiki — stub" but someone
already built the wiki feature and forgot to update the docs.

---

## Complete Example: Multi-Doc Project

Here is a full `verify-docs.json` for a project with README, WORKFLOW, and
ARCHITECTURE docs:

```json
{
  "readme": "README.md",
  "checks": [
    {
      "name": "Routes",
      "source": "glob:src/app/**/page.tsx",
      "readmePattern": "(\\d+) routes"
    },
    {
      "name": "Components",
      "source": "glob:src/components/**/*.tsx",
      "exclude": ["test", "spec"],
      "readmePattern": "(\\d+) components"
    },
    {
      "name": "API endpoints",
      "source": "glob:src/app/api/**/route.ts",
      "readmePattern": "(\\d+) API endpoints"
    },
    {
      "name": "Wiki pages",
      "source": "glob:src/features/wiki/pages/*.tsx",
      "readmePattern": "(\\d+) wiki articles"
    },
    {
      "name": "ESLint rules",
      "source": "file:packages/eslint-plugin/src/index.ts",
      "countPattern": "createRule",
      "readmePattern": "(\\d+) custom rules"
    },
    {
      "name": "Prisma models",
      "source": "file:prisma/schema.prisma",
      "countPattern": "^model \\w+",
      "readmePattern": "(\\d+) database models"
    },
    {
      "name": "Node types",
      "source": "file:src/lib/node-types.ts",
      "countPattern": "export.*NodeType",
      "readmePattern": "(\\d+) node types"
    },
    {
      "name": "i18n locales",
      "source": "file:src/lib/i18n/translations/index.ts",
      "countPattern": "\\w+: \\{",
      "readmePattern": "(\\d+) locales"
    },
    {
      "name": "Commits",
      "source": "git:HEAD",
      "readmePattern": "(\\d+) commits",
      "tolerance": 5
    }
  ],
  "versionSync": {
    "source": "file:package.json",
    "extractPattern": "\"version\"\\s*:\\s*\"([\\d.]+)\"",
    "targets": [
      { "file": "README.md", "pattern": "v([\\d.]+)" },
      { "file": "CHANGELOG.md", "pattern": "## \\[([\\d.]+)\\]" },
      { "file": "package-lock.json", "pattern": "\"version\"\\s*:\\s*\"([\\d.]+)\"" }
    ]
  },
  "featureStatus": [
    {
      "name": "Wiki",
      "stubPatterns": ["stub", "TODO", "planned"],
      "docFile": "WORKFLOW.md",
      "contextPattern": "wiki",
      "implementationFiles": ["src/features/wiki/pages/index.tsx"],
      "implementedPatterns": ["implemented", "done"]
    }
  ],
  "docCoverage": [
    {
      "name": "components/ in README",
      "sourceDir": "src/components",
      "docFile": "README.md",
      "requiredMention": false,
      "severity": "warn"
    },
    {
      "name": "features/ in WORKFLOW",
      "sourceDir": "src/features",
      "docFile": "WORKFLOW.md",
      "requiredMention": false,
      "severity": "warn"
    },
    {
      "name": "packages/ in ARCHITECTURE",
      "sourceDir": "packages",
      "glob": "package.json",
      "docFile": "ARCHITECTURE.md",
      "requiredMention": true,
      "severity": "err",
      "excludePatterns": ["test-utils"]
    }
  ]
}
```

---

## Common Patterns

| What you want to protect | Section to use | Example |
|---|---|---|
| Numbers in README (routes, components, tests) | `checks` | `glob:src/app/**/page.tsx` + `readmePattern` |
| Version in multiple files | `versionSync` | `package.json` → 5 targets |
| Files mentioned in WORKFLOW.md | `docCoverage` | `sourceDir: "src/features"`, `docFile: "WORKFLOW.md"` |
| Files mentioned in ARCHITECTURE.md | `docCoverage` | `sourceDir: "packages"`, `docFile: "ARCHITECTURE.md"` |
| Stub docs that should say "done" | `featureStatus` | `stubPatterns` + `implementationFiles` |
| Cross-repo consistency | `crossRepo` | See monorepo example |

## Severity Levels

- **`"err"`** — blocks commit in pre-commit hook
- **`"warn"`** — prints warning, allows commit (good for starting out)
- **`"infoOnly": true`** — just shows the value, no comparison (good for discovery)

## Recommended Migration Path

1. Run `--init` to generate a starter config
2. Add `"infoOnly": true` checks for counts you care about
3. Commit and verify the output looks correct
4. Switch `infoOnly` → real `readmePattern` one by one
5. Add `docCoverage` entries for non-README docs (WORKFLOW, ARCHITECTURE)
6. Set `severity: "warn"` first, then promote to `"err"` once stable

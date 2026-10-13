# Session log

`worklog.md` is the file the pre-commit hook checks: it must exist, be at least
50 bytes, contain two `---` separators and be no older than 10 minutes. It is
listed in `.gitignore`, so it never reaches the repository -- the record of what
an agent actually did disappears together with the working copy.

This file is the tracked version of that record. `worklog.md` stays the hook's
scratchpad; read this file to find out what was done, what is still open, and
what the reasoning was. Newest entry first.

---

## 2026-10-13 -- v2.5.0 audit, defect fixes, 2.5.1, unified gate

Branch: `arena/bab47372-anti-hallucination-guard`
Commits: `f4592f6` (merged, PR 22), `f5055d1` (local, not pushed)

### What was done

Reviewed the whole module: README, AGENT_RULES.md, registry.json, the three
hooks, every script under `scripts/` and the verify-docs engine. Every defect
below was reproduced first, fixed second, and pinned by a test that fails
against the pre-fix code.

| Defect | Effect | Fix |
|--------|--------|-----|
| `co-change-check.sh` ran under `set -e` | a `severity: block` violation exited 2; pre-commit reads 2 as "unexpected error" and only warned, so the commit went through without its buddy file | explicit exit codes 0 pass / 1 blocked / 2 not evaluated; `COCHANGE_STRICT=1` blocks an unevaluated check |
| `cli.ts` auto-discover | printed "N mismatch(es) found!" and exited 0 | exits 1, as its own `--help` promises |
| `bump.ts` replace callback | treated the match offset and the source string as capture groups: `version: 9.9.9` became `version: 2.0.06` | capture-preserving replacement |
| `bump.ts` notation handling | only the first notation per file was replaced; a re-run stacked a duplicate empty CHANGELOG section | all five patterns global; changelog early-return plus entry guard |
| `discover-versions.ts` | counted CHANGELOG and gitignored files as version files; skipped `tools/verify-docs/` even inside the module | `git-ignore.ts` with `gitIgnoredFiles`/`isIgnored`; skip conditional on `!isAhgModule` |
| `verify-section3.ts` | a configured but missing version target was a silent skip | reports ERR |
| `verify-section4.ts` | a file holding nothing but a TODO stub counted as "Implemented" | stub markers are ERR; wording says "presence check only" |
| `audit.sh` | `git log --oneline \| uniq -d` could never match; `MAX_SCORE=100` against 90 attainable points, so the verdict accused the agent of faking activity | duplicate detection over commit subjects; `MAX_SCORE=90`; configurable window |

Then the structural part. The same checks were assembled in four places -- the
pre-commit hook, the pre-push hook, `.github/workflows/validate.yml`, and
`ahg.sh`, which could call each tool but had no "run everything" command. Four
lists drift, and a check missing from one of them is silently not run there.

- `scripts/check.sh`: one registry. Each check declares its stages
  (`all | ci | push | commit`), its scope (module vs consumer project) and the
  tool it needs. A check whose tool is missing is reported as SKIP, never as
  PASS; `--strict` turns a skip into a failure.
- `scripts/doctor.sh`: context, tool versions, installed hooks, config files.
- `ahg.sh`: the `check`, `doctor` and `test` commands.
- CI: one job -- `ahg doctor`, then `ahg check --stage=ci --strict`.
- `pre-push` (module repo): `check.sh --stage=push`.
- `setup/05`: deploys `check.sh` and `doctor.sh`; their module-only checks skip
  themselves in a consumer project.
- `scripts/tests/check-gate.sh`: 26 self-tests for the gate.
- `discover-versions.ts`: the CHANGELOG-only exclusion became a list of
  historical-record markers (`changelog`, `session-log`, `release-notes`
  and their underscore spellings). Adding this file broke auto-discover,
  and the reason applies to any history file, not just a changelog.

### Verification

| Check | Result |
|-------|--------|
| `ahg check --stage=ci --strict` | 9 passed, 0 failed, 0 skipped |
| `ahg test` | 3 suites green: 26 engine tests, 13 shell checks, 26 gate self-tests |
| `line-count-check.sh` | no violations, 58 files checked |
| `verify-docs --ci` and auto-discover | all checks consistent; coverage 17/17 scripts, 36/36 tools |
| rewritten `pre-push`, run in a disposable clone | intact tree: exit 0, 7 checks. Audit defect reintroduced: exit 1, `[FAIL] tests_shell`, "PUSH BLOCKED. Gate failed.". No bun on PATH: 2 loud SKIPs, exit 0 |

### What is still open

- **`pre-commit` still assembles its own phases.** It is fingerprinted by
  `check-hooks-verify.sh` (SHA256 compared against a snapshot taken at setup)
  and its anti-tamper self-check requires the literal string `worklog` inside
  the hook file, so folding it into the gate means a coordinated change to the
  hook, the snapshot flow and the tamper checks. Left for a separate change.
- **The consumer branch of `pre-push` still calls `ahg.sh verify --ci`.**
  Running `check.sh` from the submodule resolves the root to the submodule and
  would verify AHG instead of the consumer project.
- **Worklog content is validated by shape only** -- size, freshness, separator
  count. 121 bytes of plausible nonsense pass the same check. This file exists
  because that gap is real.
- **Rule 8 is hardcoded to the Z.ai sandbox** (`/home/z/my-project`,
  `.zscripts/dev.sh`). It belongs in an environment adapter, not in rules that
  apply everywhere.
- **Two different version patterns can read the same file.**
  `auto-config.ts` extracts `v([\d.]+)` for `.md` -- the first `v<digits>`
  anywhere in the file. `discover-versions.ts` walks its own pattern list.
  On this very file they disagreed: discovery reported `9.9.9` (from
  `version: 9.9.9` quoted in the defect table), the check reported `2.5.0`
  (from the `v2.5.0` in the heading). Excluding historical records removes
  the symptom here; the divergence itself is still there.
- **Version discovery reads only the first 100 lines of a file**, so `ahg bump`
  cannot reach the version line in `AGENT_RULES.md` (line 399). Recorded under
  Known limitations; the version check does catch the resulting drift.

### Plans, in order

1. Push the branch and open a PR for `f5055d1`.
2. Extract environment adapters (`zai`, `local`, `docker`) so Rule 8 stops being
   universal, and keep the CLI core environment-agnostic.
3. Move the pre-commit phases into the gate, together with the snapshot and
   tamper-check changes, as one versioned change.
4. Decide what a worklog entry must contain to count, and check that instead of
   the byte count.

### Notes

- A passing hook or gate run is evidence about the checks that ran, not about
  the correctness of the claims written here.
- In the sandbox used for this work, bun was reachable only through a symlink to
  the copy fetched by `npx`; without it `ahg check` reports SKIP for the
  bun-dependent checks, which is the behaviour under test, not a workaround.
- `f4592f6` is a squash merge, so the five commits of that change appear as a
  single commit in `main`.

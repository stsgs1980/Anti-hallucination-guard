# Changelog

All notable changes to anti-hallucination-guard are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [2.5.0] - 2026-06-14

### Changed

- AGENT_RULES.md: added H1 title, Quick Reference block (5 critical rules),
  Table of Contents with anchor links, visual [C]/[W] severity markers in
  rule headings (previously only in HTML ID comments), ANTI-MONOLITH exception
  comment for line-count compliance. Removed stray "test" text.
- registry.json: updated all anchors to match new heading format (rule-N-c/w-...).
  Added RULE-015 and RULE-016 entries. Version bumped to 2.5.0.
- README.md: added [C]/[W] Level column to rules table, fixed "14 rules" to
  "17 rules" in two locations. Version bumped to 2.5.0.

## [2.4.0] - 2026-06-14

### Added

- co-change-check.sh: detects that buddy files change together.
  If file A changes, file B should also change in the same commit.
  Config via .ahg-cochange.json in project root. Pre-commit Phase 5.
  Bypass: [no-cochange] in commit message.
- line-count-check.sh: automatic enforcement of Rule 11 (anti-monolith).
  Blocks commit if any source file exceeds 250 lines (configurable via
  LINE_LIMIT env var). Hard cap at 400 lines (no exceptions).
  Supports documented exceptions via `ANTI-MONOLITH exception` comment
  in file header.
- Pre-commit hook Phase 4: line-count check (anti-monolith).
- Pre-commit hook Phase 5: co-change buddy detection.
- Rule 1 (RULE-017, renumbered to RULE-001): Answer before act -- agents MUST
  answer questions before taking action. No unsolicited implementation.
  (Was Rule 17 before v2.5.0 renumbering.)
- .ahg-cochange.json: default co-change dependency graph for AHG files
  (AGENT_RULES.md <-> README.md, registry.json, CHANGELOG.md, worklog.md;
  scripts/* <-> CHANGELOG.md; .git-hooks/* <-> CHANGELOG.md).
- setup/05-deploy-monitoring-scripts.sh: deploys line-count-check.sh,
  co-change-check.sh, and .ahg-cochange.json to consumer projects.

### Changed

- Rule 12 (RULE-011, renumbered to RULE-012): annotated as hook-enforced (Phase 4)
- validate.sh whitelist: added line-count-check.sh, co-change-check.sh
- Pre-commit hook: added Phase 4 (anti-monolith) and Phase 5 (co-change)

### Security

- Rule 12 (anti-monolith) is now enforced at hook level. Agents cannot commit
  files exceeding line limits, even if they ignore the rule in AGENT_RULES.md.
- Co-change detection catches documentation drift at commit time:
  if AGENT_RULES.md changes but README.md does not, the agent is warned.
- Rule 1 prevents agents from implementing without being asked.

## [2.3.0] - 2026-06-13

### Added

- Rule 17 (RULE-016, renumbered to RULE-017): Upstream write protection --
  consumer project agents MUST NOT push, merge, create PRs, or modify AHG
  upstream in any way. Consumer projects are READ-ONLY consumers of the AHG
  submodule. (Was Rule 16 before v2.5.0 renumbering.)
- CODEOWNERS: only @stsgs1980 can approve changes to the repository
- pr-guard.yml workflow: CI-level check that blocks PRs from forks,
  non-collaborators, and anti-tampering attempts (removing Rule 16/17
  or CODEOWNERS)
- setup-branch-protection.sh: one-command GitHub branch protection setup
  (requires `gh` CLI with admin access)

### Changed

- validate.sh whitelist: added .github/CODEOWNERS and
  setup-branch-protection.sh
- .gitignore: un-ignored .github/CODEOWNERS

### Security

- Closed upstream write breach: no consumer project agent can now push
  to AHG without owner approval (5 enforcement layers: Rule 16+17,
  CODEOWNERS, pr-guard.yml CI, validate.sh submodule gate, GitHub
  branch protection)

## [2.2.0] - 2026-06-13

### Added

## [2.1.0] - 2026-06-13

### Added

- Auto-discover fallback for `ahg.sh verify`: runs full 5-section verification
  engine without verify-docs.json config (RULE-012, TOOL-VERIFY)
- `auto-config.ts`: generates VerifyConfig in memory from project structure
- `discover-project.ts`: project type detection (TS/JS/Python/Go/Rust) and
  smart extension scanning (extracted from auto-config for RULE-011 compliance)
- `cli-helpers.ts`: shared output formatting (extracted from cli.ts for
  RULE-011 compliance)
- `--init` flag now uses shared `generateAutoConfig()` (no duplicated logic)

### Changed

- `verify` without config runs full 5-section engine (was: discover overview only)
- AGENT_RULES.md Rule 12 updated: `ahg bump` now adds CHANGELOG entry
- AGENT_RULES.md Rule 13 updated: cascade-state.json auto-sync in hook

## [2.0.0] - 2026-06-12

### Added

- 14 agent rules in AGENT_RULES.md (RULE-001 through RULE-014)
- 5-section verify-docs engine (README vs Code, Cross-repo, Version sync,
  Feature status, Doc coverage)
- Auto-discover mode: version files, CHANGELOG freshness, coverage gaps,
  baseline tracking
- Atomic version bump via `ahg bump X.Y.Z`
- Unified CLI: `ahg.sh` with verify/discover/bump/init/baseline/snapshot/
  integrity/sync/audit/validate commands
- Pre-commit hook with 5 phases (integrity, worklog, sync, verify, discover)
- Pre-push hook with module purity check
- check-hooks integrity system (snapshot + verify, anti-tampering)
- Branch protection (branch-protect.sh + branch-protect-lib.sh)
- sync-task-state.sh for cascade-state.json auto-sync
- setup.sh modular installer (9 steps in setup/ directory)
- update.sh for submodule pull + reinstall
- validate.sh for repository purity + Unicode policy enforcement
- Z.ai skill definition (SKILL.md)

### Changed

- Monolith check-hooks.sh split into snapshot/verify (RULE-011)
- Monolith check-hooks-integrity.sh renamed to check-hooks-verify.sh

## [1.0.0] - 2026-06-10

### Added

- Initial release: basic git hooks, worklog enforcement, AGENT_RULES.md
- Single check-hooks.sh for integrity verification

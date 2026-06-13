# Changelog

All notable changes to anti-hallucination-guard are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [2.3.0] - 2026-06-13

### Added

- Rule 16 (RULE-016): Upstream write protection -- consumer project agents
  MUST NOT push, merge, create PRs, or modify AHG upstream in any way.
  Consumer projects are READ-ONLY consumers of the AHG submodule.
- CODEOWNERS: only @stsgs1980 can approve changes to the repository
- pr-guard.yml workflow: CI-level check that blocks PRs from forks,
  non-collaborators, and anti-tampering attempts (removing Rule 15/16
  or CODEOWNERS)
- setup-branch-protection.sh: one-command GitHub branch protection setup
  (requires `gh` CLI with admin access)

### Changed

- validate.sh whitelist: added .github/CODEOWNERS and
  setup-branch-protection.sh
- .gitignore: un-ignored .github/CODEOWNERS

### Security

- Closed upstream write breach: no consumer project agent can now push
  to AHG without owner approval (5 enforcement layers: Rule 15+16,
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

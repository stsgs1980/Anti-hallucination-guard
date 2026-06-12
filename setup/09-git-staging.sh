#!/usr/bin/env bash
# setup/09-git-staging.sh
# Stages all installed files for git commit.

cd "$PROJECT_ROOT"
git add AGENT_RULES.md worklog.md .git/hooks/pre-commit .git/hooks/pre-push scripts/ tools/ 2>/dev/null || true
ok "Files added to git staging"

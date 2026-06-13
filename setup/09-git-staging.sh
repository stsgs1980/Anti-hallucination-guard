#!/usr/bin/env bash
# setup/09-git-staging.sh
# Stages all installed files for git commit.

cd "$PROJECT_ROOT"

# Build file list -- skip worklog.md when running in AHG standalone repo
# (worklog.md is a host-project file, not for distribution in the AHG module)
# When MODULE_ROOT == PROJECT_ROOT, we are in the AHG repo itself, not a consumer project.
STAGE_FILES="AGENT_RULES.md .git/hooks/pre-commit .git/hooks/pre-push scripts/ tools/"
if [ "$MODULE_ROOT" != "$PROJECT_ROOT" ]; then
    STAGE_FILES="worklog.md $STAGE_FILES"
fi

git add $STAGE_FILES 2>/dev/null || true
ok "Files added to git staging"

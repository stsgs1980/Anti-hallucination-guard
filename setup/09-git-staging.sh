#!/usr/bin/env bash
# setup/09-git-staging.sh
# Stages all installed files for git commit.

cd "$PROJECT_ROOT"

# Build file list -- skip worklog.md when running in AHG standalone repo
# (worklog.md is a host-project file, not for distribution in the AHG module)
# When MODULE_ROOT == PROJECT_ROOT, we are in the AHG repo itself, not a consumer project.
STAGE_FILES="AGENT_RULES.md .git/hooks/pre-commit .git/hooks/pre-push scripts/"
if [ "$MODULE_ROOT" != "$PROJECT_ROOT" ]; then
    # Host project: add worklog.md (host-project file)
    # Do NOT add tools/ -- verify-docs runs from the submodule, not from host root
    STAGE_FILES="worklog.md $STAGE_FILES"
else
    # AHG standalone repo: add tools/ (it's part of the module)
    STAGE_FILES="$STAGE_FILES tools/"
fi

git add $STAGE_FILES 2>/dev/null || true
ok "Files added to git staging"

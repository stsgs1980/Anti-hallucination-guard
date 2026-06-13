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

# Use git add with -- to separate paths from options.
# Quote each path to handle spaces. Silencing stderr is intentional here:
# some files (e.g. .git/hooks/) may not exist if setup was partial.
for _f in $STAGE_FILES; do
    git add -- "$_f" 2>/dev/null || true
done

# Write setup stamp (for post-checkout stale hook detection)
_AHG_STAMP="$PROJECT_ROOT/.ahg-setup-stamp"
if [ "$MODULE_ROOT" != "$PROJECT_ROOT" ]; then
    _stamp_hash="$(cd "$MODULE_ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")"
    echo "commit=$_stamp_hash" > "$_AHG_STAMP"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$_AHG_STAMP"
    ok "Setup stamp written (.ahg-setup-stamp)"
fi

ok "Files added to git staging"

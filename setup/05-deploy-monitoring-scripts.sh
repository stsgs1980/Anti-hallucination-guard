#!/usr/bin/env bash
# setup/05-deploy-monitoring-scripts.sh
# Copies monitoring scripts to the consumer project's scripts/ directory.
# On update: overwrites existing scripts to ensure latest version is deployed.

mkdir -p "$PROJECT_ROOT/scripts"

# Resolve real MODULE_ROOT path (for nested-deploy protection)
_module_real="$(readlink -f "$MODULE_ROOT" 2>/dev/null || echo "$MODULE_ROOT")"

# Helper: deploy a script, overwriting if it's ours (has AHG marker),
# skipping if it's a custom file from the project.
deploy_script() {
    local NAME="$1"
    local SRC="$MODULE_ROOT/scripts/$NAME"
    local DST="$PROJECT_ROOT/scripts/$NAME"

    if [ ! -f "$SRC" ]; then
        warn "$NAME not found in module -- skipping"
        return
    fi

    # Skip if SRC and DST resolve to the same file (running in AHG standalone repo)
    # Use canonical paths to catch symlinks and relative path differences
    local SRC_REAL DST_REAL
    SRC_REAL="$(readlink -f "$SRC" 2>/dev/null || echo "$SRC")"
    DST_REAL="$(readlink -f "$DST" 2>/dev/null || echo "$DST")"
    if [ "$SRC_REAL" = "$DST_REAL" ]; then
        ok "scripts/$NAME is module source -- skip copy"
        return
    fi

    # Safety: never deploy scripts INSIDE the AHG module directory.
    # This prevents creating a nested scripts/scripts/ copy when
    # running from within the AHG submodule.
    if [ "$DST_REAL" = "${DST_REAL#$_module_real}" ] 2>/dev/null; then
        : # DST is outside MODULE_ROOT -- good
    else
        # DST is inside MODULE_ROOT -- skip to avoid nested copy
        warn "scripts/$NAME: DST inside module dir -- skip (would create nested copy)"
        return
    fi

    if [ -f "$DST" ]; then
        # Check if it's our file (deployed by AHG previously)
        if grep -q "anti-hallucination-guard\|verify-docs" "$DST" 2>/dev/null; then
            # Ours -- update to latest
            cp "$SRC" "$DST"
            chmod +x "$DST" 2>/dev/null || true
            ok "scripts/$NAME updated"
        else
            # Foreign/custom file -- don't overwrite
            warn "scripts/$NAME exists (custom) -- skipping (not overwriting)"
        fi
    else
        cp "$SRC" "$DST"
        chmod +x "$DST" 2>/dev/null || true
        ok "scripts/$NAME created"
    fi
}

# -- Deploy all scripts --------------------------------------------------------
# validate.sh is NOT deployed -- it checks AHG module purity,
# not consumer project files. Running it in a consumer project
# would flag ALL consumer files as FORBIDDEN.
deploy_script "check-agent.sh"
deploy_script "audit.sh"
deploy_script "sync-task-state.sh"
deploy_script "ahg.sh"
deploy_script "check-hooks-lib.sh"
deploy_script "check-hooks-snapshot.sh"
deploy_script "check-hooks-verify.sh"
deploy_script "line-count-check.sh"
deploy_script "co-change-check.sh"

# Note: .ahg-cochange.json is NOT deployed to consumer projects.
# It contains AHG-internal co-change rules (AGENT_RULES.md <-> README.md etc.)
# which are meaningless in consumer project context.
# Consumer projects should create their own .ahg-cochange.json if they want
# co-change detection for their own files.

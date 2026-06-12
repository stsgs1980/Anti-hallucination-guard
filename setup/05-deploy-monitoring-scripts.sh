#!/usr/bin/env bash
# setup/05-deploy-monitoring-scripts.sh
# Copies monitoring scripts to the consumer project's scripts/ directory.
# On update: overwrites existing scripts to ensure latest version is deployed.

mkdir -p "$PROJECT_ROOT/scripts"

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
deploy_script "validate.sh"
deploy_script "check-agent.sh"
deploy_script "audit.sh"
deploy_script "sync-task-state.sh"
deploy_script "ahg.sh"
deploy_script "check-hooks-lib.sh"
deploy_script "check-hooks-snapshot.sh"
deploy_script "check-hooks-verify.sh"

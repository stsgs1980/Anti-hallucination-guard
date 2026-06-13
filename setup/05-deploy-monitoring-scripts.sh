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

    # Skip if SRC and DST are the same file (running in AHG standalone repo)
    if [ "$SRC" = "$DST" ]; then
        ok "scripts/$NAME is module source -- skip copy"
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

# -- Deploy .ahgrc config (if not already present) ---------------------------
if [ "$MODULE_ROOT" != "$PROJECT_ROOT" ]; then
    _ahgrc_src="$MODULE_ROOT/.ahgrc"
    _ahgrc_dst="$PROJECT_ROOT/.ahgrc"
    if [ -f "$_ahgrc_src" ]; then
        if [ ! -f "$_ahgrc_dst" ]; then
            cp "$_ahgrc_src" "$_ahgrc_dst"
            ok ".ahgrc config created (edit to customize line-check settings)"
        else
            ok ".ahgrc config already exists (keeping yours)"
        fi
    fi
fi

# Note: .ahg-cochange.json is NOT deployed to consumer projects.
# It contains AHG-internal co-change rules (AGENT_RULES.md <-> README.md etc.)
# which are meaningless in consumer project context.
# Consumer projects should create their own .ahg-cochange.json if they want
# co-change detection for their own files.

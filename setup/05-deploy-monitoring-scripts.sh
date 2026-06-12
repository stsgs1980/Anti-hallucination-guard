#!/usr/bin/env bash
# setup/05-deploy-monitoring-scripts.sh
# Copies monitoring scripts to the consumer project's scripts/ directory.

mkdir -p "$PROJECT_ROOT/scripts"

# -- validate.sh ---------------------------------------------------------------
if [ -f "$PROJECT_ROOT/scripts/validate.sh" ]; then
    warn "scripts/validate.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/validate.sh" "$PROJECT_ROOT/scripts/validate.sh"
    chmod +x "$PROJECT_ROOT/scripts/validate.sh" 2>/dev/null || true
    ok "scripts/validate.sh created"
fi

# -- check-agent.sh ------------------------------------------------------------
if [ -f "$PROJECT_ROOT/scripts/check-agent.sh" ]; then
    warn "scripts/check-agent.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/check-agent.sh" "$PROJECT_ROOT/scripts/check-agent.sh"
    chmod +x "$PROJECT_ROOT/scripts/check-agent.sh"
    ok "scripts/check-agent.sh created"
fi

# -- audit.sh ------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/scripts/audit.sh" ]; then
    warn "scripts/audit.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/audit.sh" "$PROJECT_ROOT/scripts/audit.sh"
    chmod +x "$PROJECT_ROOT/scripts/audit.sh"
    ok "scripts/audit.sh created"
fi

# -- sync-task-state.sh --------------------------------------------------------
if [ -f "$PROJECT_ROOT/scripts/sync-task-state.sh" ]; then
    warn "scripts/sync-task-state.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/sync-task-state.sh" "$PROJECT_ROOT/scripts/sync-task-state.sh"
    chmod +x "$PROJECT_ROOT/scripts/sync-task-state.sh"
    ok "scripts/sync-task-state.sh created"
fi

# -- ahg.sh (unified CLI) ------------------------------------------------------
if [ -f "$PROJECT_ROOT/scripts/ahg.sh" ]; then
    warn "scripts/ahg.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/ahg.sh" "$PROJECT_ROOT/scripts/ahg.sh"
    chmod +x "$PROJECT_ROOT/scripts/ahg.sh"
    ok "scripts/ahg.sh created"
fi

# -- check-hooks-lib.sh --------------------------------------------------------
if [ -f "$PROJECT_ROOT/scripts/check-hooks-lib.sh" ]; then
    warn "scripts/check-hooks-lib.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/check-hooks-lib.sh" "$PROJECT_ROOT/scripts/check-hooks-lib.sh"
    chmod +x "$PROJECT_ROOT/scripts/check-hooks-lib.sh"
    ok "scripts/check-hooks-lib.sh created"
fi

# -- check-hooks-snapshot.sh ---------------------------------------------------
if [ -f "$PROJECT_ROOT/scripts/check-hooks-snapshot.sh" ]; then
    warn "scripts/check-hooks-snapshot.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/check-hooks-snapshot.sh" "$PROJECT_ROOT/scripts/check-hooks-snapshot.sh"
    chmod +x "$PROJECT_ROOT/scripts/check-hooks-snapshot.sh"
    ok "scripts/check-hooks-snapshot.sh created"
fi

# -- check-hooks-verify.sh -----------------------------------------------------
if [ -f "$PROJECT_ROOT/scripts/check-hooks-verify.sh" ]; then
    warn "scripts/check-hooks-verify.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/check-hooks-verify.sh" "$PROJECT_ROOT/scripts/check-hooks-verify.sh"
    chmod +x "$PROJECT_ROOT/scripts/check-hooks-verify.sh"
    ok "scripts/check-hooks-verify.sh created"
fi

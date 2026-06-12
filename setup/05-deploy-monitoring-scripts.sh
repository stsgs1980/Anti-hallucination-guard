#!/usr/bin/env bash
# setup/05-deploy-monitoring-scripts.sh
# Copies monitoring scripts (validate.sh, check-agent.sh, audit.sh)
# to the consumer project's scripts/ directory.

CHECK_SCRIPT="$PROJECT_ROOT/scripts/check-agent.sh"
AUDIT_SCRIPT="$PROJECT_ROOT/scripts/audit.sh"
VALIDATE_SCRIPT="$PROJECT_ROOT/scripts/validate.sh"

mkdir -p "$PROJECT_ROOT/scripts"

if [ -f "$VALIDATE_SCRIPT" ]; then
    warn "scripts/validate.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/validate.sh" "$VALIDATE_SCRIPT"
    chmod +x "$VALIDATE_SCRIPT" 2>/dev/null || true
    ok "scripts/validate.sh created"
fi

if [ -f "$CHECK_SCRIPT" ]; then
    warn "scripts/check-agent.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/check-agent.sh" "$CHECK_SCRIPT"
    chmod +x "$CHECK_SCRIPT"
    ok "scripts/check-agent.sh created"
fi

if [ -f "$AUDIT_SCRIPT" ]; then
    warn "scripts/audit.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/audit.sh" "$AUDIT_SCRIPT"
    chmod +x "$AUDIT_SCRIPT"
    ok "scripts/audit.sh created"
fi

SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-task-state.sh"

if [ -f "$SYNC_SCRIPT" ]; then
    warn "scripts/sync-task-state.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/sync-task-state.sh" "$SYNC_SCRIPT"
    chmod +x "$SYNC_SCRIPT"
    ok "scripts/sync-task-state.sh created"
fi

INTEGRITY_SCRIPT="$PROJECT_ROOT/scripts/check-hooks-integrity.sh"

if [ -f "$INTEGRITY_SCRIPT" ]; then
    warn "scripts/check-hooks-integrity.sh already exists -- skipping"
else
    cp "$MODULE_ROOT/scripts/check-hooks-integrity.sh" "$INTEGRITY_SCRIPT"
    chmod +x "$INTEGRITY_SCRIPT"
    ok "scripts/check-hooks-integrity.sh created"
fi

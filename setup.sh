#!/bin/bash
# ============================================================
# anti-hallucination-guard / setup.sh
# Installs anti-hallucination mechanisms into a project.
# Run from project root:
#   bash path/to/anti-hallucination-guard/setup.sh
#
# Idempotent: safe to run multiple times.
# Uses HTML comment markers for AGENT_RULES.md merging
# (compatible with cascade-guard's marker system).
#
# This is the orchestrator. Individual steps live in setup/ directory.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$SCRIPT_DIR/setup"

# Source shared functions (MODULE_ROOT, PROJECT_ROOT, ok/warn/info/err)
source "$SETUP_DIR/_lib.sh"

# --- Checks ---
echo ""
echo "============================================"
echo "  ANTI-HALLUCINATION-GUARD -- Project Setup"
echo "============================================"
echo ""
echo "Project root: $PROJECT_ROOT"
echo "Module dir:   $MODULE_ROOT"
echo ""

if [ ! -d "$PROJECT_ROOT/.git" ]; then
    warn "Git is not initialized in this project."
    read -rp "Initialize git now? (y/N): " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        git init "$PROJECT_ROOT"
        ok "git init"
    else
        err "Git is required for hooks to work. Exiting."
        exit 1
    fi
fi

cd "$PROJECT_ROOT"

# Run setup steps in order
source "$SETUP_DIR/01-deploy-agent-rules.sh"
source "$SETUP_DIR/02-create-worklog.sh"
source "$SETUP_DIR/03-install-pre-commit-hook.sh"
source "$SETUP_DIR/04-install-pre-push-hook.sh"
source "$SETUP_DIR/05-deploy-monitoring-scripts.sh"
source "$SETUP_DIR/06-deploy-skill.sh"
source "$SETUP_DIR/07-install-verify-docs.sh"
source "$SETUP_DIR/08-integrate-cascade-guard.sh"
source "$SETUP_DIR/09-git-staging.sh"

# ---- Summary ----
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "Installed:"
echo "  AGENT_RULES.md          -- agent work rules (AHG section with markers)"
echo "  worklog.md              -- mandatory work log"
echo "  .git/hooks/pre-commit   -- blocks commit without fresh worklog"
echo "  .git/hooks/pre-push     -- blocks push with foreign files"
echo "  scripts/check-agent.sh  -- activity monitor"
echo "  scripts/audit.sh        -- post-session audit"
echo "  scripts/validate.sh     -- module purity checker"
if command -v bun &>/dev/null && [ -d "$MODULE_ROOT/tools/verify-docs" ]; then
echo "  tools/verify-docs       -- README number checker (bun)"
echo "  pre-commit hook         -- + verify-docs (if verify-docs.json exists)"
fi
echo ""
echo "Rule namespacing in AGENT_RULES.md:"
echo "  Rule 1-7     = Anti-hallucination core (worklog, no-loops, honest reporting, sandbox)"
echo "  Rule 8       = Session Start Protocol (drift prevention)"
echo "  Rule 9       = Documentation Sync (no code without docs)"
if [ -n "$CG_DIR" ] && [ -d "$CG_DIR" ]; then
echo "  Rule C-1..C-9 = Cascade (deps, priorities, acceptance verification)"
else
echo "  (Install cascade-guard for task cascade rules C-1..C-9)"
fi
echo ""
echo "Agent startup prompt:"
echo "  Before starting work, read AGENT_RULES.md and worklog.md."
echo "  Record every action in worklog.md."
echo "  After each logical block -- git commit."
echo ""

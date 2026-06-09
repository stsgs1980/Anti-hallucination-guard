#!/bin/bash
# ============================================================
# anti-hallucination-guard / setup.sh
# Installs anti-hallucination mechanisms into a project.
# Run from project root:
#   bash path/to/anti-hallucination-guard/setup.sh
# ============================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
WORKLOG="$PROJECT_ROOT/worklog.md"
RULES="$PROJECT_ROOT/AGENT_RULES.md"
HOOK_DIR="$PROJECT_ROOT/.git/hooks"
HOOK_SRC="$SCRIPT_DIR/.git-hooks/pre-commit"
PUSH_HOOK_SRC="$SCRIPT_DIR/.git-hooks/pre-push"
CHECK_SCRIPT="$PROJECT_ROOT/scripts/check-agent.sh"
AUDIT_SCRIPT="$PROJECT_ROOT/scripts/audit.sh"
VALIDATE_SCRIPT="$PROJECT_ROOT/scripts/validate.sh"

# Terminal colors (only when TTY is available)
if [ -t 1 ]; then
    GREEN="[32m"
    RED="[31m"
    YELLOW="[33m"
    RESET="[0m"
else
    GREEN=""
    RED=""
    YELLOW=""
    RESET=""
fi

ok()   { echo -e "${GREEN}[OK]${RESET} $1"; }
err()  { echo -e "${RED}[ERROR]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }

# --- Checks ---
echo ""
echo "=== anti-hallucination-guard: setup ==="
echo "Project root: $PROJECT_ROOT"
echo "Module dir:   $SCRIPT_DIR"
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

# --- 1. AGENT_RULES.md ---
if [ -f "$RULES" ]; then
    warn "AGENT_RULES.md already exists -- skipping (will not overwrite)"
else
    cp "$SCRIPT_DIR/AGENT_RULES.md" "$RULES"
    ok "AGENT_RULES.md created"
fi

# --- 2. worklog.md ---
if [ -f "$WORKLOG" ]; then
    warn "worklog.md already exists -- skipping (will not overwrite)"
else
    cat > "$WORKLOG" << 'WORKLOG_EOF'
---
Task ID: 0
Agent: setup
Task: anti-hallucination-guard initialization

Work Log:
- setup.sh executed
- AGENT_RULES.md created
- Pre-commit hook installed
- Monitoring scripts copied

Stage Summary:
- Mechanisms active
- Ready to start work
---
WORKLOG_EOF
    ok "worklog.md created"
fi

# --- 3. Pre-commit hook ---
mkdir -p "$HOOK_DIR"

if [ -f "$HOOK_DIR/pre-commit" ]; then
    EXPECTED_MARKER="anti-hallucination-guard"
    if grep -q "$EXPECTED_MARKER" "$HOOK_DIR/pre-commit" 2>/dev/null; then
        warn "pre-commit hook already installed (ours) -- updating"
        cp "$HOOK_SRC" "$HOOK_DIR/pre-commit"
        chmod +x "$HOOK_DIR/pre-commit"
        ok "pre-commit hook updated"
    else
        warn "pre-commit hook already exists (foreign) -- will not overwrite"
        echo "  To install manually:"
        echo "  cp $HOOK_SRC $HOOK_DIR/pre-commit"
    fi
else
    cp "$HOOK_SRC" "$HOOK_DIR/pre-commit"
    chmod +x "$HOOK_DIR/pre-commit"
    ok "pre-commit hook installed"
fi

# --- 4. Pre-push hook (module protection) ---
if [ -f "$HOOK_DIR/pre-push" ]; then
    warn "pre-push hook already exists -- skipping"
else
    cp "$PUSH_HOOK_SRC" "$HOOK_DIR/pre-push"
    chmod +x "$HOOK_DIR/pre-push" 2>/dev/null || true
    ok "pre-push hook installed"
fi

# --- 5. Monitoring scripts ---
mkdir -p "$PROJECT_ROOT/scripts"

if [ -f "$VALIDATE_SCRIPT" ]; then
    warn "scripts/validate.sh already exists -- skipping"
else
    cp "$SCRIPT_DIR/scripts/validate.sh" "$VALIDATE_SCRIPT"
    chmod +x "$VALIDATE_SCRIPT" 2>/dev/null || true
    ok "scripts/validate.sh created"
fi

if [ -f "$CHECK_SCRIPT" ]; then
    warn "scripts/check-agent.sh already exists -- skipping"
else
    cp "$SCRIPT_DIR/scripts/check-agent.sh" "$CHECK_SCRIPT"
    chmod +x "$CHECK_SCRIPT"
    ok "scripts/check-agent.sh created"
fi

if [ -f "$AUDIT_SCRIPT" ]; then
    warn "scripts/audit.sh already exists -- skipping"
else
    cp "$SCRIPT_DIR/scripts/audit.sh" "$AUDIT_SCRIPT"
    chmod +x "$AUDIT_SCRIPT"
    ok "scripts/audit.sh created"
fi

# --- 6. Skill (if skills/ exists in project) ---
if [ -d "$PROJECT_ROOT/skills" ]; then
    SKILL_DIR="$PROJECT_ROOT/skills/anti-hallucination-guard"
    if [ -d "$SKILL_DIR" ]; then
        warn "skills/anti-hallucination-guard already exists -- skipping"
    else
        cp -r "$SCRIPT_DIR/skills/anti-hallucination-guard" "$SKILL_DIR"
        ok "skills/anti-hallucination-guard created"
    fi
else
    warn "skills/ not found -- skill not installed (not required for Z.ai)"
fi

# --- 7. verify-docs (optional, requires bun) ---
VERIFY_DOCS_DIR="$SCRIPT_DIR/tools/verify-docs"
VERIFY_DOCS_PKG="$PROJECT_ROOT/tools/verify-docs"

if [ -d "$VERIFY_DOCS_DIR" ] && command -v bun &>/dev/null; then
    if [ -d "$VERIFY_DOCS_PKG" ]; then
        warn "tools/verify-docs already exists -- skipping"
    else
        mkdir -p "$PROJECT_ROOT/tools"
        cp -r "$VERIFY_DOCS_DIR" "$VERIFY_DOCS_PKG"
        cd "$VERIFY_DOCS_PKG"
        bun install 2>/dev/null || true
        cd "$PROJECT_ROOT"
        ok "tools/verify-docs installed (run: bun run tools/verify-docs/src/cli.ts)"
    fi

    # Create verify-docs.json if missing
    if [ ! -f "$PROJECT_ROOT/verify-docs.json" ]; then
        warn "verify-docs.json not found -- create manually or run: bun run tools/verify-docs/src/init.ts"
    fi

    # Add verify-docs to pre-commit hook if not already there
    if grep -q "verify-docs" "$HOOK_DIR/pre-commit" 2>/dev/null; then
        ok "verify-docs already in pre-commit hook"
    else
        cat >> "$HOOK_DIR/pre-commit" << 'VERIFY_DOCS_HOOK'

# --- verify-docs: check README numbers ---
if command -v bun &>/dev/null && [ -f "verify-docs.json" ]; then
    VERIFY_RESULT=$(bun run tools/verify-docs/src/cli.ts --ci 2>&1)
    VERIFY_EXIT=$?
    if [ "$VERIFY_EXIT" -ne 0 ]; then
        echo ""
        echo "  ERROR: verify-docs found a mismatch!"
        echo ""
        echo "$VERIFY_RESULT"
        echo ""
        echo "  Fix the numbers in README or in verify-docs.json."
        echo "  Or bypass: git commit --no-verify"
        echo ""
        exit 1
    fi
    echo "  OK: verify-docs passed"
fi
VERIFY_DOCS_HOOK
        ok "verify-docs added to pre-commit hook"
    fi
elif [ -d "$VERIFY_DOCS_DIR" ]; then
    warn "verify-docs skipped: bun not found (install: curl -fsSL https://bun.sh/install | bash)"
else
    warn "verify-docs not found in module -- skipping"
fi

# --- 8. Git staging ---
cd "$PROJECT_ROOT"
git add AGENT_RULES.md worklog.md .git/hooks/pre-commit scripts/ tools/ 2>/dev/null || true
ok "Files added to git staging"

# --- Summary ---
echo ""
echo "=== Setup complete ==="
echo ""
echo "Installed:"
echo "  AGENT_RULES.md          -- agent work rules"
echo "  worklog.md              -- mandatory work log"
echo "  .git/hooks/pre-commit  -- blocks commit without fresh worklog"
echo "  .git/hooks/pre-push     -- blocks push with foreign files"
echo "  scripts/check-agent.sh -- activity monitor"
echo "  scripts/audit.sh       -- post-session audit"
echo "  scripts/validate.sh    -- module purity checker"
if command -v bun &>/dev/null && [ -d "$VERIFY_DOCS_DIR" ]; then
echo "  tools/verify-docs      -- README number checker (bun)"
echo "  pre-commit hook        -- + verify-docs (if verify-docs.json exists)"
fi
echo ""
echo "Agent startup prompt:"
echo "  Before starting work, read /AGENT_RULES.md and /worklog.md."
echo "  Record every action in worklog.md."
echo "  After each logical block -- git commit."
echo ""

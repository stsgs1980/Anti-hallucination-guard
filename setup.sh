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
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    NC=""
fi

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# --- Checks ---
echo ""
echo "============================================"
echo "  ANTI-HALLUCINATION-GUARD — Project Setup"
echo "============================================"
echo ""
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

# ---- 1. AGENT_RULES.md with marker-based merging ----
# Uses markers: <!-- AHG:START --> ... <!-- AHG:END -->
# This is idempotent: removes old block first, then inserts new one.
# Compatible with cascade-guard's <!-- CASCADE-GUARD:START/END --> markers.

AHG_BLOCK_SRC="$SCRIPT_DIR/AGENT_RULES.md"

if [ -f "$RULES" ]; then
    # Check if AHG block already exists
    if grep -q "AHG:START" "$RULES" 2>/dev/null; then
        # Remove old AHG block (between markers, inclusive)
        sed '/<!-- AHG:START -->/,/<!-- AHG:END -->/d' "$RULES" > "${RULES}.tmp"
        mv "${RULES}.tmp" "$RULES"
        ok "Removed previous AHG block from AGENT_RULES.md"
    fi

    # Append new AHG block
    echo "" >> "$RULES"
    echo "<!-- AHG:START -->" >> "$RULES"
    echo "<!-- Do NOT edit between START and END markers. This block is managed by anti-hallucination-guard/setup.sh -->" >> "$RULES"
    # Insert the rules content (without the version footer line, we add our own)
    grep -v '^v[0-9]' "$AHG_BLOCK_SRC" | grep -v '^---$' | grep -v '^# AGENT RULES' | grep -v '^> Copied to project' >> "$RULES"
    echo "" >> "$RULES"
    echo "<!-- AHG:END -->" >> "$RULES"
    ok "AHG block appended to existing AGENT_RULES.md"
else
    # Create new AGENT_RULES.md with AHG block
    echo "# AGENT RULES -- VIOLATION IS NOT ACCEPTABLE" > "$RULES"
    echo "" >> "$RULES"
    echo "<!-- AHG:START -->" >> "$RULES"
    echo "<!-- Do NOT edit between START and END markers. This block is managed by anti-hallucination-guard/setup.sh -->" >> "$RULES"
    grep -v '^v[0-9]' "$AHG_BLOCK_SRC" | grep -v '^---$' | grep -v '^# AGENT RULES' | grep -v '^> Copied to project' >> "$RULES"
    echo "" >> "$RULES"
    echo "<!-- AHG:END -->" >> "$RULES"
    ok "AGENT_RULES.md created with AHG rules"
fi

# ---- 2. worklog.md ----
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

# ---- 3. Pre-commit hook ----
mkdir -p "$HOOK_DIR"

if [ -f "$HOOK_DIR/pre-commit" ]; then
    EXPECTED_MARKER="anti-hallucination-guard"
    if grep -q "$EXPECTED_MARKER" "$HOOK_DIR/pre-commit" 2>/dev/null; then
        # Our hook is already there — update it, but preserve any appended sections
        # (like cascade-guard checks or verify-docs)
        # Find where our hook ends (before any appended sections)
        # Strategy: replace only the AHG portion, keep the rest
        warn "pre-commit hook already installed (ours) -- updating"
        cp "$HOOK_SRC" "$HOOK_DIR/pre-commit"
        chmod +x "$HOOK_DIR/pre-commit"
        ok "pre-commit hook updated"
    else
        # Foreign hook exists — append our checks instead of overwriting
        warn "pre-commit hook already exists (foreign) -- appending AHG checks"
        cat >> "$HOOK_DIR/pre-commit" << 'PRECOMMIT_APPEND'

# ---- anti-hallucination-guard: worklog checks ----
# anti-hallucination-guard
WORKLOG="worklog.md"
MAX_AGE=600  # 10 minutes

if [ ! -f "$WORKLOG" ]; then
    echo ""
    echo "  ERROR: worklog.md not found!"
    echo "  Create the file and describe the work done."
    echo ""
    exit 1
fi

LAST_MODIFIED=$(stat -c %Y "$WORKLOG" 2>/dev/null || stat -f %m "$WORKLOG" 2>/dev/null)
NOW=$(date +%s)
DIFF=$((NOW - LAST_MODIFIED))

if [ "$DIFF" -gt "$MAX_AGE" ]; then
    echo ""
    echo "  ERROR: worklog.md not updated for over $((MAX_AGE/60)) minutes!"
    echo "  Last update: $((DIFF/60)) min ago"
    echo "  Update worklog.md before committing."
    echo ""
    exit 1
fi

SIZE=$(wc -c < "$WORKLOG")
if [ "$SIZE" -lt 50 ]; then
    echo ""
    echo "  ERROR: worklog.md is empty (less than 50 bytes)!"
    echo "  Describe the work done."
    echo ""
    exit 1
fi

BLOCK_COUNT=$(grep -c '^---$' "$WORKLOG" 2>/dev/null)
if [ "$BLOCK_COUNT" -lt 2 ]; then
    echo ""
    echo "  ERROR: worklog.md does not contain standard blocks!"
    echo "  Format: --- / Task ID / Work Log / Stage Summary / ---"
    echo ""
    exit 1
fi

echo "  OK: worklog.md is up to date ($BLOCK_COUNT blocks)"
PRECOMMIT_APPEND
        ok "AHG checks appended to existing pre-commit hook"
    fi
else
    cp "$HOOK_SRC" "$HOOK_DIR/pre-commit"
    chmod +x "$HOOK_DIR/pre-commit"
    ok "pre-commit hook installed"
fi

# ---- 4. Pre-push hook (module protection) ----
# Smart merge: if a pre-push hook exists (e.g. from cascade-guard),
# append our validate check instead of skipping.
if [ -f "$HOOK_DIR/pre-push" ]; then
    if grep -q "anti-hallucination-guard" "$HOOK_DIR/pre-push" 2>/dev/null; then
        ok "pre-push hook already contains AHG validation"
    else
        # Append our validate check to the existing pre-push hook
        cat >> "$HOOK_DIR/pre-push" << 'PUSH_APPEND'

# ---- anti-hallucination-guard: validate module purity ----
AHG_VALIDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$AHG_VALIDATE_DIR/scripts/validate.sh" ]; then
    if ! bash "$AHG_VALIDATE_DIR/scripts/validate.sh"; then
        echo ""
        echo "  pre-push: PUSH BLOCKED. AHG found foreign files."
        echo ""
        exit 1
    fi
fi
PUSH_APPEND
        ok "AHG validation appended to existing pre-push hook"
    fi
else
    cp "$PUSH_HOOK_SRC" "$HOOK_DIR/pre-push"
    chmod +x "$HOOK_DIR/pre-push" 2>/dev/null || true
    ok "pre-push hook installed"
fi

# ---- 5. Monitoring scripts ----
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

# ---- 6. Skill (if skills/ exists in project) ----
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

# ---- 7. verify-docs (optional, requires bun) ----
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

# ---- 8. Cascade-guard integration ----
CG_DIR=""
# Strategy: check common locations, then scan .gitmodules, then use find
if [ -d "cascade-guard" ]; then
    CG_DIR="cascade-guard"
elif [ -d "scripts/cascade-guard" ]; then
    CG_DIR="scripts/cascade-guard"
elif [ -f ".gitmodules" ]; then
    CG_DIR=$(git config -f .gitmodules --get-regexp 'path' 2>/dev/null | grep -i 'cascade.guard' | awk '{print $2}' | head -1 || true)
    if [ -n "$CG_DIR" ] && [ ! -d "$CG_DIR" ]; then
        git submodule update --init "$CG_DIR" 2>/dev/null || true
    fi
fi
if [ -z "$CG_DIR" ] || [ ! -d "$CG_DIR" ]; then
    CG_DIR=$(find . -maxdepth 4 -type d -name "cascade-guard" ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | head -1 || true)
fi

if [ -n "$CG_DIR" ] && [ -d "$CG_DIR" ]; then
    info "Cascade-guard detected at $CG_DIR — integrating"

    # Add cascade-state.json freshness check to pre-commit hook
    if [ -f ".git/hooks/pre-commit" ]; then
        if ! grep -q "cascade-state.json" .git/hooks/pre-commit 2>/dev/null; then
            cat >> .git/hooks/pre-commit << 'CASCADE_HOOK'

# ---- Cascade-guard: check cascade-state.json freshness ----
if [ -f "cascade-state.json" ]; then
    if ! jq empty cascade-state.json 2>/dev/null; then
        echo "ERROR: cascade-state.json is not valid JSON"
        exit 1
    fi
    IN_PROGRESS=$(jq '[.phases[].tasks[] | select(.status == "in_progress")] | length' cascade-state.json 2>/dev/null || echo "0")
    PENDING=$(jq '[.phases[].tasks[] | select(.status == "pending")] | length' cascade-state.json 2>/dev/null || echo "0")
    if [ "$IN_PROGRESS" = "0" ] && [ "$PENDING" != "0" ]; then
        echo "WARN: No tasks in_progress but $PENDING pending. Did you forget to start a task?"
    fi
fi
CASCADE_HOOK
            ok "Cascade checks added to pre-commit hook"
        else
            ok "Cascade checks already in pre-commit hook"
        fi
    fi

    # AHG rules (1-6) and Cascade rules (C-1 to C-9) coexist in AGENT_RULES.md
    ok "AHG rules (1-6) and Cascade rules (C-1 to C-9) coexist in AGENT_RULES.md"
    ok "No duplication -- different namespaces (Rule N vs C-N) and separate markers"
else
    info "No Cascade-guard detected. Standalone mode."
    info "To add: git submodule add https://github.com/stsgs1980/Cascade-guard.git"
fi

# ---- 9. Git staging ----
cd "$PROJECT_ROOT"
git add AGENT_RULES.md worklog.md .git/hooks/pre-commit .git/hooks/pre-push scripts/ tools/ 2>/dev/null || true
ok "Files added to git staging"

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
if command -v bun &>/dev/null && [ -d "$VERIFY_DOCS_DIR" ]; then
echo "  tools/verify-docs       -- README number checker (bun)"
echo "  pre-commit hook         -- + verify-docs (if verify-docs.json exists)"
fi
echo ""
echo "Rule namespacing in AGENT_RULES.md:"
echo "  Rule 1-6     = Anti-hallucination (worklog, no-loops, honest reporting)"
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

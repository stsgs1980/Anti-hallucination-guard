#!/usr/bin/env bash
# setup/07-install-verify-docs.sh
# Installs verify-docs tool (optional, requires bun).
# Also adds verify-docs check to pre-commit hook if verify-docs.json exists.

VERIFY_DOCS_DIR="$MODULE_ROOT/tools/verify-docs"
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

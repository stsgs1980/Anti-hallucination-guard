#!/usr/bin/env bash
# setup/04-install-pre-push-hook.sh
# Installs pre-push hook for module purity protection.
# Smart merge: if a pre-push hook exists (e.g. from cascade-guard),
# append our validate check instead of skipping.

if [ -f "$HOOK_DIR/pre-push" ]; then
    if grep -q "anti-hallucination-guard" "$HOOK_DIR/pre-push" 2>/dev/null; then
        ok "pre-push hook already contains AHG validation"
    else
        # Append our validate check to the existing pre-push hook
        cat >> "$HOOK_DIR/pre-push" << 'PUSH_APPEND'

# ---- anti-hallucination-guard: push validation ----
# In AHG module repo: runs validate.sh (purity check).
# In target project: runs ahg.sh verify (doc consistency).
AHG_MODULE_DIR="$(git rev-parse --show-toplevel)"
if [ -f "$AHG_MODULE_DIR/setup.sh" ] && [ -f "$AHG_MODULE_DIR/.git-hooks/pre-commit" ]; then
    AHG_VALIDATE_DIR="$AHG_MODULE_DIR"
    if [ -f "$AHG_VALIDATE_DIR/scripts/validate.sh" ]; then
        if ! bash "$AHG_VALIDATE_DIR/scripts/validate.sh"; then
            echo ""
            echo "  pre-push: PUSH BLOCKED. AHG found foreign files."
            echo ""
            exit 1
        fi
    fi
else
    AHG_SH="$AHG_MODULE_DIR/scripts/ahg.sh"
    if [ -f "$AHG_SH" ] && command -v bun &>/dev/null; then
        echo "  pre-push: Running AHG verify..."
        if ! bash "$AHG_SH" verify --ci 2>&1; then
            echo ""
            echo "  pre-push: PUSH BLOCKED. Doc consistency check failed."
            echo ""
            exit 1
        fi
        echo "  pre-push: AHG verify passed."
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

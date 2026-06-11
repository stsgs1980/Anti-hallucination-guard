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

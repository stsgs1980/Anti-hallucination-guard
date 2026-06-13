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
# NOTE: We do NOT use `git rev-parse --show-toplevel` for context detection
# because in submodule scenarios it resolves to the parent repo, not AHG.
_AHG_GIT_ROOT="$(git rev-parse --show-toplevel)"
_AHG_MODULE_DIR=""
# Check for AHG submodule via .gitmodules
if [ -f "$_AHG_GIT_ROOT/.gitmodules" ]; then
    _ahg_sp=$(git -C "$_AHG_GIT_ROOT" config -f .gitmodules --get-regexp 'path' 2>/dev/null \
        | grep -i 'anti.hallucination' | awk '{print $2}' | head -1 || true)
    if [ -n "$_ahg_sp" ] && [ -f "$_AHG_GIT_ROOT/$_ahg_sp/setup.sh" ]; then
        _AHG_MODULE_DIR="$_AHG_GIT_ROOT/$_ahg_sp"
    fi
fi
# Check common locations
if [ -z "$_AHG_MODULE_DIR" ]; then
    for _ahg_c in "$_AHG_GIT_ROOT/anti-hallucination-guard" "$_AHG_GIT_ROOT/vendor/anti-hallucination-guard"; do
        if [ -d "$_ahg_c" ] && [ -f "$_ahg_c/setup.sh" ]; then
            _AHG_MODULE_DIR="$_ahg_c"; break
        fi
    done
fi
# Check if we ARE the AHG module repo itself
if [ -z "$_AHG_MODULE_DIR" ] && [ -f "$_AHG_GIT_ROOT/setup.sh" ] && [ -f "$_AHG_GIT_ROOT/AGENT_RULES.md" ]; then
    _AHG_MODULE_DIR="$_AHG_GIT_ROOT"
fi
if [ -n "$_AHG_MODULE_DIR" ] && [ "$_AHG_MODULE_DIR" = "$_AHG_GIT_ROOT" ]; then
    # AHG module repo -- run purity check
    if [ -f "$_AHG_MODULE_DIR/scripts/validate.sh" ]; then
        if ! bash "$_AHG_MODULE_DIR/scripts/validate.sh"; then
            echo ""
            echo "  pre-push: PUSH BLOCKED. AHG found foreign files."
            echo ""
            exit 1
        fi
    fi
elif [ -n "$_AHG_MODULE_DIR" ]; then
    # Consumer project -- run doc consistency check
    # IMPORTANT: prefer the submodule's ahg.sh over the deployed one,
    # because the deployed ahg.sh can't find verify-docs (VD_CLI bug).
    _AHG_SH="$_AHG_MODULE_DIR/scripts/ahg.sh"
    [ ! -f "$_AHG_SH" ] && _AHG_SH="$_AHG_GIT_ROOT/scripts/ahg.sh"
    if [ -f "$_AHG_SH" ] && command -v bun &>/dev/null; then
        echo "  pre-push: Running AHG verify..."
        if ! bash "$_AHG_SH" verify --ci 2>&1; then
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

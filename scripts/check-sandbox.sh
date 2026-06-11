#!/bin/bash
# anti-hallucination-guard / check-sandbox.sh
# Standalone Z.ai Sandbox verification script.
# Run: bash check-sandbox.sh
# Checks that the sandbox environment is real and correctly configured.
# Complements check-agent.sh with deeper sandbox-specific checks.

set -euo pipefail

SANDBOX_ROOT="/home/z/my-project"
ERRORS=0
WARNINGS=0

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

echo "=== check-sandbox.sh: Z.ai Sandbox verification ==="
echo "[$(timestamp)] Sandbox root: $SANDBOX_ROOT"
echo ""

# Check 1: Is this actually Z.ai Sandbox?
echo "--- Check 1: Sandbox environment ---"
if [ -d "$SANDBOX_ROOT/.zscripts" ]; then
    echo "[+] OK: .zscripts/ exists -- we are in Z.ai Sandbox"
else
    echo "[-] SKIP: .zscripts/ not found -- not Z.ai Sandbox, skipping remaining checks"
    exit 0
fi

# Check 2: Dev server management
echo ""
echo "--- Check 2: Dev server ---"
if pgrep -f ".zscripts/dev.sh" >/dev/null 2>&1; then
    # Extract PID for reporting
    DEV_PID=$(pgrep -f ".zscripts/dev.sh" | head -1)
    echo "[+] OK: .zscripts/dev.sh running (PID $DEV_PID)"

    # Verify PID file exists and matches
    PID_FILE="$SANDBOX_ROOT/.zscripts/dev.pid"
    if [ -f "$PID_FILE" ]; then
        FILE_PID=$(cat "$PID_FILE")
        if [ "$FILE_PID" = "$DEV_PID" ]; then
            echo "[+] OK: dev.pid ($FILE_PID) matches running process"
        else
            echo "[!] WARN: dev.pid ($FILE_PID) != running PID ($DEV_PID) -- stale pid file?"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
else
    echo "[-] FAIL: .zscripts/dev.sh not running!"
    echo "    Fix: curl https://z-cdn.chatglm.cn/fullstack/init-fullstack_1775040338514.sh | bash"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: Port 3000 response
echo ""
echo "--- Check 3: HTTP response ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/ 2>/dev/null || echo "000")
case "$HTTP_CODE" in
    200)
        echo "[+] OK: HTTP 200 from localhost:3000"
        ;;
    000)
        echo "[-] FAIL: No response from localhost:3000 (server down?)"
        ERRORS=$((ERRORS + 1))
        ;;
    500)
        echo "[-] FAIL: HTTP 500 -- broken code, NOT a working server!"
        echo "    Check dev.log for compilation errors"
        ERRORS=$((ERRORS + 1))
        ;;
    *)
        echo "[!] WARN: HTTP $HTTP_CODE (expected 200)"
        WARNINGS=$((WARNINGS + 1))
        ;;
esac

# Check 4: Code location (root vs subfolder)
echo ""
echo "--- Check 4: Code location ---"
if [ -f "$SANDBOX_ROOT/src/app/page.tsx" ]; then
    echo "[+] OK: src/app/page.tsx in sandbox root"
elif [ -f "$SANDBOX_ROOT/src/app/layout.tsx" ]; then
    echo "[+] OK: src/app/layout.tsx in sandbox root (Next.js app detected)"
else
    echo "[-] FAIL: No Next.js entry point found in $SANDBOX_ROOT/src/app/"
    echo "    Agent may have cloned to /tmp/ or a subfolder instead of sandbox root"
    ERRORS=$((ERRORS + 1))
fi

# Check 5: Stale subfolder clones (common anti-hallucination pattern)
echo ""
echo "--- Check 5: Stale clones ---"
SUBFOLDER_CLONES=0
for DIR in /tmp/*/src/app/page.tsx; do
    if [ -f "$DIR" ]; then
        PARENT=$(dirname "$(dirname "$(dirname "$DIR")")")
        echo "[!] WARN: Found clone at $PARENT -- code here is NOT served by dev server"
        SUBFOLDER_CLONES=$((SUBFOLDER_CLONES + 1))
    fi
done 2>/dev/null

# Also check for repos cloned directly inside sandbox root as subfolders
for DIR in "$SANDBOX_ROOT"/*/src/app/page.tsx; do
    if [ -f "$DIR" ]; then
        PARENT=$(dirname "$(dirname "$(dirname "$DIR")")")
        # Skip the actual root src/app (already checked)
        if [ "$PARENT" != "$SANDBOX_ROOT" ]; then
            echo "[!] WARN: Found clone at $PARENT inside sandbox -- code NOT served"
            SUBFOLDER_CLONES=$((SUBFOLDER_CLONES + 1))
        fi
    fi
done 2>/dev/null

if [ "$SUBFOLDER_CLONES" -eq 0 ]; then
    echo "[+] OK: No stale subfolder clones detected"
else
    WARNINGS=$((WARNINGS + SUBFOLDER_CLONES))
fi

# Check 6: dev.log analysis
echo ""
echo "--- Check 6: dev.log analysis ---"
DEV_LOG="$SANDBOX_ROOT/dev.log"
if [ -f "$DEV_LOG" ]; then
    LOG_200=$(grep -c 'GET / 200' "$DEV_LOG" 2>/dev/null || true)
    LOG_500=$(grep -c 'GET / 500' "$DEV_LOG" 2>/dev/null || true)
    LOG_COMPILE=$(grep -ci 'compiled\|compilation' "$DEV_LOG" 2>/dev/null || true)
    LOG_ERROR=$(grep -ci 'error\|unhandled\|uncaught' "$DEV_LOG" 2>/dev/null || true)

    # Normalize: grep -c may return empty or multi-line on binary files; default to 0
    LOG_200=$(echo "$LOG_200" | tr -d '[:space:]' | grep -o '[0-9]*' | head -1)
    LOG_500=$(echo "$LOG_500" | tr -d '[:space:]' | grep -o '[0-9]*' | head -1)
    LOG_COMPILE=$(echo "$LOG_COMPILE" | tr -d '[:space:]' | grep -o '[0-9]*' | head -1)
    LOG_ERROR=$(echo "$LOG_ERROR" | tr -d '[:space:]' | grep -o '[0-9]*' | head -1)
    LOG_200=${LOG_200:-0}
    LOG_500=${LOG_500:-0}
    LOG_COMPILE=${LOG_COMPILE:-0}
    LOG_ERROR=${LOG_ERROR:-0}

    echo "    GET / 200 count: $LOG_200"
    echo "    GET / 500 count: $LOG_500"
    echo "    Compilation msgs: $LOG_COMPILE"
    echo "    Error msgs:      $LOG_ERROR"

    if [ "$LOG_500" -gt "$LOG_200" ]; then
        echo "[-] FAIL: More 500s than 200s in dev.log -- server is broken!"
        ERRORS=$((ERRORS + 1))
    elif [ "$LOG_ERROR" -gt 5 ]; then
        echo "[!] WARN: Many errors in dev.log ($LOG_ERROR) -- investigate"
        WARNINGS=$((WARNINGS + 1))
    else
        echo "[+] OK: dev.log looks healthy"
    fi
else
    echo "[!] WARN: dev.log not found -- server may not have been started yet"
    WARNINGS=$((WARNINGS + 1))
fi

# Summary
echo ""
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "[$(timestamp)] ALL CHECKS PASSED. Sandbox is healthy."
    exit 0
else
    echo "[$(timestamp)] Errors: $ERRORS, Warnings: $WARNINGS"
    if [ "$ERRORS" -gt 0 ]; then
        echo ""
        echo "CRITICAL issues found. Fix before continuing work:"
        echo "  1. If dev server is down: curl https://z-cdn.chatglm.cn/fullstack/init-fullstack_1775040338514.sh | bash"
        echo "  2. If code in wrong location: rsync -av --exclude='.git' /tmp/my-repo/ /home/z/my-project/"
        echo "  3. If 500 errors: check dev.log for compilation errors"
    fi
    exit 1
fi

#!/bin/bash
# anti-hallucination-guard / check-agent.sh
# Agent activity monitor.
# Run: manually or via cron every 10 minutes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Resolve PROJECT_ROOT: if AHG is a submodule, git toplevel = consumer root
PROJECT_ROOT="$(git -C "$MODULE_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$MODULE_ROOT")"
WORKLOG="$PROJECT_ROOT/worklog.md"
MAX_IDLE=900  # 15 minutes idle = alert
LOG="$PROJECT_ROOT/download/agent-monitor.log"

mkdir -p "$(dirname "$LOG")"

# Cross-platform stat: Linux uses -c, macOS uses -f
get_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

# Check 1: worklog exists?
if [ ! -f "$WORKLOG" ]; then
    echo "[$(timestamp)] ERROR: worklog.md deleted or not created!" >> "$LOG"
    exit 1
fi

# Check 2: worklog fresh?
LAST=$(get_mtime "$WORKLOG")
NOW=$(date +%s)
IDLE=$((NOW - LAST))

if [ "$IDLE" -gt "$MAX_IDLE" ]; then
    echo "[$(timestamp)] ALERT: worklog not updated for $((IDLE/60)) min" >> "$LOG"
    echo "[$(timestamp)] Possible: agent stuck or faking activity" >> "$LOG"
fi

# Check 3: git activity?
LAST_COMMIT=$(git -C "$PROJECT_ROOT" log -1 --format=%ct 2>/dev/null)
if [ -n "$LAST_COMMIT" ]; then
    COMMIT_AGE=$((NOW - LAST_COMMIT))
    if [ "$COMMIT_AGE" -gt 1800 ]; then
        echo "[$(timestamp)] ALERT: no commits for $((COMMIT_AGE/60)) min" >> "$LOG"
    fi
fi

# Check 4: count blocks in worklog
BLOCKS=$(grep -c '^---$' "$WORKLOG" 2>/dev/null)
echo "[$(timestamp)] Status: worklog=$BLOCKS blocks, idle=$((IDLE/60))min" >> "$LOG"

# --- Sandbox verification checks (Rule 8) ---
# Auto-detect sandbox root: prefer Z.AI sandbox, fallback to PROJECT_ROOT
SANDBOX_ROOT=""
if [ -d "/home/z/my-project/.zscripts" ]; then
    SANDBOX_ROOT="/home/z/my-project"
fi

if [ -d "$SANDBOX_ROOT/.zscripts" ]; then
    # Check 5: dev server managed by sandbox (not manual next dev)
    if pgrep -f ".zscripts/dev.sh" >/dev/null 2>&1; then
        echo "[$(timestamp)] SANDBOX OK: dev server via .zscripts/dev.sh" >> "$LOG"
    else
        echo "[$(timestamp)] SANDBOX ALERT: .zscripts/dev.sh not running!" >> "$LOG"
        echo "[$(timestamp)]   -> Agent may have started server manually or not at all" >> "$LOG"
    fi

    # Check 6: code served from correct location (root, not subfolder)
    if [ -f "$SANDBOX_ROOT/src/app/page.tsx" ]; then
        echo "[$(timestamp)] SANDBOX OK: code in /home/z/my-project/ root" >> "$LOG"
    else
        echo "[$(timestamp)] SANDBOX ALERT: src/app/page.tsx NOT in sandbox root!" >> "$LOG"
        echo "[$(timestamp)]   -> Agent may be editing in /tmp/ or wrong subfolder" >> "$LOG"
    fi

    # Check 7: dev server actually returns 200
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "[$(timestamp)] SANDBOX OK: dev server returns 200" >> "$LOG"
    else
        echo "[$(timestamp)] SANDBOX ALERT: dev server returns HTTP $HTTP_CODE (expected 200)" >> "$LOG"
        echo "[$(timestamp)]   -> HMR 500 or server down; code may be broken" >> "$LOG"
    fi

    # Check 8: dev.log contains real 200 responses (not just 500 errors)
    DEV_LOG="$SANDBOX_ROOT/dev.log"
    if [ -f "$DEV_LOG" ]; then
        LOG_200=$(grep -c 'GET / 200' "$DEV_LOG" 2>/dev/null || true)
        LOG_500=$(grep -c 'GET / 500' "$DEV_LOG" 2>/dev/null || true)
        LOG_200=$(echo "$LOG_200" | tr -d '[:space:]' | grep -o '[0-9]*' | head -1)
        LOG_500=$(echo "$LOG_500" | tr -d '[:space:]' | grep -o '[0-9]*' | head -1)
        LOG_200=${LOG_200:-0}
        LOG_500=${LOG_500:-0}
        echo "[$(timestamp)] SANDBOX: dev.log has $LOG_200 x GET / 200, $LOG_500 x GET / 500" >> "$LOG"
        if [ "$LOG_500" -gt "$LOG_200" ]; then
            echo "[$(timestamp)] SANDBOX ALERT: more 500s than 200s in dev.log!" >> "$LOG"
        fi
    fi
fi

exit 0

#!/bin/bash
# anti-hallucination-guard / check-agent.sh
# Agent activity monitor.
# Run: manually or via cron every 10 minutes.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKLOG="$PROJECT_ROOT/worklog.md"
MAX_IDLE=900  # 15 minutes idle = alert
LOG="$PROJECT_ROOT/download/agent-monitor.log"

mkdir -p "$(dirname "$LOG")"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

# Check 1: worklog exists?
if [ ! -f "$WORKLOG" ]; then
    echo "[$(timestamp)] ERROR: worklog.md deleted or not created!" >> "$LOG"
    exit 1
fi

# Check 2: worklog fresh?
LAST=$(stat -c %Y "$WORKLOG" 2>/dev/null)
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

exit 0

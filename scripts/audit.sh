#!/bin/bash
# anti-hallucination-guard / audit.sh
# Post-session agent audit.
# Run: bash scripts/audit.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Resolve PROJECT_ROOT: if AHG is a submodule, git toplevel = consumer root
PROJECT_ROOT="$(git -C "$MODULE_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$MODULE_ROOT")"
WORKLOG="$PROJECT_ROOT/worklog.md"
REPORT="$PROJECT_ROOT/download/audit-report.txt"
SCORE=0
# Sum of every weight below: 20 + 15 + 15 + 15 + 15 + 10 = 90.
# A maximum that cannot be reached makes every result read as a shortfall.
MAX_SCORE=90
# Only the recent part of the history describes the session being audited.
COMMIT_WINDOW="${AUDIT_COMMIT_WINDOW:-50}"

mkdir -p "$(dirname "$REPORT")"

# Cross-platform stat: Linux uses -c, macOS uses -f
get_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

echo "=== SESSION AUDIT ===" > "$REPORT"
echo "Time: $(date)" >> "$REPORT"
echo "Project: $PROJECT_ROOT" >> "$REPORT"
echo "" >> "$REPORT"

# 1. Worklog exists?
if [ -f "$WORKLOG" ]; then
    BLOCKS=$(grep -c '^---$' "$WORKLOG" 2>/dev/null)
    echo "[+] worklog.md: OK (${BLOCKS} blocks)" >> "$REPORT"
    SCORE=$((SCORE + 20))
else
    echo "[-] worklog.md: NOT FOUND -- agent did not maintain documentation" >> "$REPORT"
fi

# 2. Commit count (bounded window, not the whole history of the project)
COMMITS=$(git -C "$PROJECT_ROOT" rev-list --count -n "$COMMIT_WINDOW" HEAD 2>/dev/null || echo 0)
echo "[+] Commits in last $COMMIT_WINDOW: $COMMITS" >> "$REPORT"
if [ "$COMMITS" -gt 3 ]; then
    SCORE=$((SCORE + 15))
fi

# 3. Changed files
CHANGED=$(git -C "$PROJECT_ROOT" diff --name-only HEAD~3 2>/dev/null)
echo "[+] Changed files (last 3 commits):" >> "$REPORT"
echo "$CHANGED" | head -20 >> "$REPORT"
if [ -n "$CHANGED" ]; then
    SCORE=$((SCORE + 15))
fi

# 4. Duplicate commit messages (sign of loops)
# `--oneline` prefixes each line with the commit hash, so no two lines are ever
# equal and `uniq -d` could never report anything. Compare subjects only.
DUPS=$(git -C "$PROJECT_ROOT" log --pretty=%s -n "$COMMIT_WINDOW" 2>/dev/null | sort | uniq -d | head -5)
if [ -n "$DUPS" ]; then
    echo "[!] Repeated commit messages (possible loop):" >> "$REPORT"
    echo "$DUPS" >> "$REPORT"
else
    echo "[+] No repeated commit messages in window" >> "$REPORT"
    SCORE=$((SCORE + 15))
fi

# 5. Worklog size
if [ -f "$WORKLOG" ]; then
    SIZE=$(wc -c < "$WORKLOG")
    LINES=$(wc -l < "$WORKLOG")
    echo "[+] Worklog size: ${SIZE} bytes, ${LINES} lines" >> "$REPORT"
    if [ "$LINES" -gt 20 ]; then
        SCORE=$((SCORE + 15))
    fi
fi

# 6. Last activity
if [ -f "$WORKLOG" ]; then
    LAST=$(get_mtime "$WORKLOG")
    NOW=$(date +%s)
    MIN_AGO=$(( (NOW - LAST) / 60 ))
    echo "[+] Last worklog update: ${MIN_AGO} min ago" >> "$REPORT"
fi

# 7. AGENT_RULES.md exists?
if [ -f "$PROJECT_ROOT/AGENT_RULES.md" ]; then
    echo "[+] AGENT_RULES.md: OK" >> "$REPORT"
    SCORE=$((SCORE + 10))
else
    echo "[-] AGENT_RULES.md: MISSING" >> "$REPORT"
fi

# Result
echo "" >> "$REPORT"
echo "==============================" >> "$REPORT"
echo "SCORE: ${SCORE}/${MAX_SCORE}" >> "$REPORT"
echo "" >> "$REPORT"
echo "This score measures process signals only: worklog present, recent and" >> "$REPORT"
echo "structured, commits made, no repeated commit messages. It is not evidence" >> "$REPORT"
echo "that the work is correct, and a low score is not evidence of dishonesty." >> "$REPORT"
if [ "$SCORE" -ge 70 ]; then
    echo "VERDICT: Process signals present" >> "$REPORT"
elif [ "$SCORE" -ge 40 ]; then
    echo "VERDICT: Process signals incomplete" >> "$REPORT"
else
    echo "VERDICT: Process signals missing -- nothing verifiable was documented" >> "$REPORT"
fi

cat "$REPORT"

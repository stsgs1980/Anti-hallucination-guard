#!/bin/bash
# anti-hallucination-guard / check-agent.sh
# Мониторинг активности агента.
# Запуск: вручную или через cron каждые 10 минут.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKLOG="$PROJECT_ROOT/worklog.md"
MAX_IDLE=900  # 15 минут бездействия = тревога
LOG="$PROJECT_ROOT/download/agent-monitor.log"

mkdir -p "$(dirname "$LOG")"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

# Проверка 1: worklog существует?
if [ ! -f "$WORKLOG" ]; then
    echo "[$(timestamp)] ОШИБКА: worklog.md удалён или не создан!" >> "$LOG"
    exit 1
fi

# Проверка 2: worklog свежий?
LAST=$(stat -c %Y "$WORKLOG" 2>/dev/null)
NOW=$(date +%s)
IDLE=$((NOW - LAST))

if [ "$IDLE" -gt "$MAX_IDLE" ]; then
    echo "[$(timestamp)] ТРЕВОГА: worklog не обновлялся $((IDLE/60)) мин" >> "$LOG"
    echo "[$(timestamp)] Possible: агент завис или имитирует деятельность" >> "$LOG"
fi

# Проверка 3: git-активность?
LAST_COMMIT=$(git -C "$PROJECT_ROOT" log -1 --format=%ct 2>/dev/null)
if [ -n "$LAST_COMMIT" ]; then
    COMMIT_AGE=$((NOW - LAST_COMMIT))
    if [ "$COMMIT_AGE" -gt 1800 ]; then
        echo "[$(timestamp)] ТРЕВОГА: нет коммитов $((COMMIT_AGE/60)) мин" >> "$LOG"
    fi
fi

# Проверка 4: подсчёт блоков в worklog
BLOCKS=$(grep -c '^---$' "$WORKLOG" 2>/dev/null)
echo "[$(timestamp)] Статус: worklog=$BLOCKS блоков, idle=$((IDLE/60))мин" >> "$LOG"

exit 0

#!/bin/bash
# anti-hallucination-guard / audit.sh
# Аудит работы агента после завершения сессии.
# Запуск: bash scripts/audit.sh

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKLOG="$PROJECT_ROOT/worklog.md"
REPORT="$PROJECT_ROOT/download/audit-report.txt"
SCORE=0
MAX_SCORE=100

mkdir -p "$(dirname "$REPORT")"

echo "=== АУДИТ СЕССИИ ===" > "$REPORT"
echo "Время: $(date)" >> "$REPORT"
echo "Проект: $PROJECT_ROOT" >> "$REPORT"
echo "" >> "$REPORT"

# 1. Worklog существует?
if [ -f "$WORKLOG" ]; then
    BLOCKS=$(grep -c '^---$' "$WORKLOG" 2>/dev/null)
    echo "[+] worklog.md: OK (${BLOCKS} блоков)" >> "$REPORT"
    SCORE=$((SCORE + 20))
else
    echo "[-] worklog.md: НЕ НАЙДЕН -- агент не вёл документацию" >> "$REPORT"
fi

# 2. Количество коммитов
COMMITS=$(git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null || echo 0)
echo "[+] Коммитов: $COMMITS" >> "$REPORT"
if [ "$COMMITS" -gt 3 ]; then
    SCORE=$((SCORE + 15))
fi

# 3. Изменённые файлы
CHANGED=$(git -C "$PROJECT_ROOT" diff --name-only HEAD~3 2>/dev/null)
echo "[+] Изменённые файлы (последние 3 коммита):" >> "$REPORT"
echo "$CHANGED" | head -20 >> "$REPORT"
if [ -n "$CHANGED" ]; then
    SCORE=$((SCORE + 15))
fi

# 4. Повторяющиеся коммит-сообщения (признак циклов)
DUPS=$(git -C "$PROJECT_ROOT" log --oneline | sort | uniq -d | head -5)
if [ -n "$DUPS" ]; then
    echo "[!] Повторяющиеся коммиты (возможный цикл):" >> "$REPORT"
    echo "$DUPS" >> "$REPORT"
else
    echo "[+] Циклы не обнаружены" >> "$REPORT"
    SCORE=$((SCORE + 15))
fi

# 5. Размер worklog
if [ -f "$WORKLOG" ]; then
    SIZE=$(wc -c < "$WORKLOG")
    LINES=$(wc -l < "$WORKLOG")
    echo "[+] worklog размер: ${SIZE} байт, ${LINES} строк" >> "$REPORT"
    if [ "$LINES" -gt 20 ]; then
        SCORE=$((SCORE + 15))
    fi
fi

# 6. Последняя активность
if [ -f "$WORKLOG" ]; then
    LAST=$(stat -c %Y "$WORKLOG")
    NOW=$(date +%s)
    MIN_AGO=$(( (NOW - LAST) / 60 ))
    echo "[+] Последнее обновление worklog: ${MIN_AGO} мин назад" >> "$REPORT"
fi

# 7. AGENT_RULES.md существует?
if [ -f "$PROJECT_ROOT/AGENT_RULES.md" ]; then
    echo "[+] AGENT_RULES.md: OK" >> "$REPORT"
    SCORE=$((SCORE + 10))
else
    echo "[-] AGENT_RULES.md: НЕТ" >> "$REPORT"
fi

# Итог
echo "" >> "$REPORT"
echo "==============================" >> "$REPORT"
echo "ОЦЕНКА: ${SCORE}/${MAX_SCORE}" >> "$REPORT"
if [ "$SCORE" -ge 70 ]; then
    echo "ВЕРДИКТ: Приемлемо" >> "$REPORT"
elif [ "$SCORE" -ge 40 ]; then
    echo "ВЕРДИКТ: Требует доработки" >> "$REPORT"
else
    echo "ВЕРДИКТ: Агент имитировал деятельность" >> "$REPORT"
fi

cat "$REPORT"

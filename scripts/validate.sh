#!/bin/bash
# anti-hallucination-guard / validate.sh
# Проверяет, что репозиторий содержит только файлы модуля.
# Запуск: bash validate.sh
# Можно использовать как pre-push hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Список разрешённых путей (whitelist)
ALLOWED=(
    "setup.sh"
    "AGENT_RULES.md"
    "README.md"
    ".gitignore"
    ".git-hooks/"
    ".git-hooks/pre-commit"
    "scripts/"
    "scripts/check-agent.sh"
    "scripts/audit.sh"
    "skills/"
    "skills/anti-hallucination-guard/"
    "skills/anti-hallucination-guard/SKILL.md"
    ".git-hooks/pre-push"
)

# Список запрещённых паттернов
FORBIDDEN_PATTERNS=(
    "*.env"
    "*.log"
    "*.tmp"
    "node_modules/"
    ".next/"
    "upload/"
    "download/"
    "src/"
    "app/"
    "public/"
    "package.json"
    "package-lock.json"
    "tsconfig.json"
    ".git/modules/"
)

ERRORS=0

echo "=== validate.sh: проверка чистоты репозитория ==="
echo ""

# Проверяем, что все tracked-файлы допустимы
TRACKED_FILES=$(git -C "$SCRIPT_DIR" ls-files)
for FILE in $TRACKED_FILES; do
    ALLOWED_FLAG=0
    for PATTERN in "${ALLOWED[@]}"; do
        # Проверяем, начинается ли файл с разрешённого пути
        case "$FILE" in
            "$PATTERN"*) ALLOWED_FLAG=1 ;;
        esac
    done
    if [ "$ALLOWED_FLAG" -eq 0 ]; then
        echo "[-] ЗАПРЕЩЁННЫЙ ФАЙЛ: $FILE"
        echo "    Этот файл не должен быть в репозитории модуля."
        echo "    Модуль содержит только: setup.sh, AGENT_RULES.md, .git-hooks/, scripts/, skills/, README.md, .gitignore"
        ERRORS=$((ERRORS + 1))
    fi
done

# Проверяем, что нет запрещённых паттернов в tracked-файлах
for FILE in $TRACKED_FILES; do
    for PATTERN in "${FORBIDDEN_PATTERNS[@]}"; do
        case "$FILE" in
            *"$PATTERN"*)
                echo "[-] ЗАПРЕЩЁННЫЙ ПАТТЕРН: $FILE (совпадение: $PATTERN)"
                ERRORS=$((ERRORS + 1))
                ;;
        esac
    done
done

# Проверяем, что все разрешённые файлы существуют
for ITEM in "${ALLOWED[@]}"; do
    if [ -e "$SCRIPT_DIR/$ITEM" ]; then
        echo "[+] $ITEM -- OK"
    elif [[ "$ITEM" == */ ]]; then
        # Директория -- проверяем, что внутри есть файлы
        DIR_CONTENTS=$(find "$SCRIPT_DIR/$ITEM" -type f 2>/dev/null | head -1)
        if [ -z "$DIR_CONTENTS" ]; then
            echo "[-] $ITEM -- ПУСТАЯ ДИРЕКТОРИЯ (или отсутствует)"
            ERRORS=$((ERRORS + 1))
        else
            echo "[+] $ITEM -- OK"
        fi
    fi
done

echo ""
echo "=== Итог ==="

if [ "$ERRORS" -eq 0 ]; then
    echo "Репозиторий чист. Все файлы соответствуют модулю."
    exit 0
else
    echo "ОБНАРУЖЕНО ОШИБОК: $ERRORS"
    echo ""
    echo "Возможные причины:"
    echo "  1. Вы пушите из песочницы -- submodule попал в родительский репо"
    echo "  2. Вы случайно добавили сторонние файлы (git add -A)"
    echo "  3. Файлы модуля удалены или переименованы"
    echo ""
    echo "Исправление:"
    echo "  git rm --cached <файл>    -- удалить из индекса"
    echo "  git commit --amend         -- исправить коммит"
    echo ""
    exit 1
fi

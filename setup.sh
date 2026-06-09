#!/bin/bash
# ============================================================
# anti-hallucination-guard / setup.sh
# Установка анти-халлюцинационных механизмов в проект.
# Запуск из корня проекта:
#   bash path/to/anti-hallucination-guard/setup.sh
# ============================================================

set -euo pipefail

# --- Конфигурация ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
WORKLOG="$PROJECT_ROOT/worklog.md"
RULES="$PROJECT_ROOT/AGENT_RULES.md"
HOOK_DIR="$PROJECT_ROOT/.git/hooks"
HOOK_SRC="$SCRIPT_DIR/.git-hooks/pre-commit"
PUSH_HOOK_SRC="$SCRIPT_DIR/.git-hooks/pre-push"
CHECK_SCRIPT="$PROJECT_ROOT/scripts/check-agent.sh"
AUDIT_SCRIPT="$PROJECT_ROOT/scripts/audit.sh"
VALIDATE_SCRIPT="$PROJECT_ROOT/scripts/validate.sh"

# Цвета для терминала (только если есть TTY)
if [ -t 1 ]; then
    GREEN="[32m"
    RED="[31m"
    YELLOW="[33m"
    RESET="[0m"
else
    GREEN=""
    RED=""
    YELLOW=""
    RESET=""
fi

ok()   { echo -e "${GREEN}[OK]${RESET} $1"; }
err()  { echo -e "${RED}[ERROR]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }

# --- Проверки ---
echo ""
echo "=== anti-hallucination-guard: setup ==="
echo "Project root: $PROJECT_ROOT"
echo "Module dir:   $SCRIPT_DIR"
echo ""

if [ ! -d "$PROJECT_ROOT/.git" ]; then
    warn "Git не инициализирован в проекте."
    read -rp "Инициализировать git сейчас? (y/N): " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        git init "$PROJECT_ROOT"
        ok "git init"
    else
        err "Git нужен для работы хуков. Выход."
        exit 1
    fi
fi

# --- 1. AGENT_RULES.md ---
if [ -f "$RULES" ]; then
    warn "AGENT_RULES.md уже существует -- пропускаю (не перезаписываю)"
else
    cp "$SCRIPT_DIR/AGENT_RULES.md" "$RULES"
    ok "AGENT_RULES.md создан"
fi

# --- 2. worklog.md ---
if [ -f "$WORKLOG" ]; then
    warn "worklog.md уже существует -- пропускаю (не перезаписываю)"
else
    cat > "$WORKLOG" << 'WORKLOG_EOF'
---
Task ID: 0
Agent: setup
Task: Инициализация anti-hallucination-guard

Work Log:
- Запущен setup.sh
- AGENT_RULES.md создан
- Pre-commit hook установлен
- Скрипты мониторинга скопированы

Stage Summary:
- Механизмы активны
- Начинаем работу
---
WORKLOG_EOF
    ok "worklog.md создан"
fi

# --- 3. Pre-commit hook ---
mkdir -p "$HOOK_DIR"

# Проверяем, не установлен ли уже наш хук
if [ -f "$HOOK_DIR/pre-commit" ]; then
    CURRENT_HASH="$(md5sum "$HOOK_DIR/pre-commit" 2>/dev/null | cut -d' ' -f1)"
    EXPECTED_MARKER="anti-hallucination-guard"
    if grep -q "$EXPECTED_MARKER" "$HOOK_DIR/pre-commit" 2>/dev/null; then
        warn "pre-commit hook уже установлен (наш) -- обновляю"
        cp "$HOOK_SRC" "$HOOK_DIR/pre-commit"
        chmod +x "$HOOK_DIR/pre-commit"
        ok "pre-commit hook обновлён"
    else
        warn "pre-commit hook уже существует (чужой) -- не перезаписываю"
        echo "  Для установки вручную скопируй:"
        echo "  cp $HOOK_SRC $HOOK_DIR/pre-commit"
    fi
else
    cp "$HOOK_SRC" "$HOOK_DIR/pre-commit"
    chmod +x "$HOOK_DIR/pre-commit"
    ok "pre-commit hook установлен"
fi

# --- 4. Pre-push hook (защита модуля) ---
if [ -f "$HOOK_DIR/pre-push" ]; then
    warn "pre-push hook уже существует -- пропускаю"
else
    cp "$PUSH_HOOK_SRC" "$HOOK_DIR/pre-push"
    chmod +x "$HOOK_DIR/pre-push" 2>/dev/null || true
    ok "pre-push hook установлен"
fi

# --- 5. Скрипты мониторинга ---
mkdir -p "$PROJECT_ROOT/scripts"

if [ -f "$VALIDATE_SCRIPT" ]; then
    warn "scripts/validate.sh уже существует -- пропускаю"
else
    cp "$SCRIPT_DIR/scripts/validate.sh" "$VALIDATE_SCRIPT"
    chmod +x "$VALIDATE_SCRIPT" 2>/dev/null || true
    ok "scripts/validate.sh создан"
fi

if [ -f "$CHECK_SCRIPT" ]; then
    warn "scripts/check-agent.sh уже существует -- пропускаю"
else
    cp "$SCRIPT_DIR/scripts/check-agent.sh" "$CHECK_SCRIPT"
    chmod +x "$CHECK_SCRIPT"
    ok "scripts/check-agent.sh создан"
fi

if [ -f "$AUDIT_SCRIPT" ]; then
    warn "scripts/audit.sh уже существует -- пропускаю"
else
    cp "$SCRIPT_DIR/scripts/audit.sh" "$AUDIT_SCRIPT"
    chmod +x "$AUDIT_SCRIPT"
    ok "scripts/audit.sh создан"
fi

# --- 6. Skill (если skills/ существует в проекте) ---
if [ -d "$PROJECT_ROOT/skills" ]; then
    SKILL_DIR="$PROJECT_ROOT/skills/anti-hallucination-guard"
    if [ -d "$SKILL_DIR" ]; then
        warn "skills/anti-hallucination-guard уже существует -- пропускаю"
    else
        cp -r "$SCRIPT_DIR/skills/anti-hallucination-guard" "$SKILL_DIR"
        ok "skills/anti-hallucination-guard создан"
    fi
else
    warn "skills/ не найден -- skill не установлен (не требуется для Z.ai)"
fi

# --- 7. verify-docs (опционально, требует bun) ---
VERIFY_DOCS_DIR="$SCRIPT_DIR/tools/verify-docs"
VERIFY_DOCS_PKG="$PROJECT_ROOT/tools/verify-docs"

if [ -d "$VERIFY_DOCS_DIR" ] && command -v bun &>/dev/null; then
    if [ -d "$VERIFY_DOCS_PKG" ]; then
        warn "tools/verify-docs уже существует -- пропускаю"
    else
        mkdir -p "$PROJECT_ROOT/tools"
        cp -r "$VERIFY_DOCS_DIR" "$VERIFY_DOCS_PKG"
        cd "$VERIFY_DOCS_PKG"
        bun install 2>/dev/null || true
        cd "$PROJECT_ROOT"
        ok "tools/verify-docs установлен (bun link: bun run tools/verify-docs/src/cli.ts)"
    fi

    # Создать verify-docs.json если нет
    if [ ! -f "$PROJECT_ROOT/verify-docs.json" ]; then
        warn "verify-docs.json не найден -- создай вручную или запусти: bun run tools/verify-docs/src/init.ts"
    fi

    # Обновить pre-commit: добавить verify-docs если его там нет
    if grep -q "verify-docs" "$HOOK_DIR/pre-commit" 2>/dev/null; then
        ok "verify-docs уже в pre-commit hook"
    else
        # Добавить секцию verify-docs в конец pre-commit hook
        cat >> "$HOOK_DIR/pre-commit" << 'VERIFY_DOCS_HOOK'

# --- verify-docs: проверка чисел в README ---
if command -v bun &>/dev/null && [ -f "verify-docs.json" ]; then
    VERIFY_RESULT=$(bun run tools/verify-docs/src/cli.ts --ci 2>&1)
    VERIFY_EXIT=$?
    if [ "$VERIFY_EXIT" -ne 0 ]; then
        echo ""
        echo "  ОШИБКА: verify-docs обнаружил расхождение!"
        echo ""
        echo "$VERIFY_RESULT"
        echo ""
        echo "  Исправь числа в README или в verify-docs.json."
        echo "  Или обойди: git commit --no-verify"
        echo ""
        exit 1
    fi
    echo "  OK: verify-docs пройден"
fi
VERIFY_DOCS_HOOK
        ok "verify-docs добавлен в pre-commit hook"
    fi
elif [ -d "$VERIFY_DOCS_DIR" ]; then
    warn "verify-docs пропущен: bun не найден (установи: curl -fsSL https://bun.sh/install | bash)"
else
    warn "verify-docs не найден в модуле -- пропускаю"
fi

# --- 8. Git-подтверждение ---
cd "$PROJECT_ROOT"
git add AGENT_RULES.md worklog.md .git/hooks/pre-commit scripts/ tools/ 2>/dev/null || true
ok "Файлы добавлены в git staging"

# --- Итог ---
echo ""
echo "=== Установка завершена ==="
echo ""
echo "Установлено:"
echo "  AGENT_RULES.md          -- правила работы агента"
echo "  worklog.md              -- обязательный лог работы"
echo "  .git/hooks/pre-commit  -- блокирует коммит без worklog"
echo "  .git/hooks/pre-push     -- блокирует push мусора в модуль"
echo "  scripts/check-agent.sh -- мониторинг активности"
echo "  scripts/audit.sh       -- аудит результатов сессии"
echo "  scripts/validate.sh    -- проверка чистоты модуля"
if command -v bun &>/dev/null && [ -d "$VERIFY_DOCS_DIR" ]; then
echo "  tools/verify-docs      -- проверка чисел в README (bun)"
echo "  pre-commit hook        -- + verify-docs (если verify-docs.json есть)"
fi
echo ""
echo "Промпт для старта агента:"
echo "  Перед началом работы прочитай /AGENT_RULES.md и /worklog.md."
echo "  Каждое действие фиксируй в worklog.md."
echo "  После логического блока -- git commit."
echo ""

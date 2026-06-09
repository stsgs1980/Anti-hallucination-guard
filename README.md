# anti-hallucination-guard

Git-модуль для предотвращения "иллюзии деятельности" AI-агентов в песочнице Z.ai.
Включает встроенный **verify-docs** -- проверку чисел в README против реального кода.

## Что делает

Физически заставляет агента:
- Фиксировать каждое действие в worklog
- Читать файлы перед их изменением
- Коммитить по логическим блокам
- Останавливаться при зацикливании
- Честно отчитываться о результатах

Плюс автоматическая проверка документации:
- Числа в README сверяются с реальным кодом
- Блокирует push если расхождение
- Поддержка cross-repo проверок

## Подключение к проекту

### Вариант 1: Git submodule (рекомендуется)

```bash
cd /path/to/your/project
git submodule add https://github.com/stsgs1980/Anti-hallucination-guard.git anti-hallucination-guard
git submodule update --init --recursive
bash anti-hallucination-guard/setup.sh
git add .gitmodules anti-hallucination-guard AGENT_RULES.md worklog.md scripts/
git commit -m "feat: add anti-hallucination-guard"
```

Обновление до последней версии:
```bash
cd anti-hallucination-guard && git pull origin main
cd ..
bash anti-hallucination-guard/setup.sh
git add anti-hallucination-guard && git commit -m "update: anti-hallucination-guard"
```

Клонеру проекта после `git clone`:
```bash
git submodule update --init --recursive
bash anti-hallucination-guard/setup.sh
```

### Вариант 2: Простое копирование

```bash
cp -r /path/to/anti-hallucination-guard /path/to/your/project/
cd /path/to/your/project
bash anti-hallucination-guard/setup.sh
```

## Что установит setup.sh

| Файл | Назначение |
|---|---|
| `AGENT_RULES.md` | Правила работы агента (в корень проекта) |
| `worklog.md` | Обязательный лог работы (в корень проекта) |
| `.git/hooks/pre-commit` | Блокирует commit без обновлённого worklog + verify-docs |
| `.git/hooks/pre-push` | Блокирует push мусора в модуль |
| `scripts/check-agent.sh` | Мониторинг активности (cron или вручную) |
| `scripts/audit.sh` | Аудит результатов после сессии |
| `scripts/validate.sh` | Проверка чистоты модуля |
| `tools/verify-docs/` | Проверка чисел в README (требует bun) |

## verify-docs (встроенный)

Автоматически устанавливается если в системе есть `bun`.
Сверяет числа в README с реальным кодом:

```json
{
  "readme": "README.md",
  "checks": [
    {
      "name": "Components",
      "source": "glob:src/components/**/*.tsx",
      "readmePattern": "(\\d+) components"
    },
    {
      "name": "Models",
      "source": "file:prisma/schema.prisma",
      "countPattern": "^model \\w+",
      "readmePattern": "(\\d+) models"
    }
  ]
}
```

Создай `verify-docs.json` в корне проекта и запусти:
```bash
bun run tools/verify-docs/src/cli.ts
```

Или автосоздание конфига:
```bash
bun run tools/verify-docs/src/init.ts
```

Источники данных: `file:`, `glob:`, `git:HEAD`, `custom:` (плагины).
Подробности: `tools/verify-docs/README.md` в репозитории verify-docs.

## Использование

### При старте каждой сессии

```
Перед началом работы прочитай /AGENT_RULES.md и /worklog.md.
```

### Во время работы

- Перед изменением файла -> Read tool
- После изменения -> обнови worklog.md
- После логического блока -> git commit (заблокирован без worklog)
- При 3-й неудачной попытке -> СТОП, напиши в чат

### После завершения сессии

```bash
bash scripts/audit.sh   # оценка качества работы
git push                 # сохранение результатов
```

## Удаление

```bash
rm AGENT_RULES.md worklog.md verify-docs.json
rm .git/hooks/pre-commit .git/hooks/pre-push
rm -r scripts/ tools/verify-docs/
rm -r anti-hallucination-guard/
```

## Структура модуля

```
anti-hallucination-guard/
  setup.sh                          -- установка в проект
  AGENT_RULES.md                    -- шаблон правил
  .git-hooks/
    pre-commit                      -- pre-commit hook (worklog + verify-docs)
    pre-push                        -- pre-push hook (защита от мусора)
  scripts/
    check-agent.sh                  -- мониторинг активности
    audit.sh                        -- аудит результатов
    validate.sh                     -- проверка чистоты модуля
  tools/
    verify-docs/                    -- встроенный verify-docs
      src/
        engine.ts                   -- ядро проверки
        cli.ts                      -- CLI
        init.ts                     -- автосоздание конфига
      templates/
        pre-push                    -- шаблон хука для verify-docs
        verify.yml                  -- GitHub Actions workflow
        install-hooks.ts            -- установщик хуков
      examples/
        simple/                     -- базовый конфиг
        monorepo/                   -- конфиг с плагинами и cross-repo
      package.json
  skills/
    anti-hallucination-guard/
      SKILL.md                      -- Z.ai skill
  .gitignore
  README.md                         -- этот файл
```

---

v1.1 | 2026-06-09 | MIT

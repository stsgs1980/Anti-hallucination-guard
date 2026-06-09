# anti-hallucination-guard

Git-модуль для предотвращения "иллюзии деятельности" AI-агентов в песочнице Z.ai.

## Что делает

Физически заставляет агента:
- Фиксировать каждое действие в worklog
- Читать файлы перед их изменением
- Коммитить по логическим блокам
- Останавливаться при зацикливании
- Честно отчитываться о результатах

## Подключение к проекту

### Вариант 1: Git submodule

```bash
cd /path/to/your/project
git submodule add <repo-url> anti-hallucination-guard
git submodule update --init
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
| `.git/hooks/pre-commit` | Блокирует commit без обновлённого worklog |
| `scripts/check-agent.sh` | Мониторинг активности (cron или вручную) |
| `scripts/audit.sh` | Аудит результатов после сессии |
| `skills/anti-hallucination-guard/` | Z.ai skill (если skills/ есть) |

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
rm AGENT_RULES.md worklog.md
rm .git/hooks/pre-commit
rm -r scripts/check-agent.sh scripts/audit.sh
rm -r anti-hallucination-guard/
```

## Структура модуля

```
anti-hallucination-guard/
  setup.sh                          -- установка в проект
  AGENT_RULES.md                    -- шаблон правил
  .git-hooks/
    pre-commit                      -- pre-commit hook
  scripts/
    check-agent.sh                  -- мониторинг активности
    audit.sh                        -- аудит результатов
  skills/
    anti-hallucination-guard/
      SKILL.md                      -- Z.ai skill
  README.md                         -- этот файл
```

---

v1.0 | 2026-06-09 | MIT

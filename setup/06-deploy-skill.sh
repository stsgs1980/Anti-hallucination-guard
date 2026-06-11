#!/usr/bin/env bash
# setup/06-deploy-skill.sh
# Installs AHG skill definition into project skills/ directory.
# Only runs if skills/ directory exists in the project.

if [ -d "$PROJECT_ROOT/skills" ]; then
    SKILL_DIR="$PROJECT_ROOT/skills/anti-hallucination-guard"
    if [ -d "$SKILL_DIR" ]; then
        warn "skills/anti-hallucination-guard already exists -- skipping"
    else
        cp -r "$MODULE_ROOT/skills/anti-hallucination-guard" "$SKILL_DIR"
        ok "skills/anti-hallucination-guard created"
    fi
else
    warn "skills/ not found -- skill not installed (not required for Z.ai)"
fi

#!/usr/bin/env bash
# setup/02-create-worklog.sh
# Creates initial worklog.md if it does not exist.

if [ -f "$WORKLOG" ]; then
    warn "worklog.md already exists -- skipping (will not overwrite)"
else
    cat > "$WORKLOG" << 'WORKLOG_EOF'
---
Task ID: 0
Agent: setup
Task: anti-hallucination-guard initialization

Work Log:
- setup.sh executed
- AGENT_RULES.md created
- Pre-commit hook installed
- Monitoring scripts copied

Stage Summary:
- Mechanisms active
- Ready to start work
---
WORKLOG_EOF
    ok "worklog.md created"
fi

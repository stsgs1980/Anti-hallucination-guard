#!/usr/bin/env bash
# setup/01-deploy-agent-rules.sh
# Deploys AHG section into project AGENT_RULES.md.
# Uses HTML comment markers: <!-- AHG:START --> ... <!-- AHG:END -->
# Idempotent: removes old block first, then inserts new one.
# Compatible with cascade-guard's <!-- CASCADE-GUARD:START/END --> markers.

AHG_BLOCK_SRC="$MODULE_ROOT/AGENT_RULES.md"

if [ -f "$RULES" ]; then
    # Check if AHG block already exists
    if grep -q "AHG:START" "$RULES" 2>/dev/null; then
        # Remove old AHG block (between markers, inclusive)
        sed '/<!-- AHG:START -->/,/<!-- AHG:END -->/d' "$RULES" > "${RULES}.tmp"
        mv "${RULES}.tmp" "$RULES"
        ok "Removed previous AHG block from AGENT_RULES.md"
    fi

    # Append new AHG block
    echo "" >> "$RULES"
    echo "<!-- AHG:START -->" >> "$RULES"
    echo "<!-- Do NOT edit between START and END markers. This block is managed by anti-hallucination-guard/setup.sh -->" >> "$RULES"
    # Insert the rules content (without the version footer line, we add our own)
    grep -v '^v[0-9]' "$AHG_BLOCK_SRC" | grep -v '^---$' | grep -v '^# AGENT RULES' | grep -v '^> Copied to project' >> "$RULES"
    echo "" >> "$RULES"
    echo "<!-- AHG:END -->" >> "$RULES"
    ok "AHG block appended to existing AGENT_RULES.md"
else
    # Create new AGENT_RULES.md with AHG block
    echo "# AGENT RULES -- VIOLATION IS NOT ACCEPTABLE" > "$RULES"
    echo "" >> "$RULES"
    echo "<!-- AHG:START -->" >> "$RULES"
    echo "<!-- Do NOT edit between START and END markers. This block is managed by anti-hallucination-guard/setup.sh -->" >> "$RULES"
    grep -v '^v[0-9]' "$AHG_BLOCK_SRC" | grep -v '^---$' | grep -v '^# AGENT RULES' | grep -v '^> Copied to project' >> "$RULES"
    echo "" >> "$RULES"
    echo "<!-- AHG:END -->" >> "$RULES"
    ok "AGENT_RULES.md created with AHG rules"
fi

#!/usr/bin/env bash
# ============================================================
# anti-hallucination-guard / co-change-check.sh
# Detects that buddy files change together in a commit.
#
# If file A changes, file B should also change.
# If B is missing from the commit -> WARN (or BLOCK).
#
# Called from pre-commit hook (Phase 5).
# Can also be run manually: bash scripts/co-change-check.sh
#
# Configuration: .ahg-cochange.json in project root
# ============================================================

set -euo pipefail

# -- Colors --
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; }

# -- Resolve project root --
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# -- Find config --
CONFIG=""
# 1. Project root
if [ -f "$PROJECT_ROOT/.ahg-cochange.json" ]; then
    CONFIG="$PROJECT_ROOT/.ahg-cochange.json"
# 2. AHG module (if running as submodule)
elif [ -n "${_pc_ahg_dir:-}" ] && [ -f "${_pc_ahg_dir}/.ahg-cochange.json" ]; then
    CONFIG="${_pc_ahg_dir}/.ahg-cochange.json"
# 3. Same directory as this script (AHG standalone repo)
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/../.ahg-cochange.json" ]; then
        CONFIG="$SCRIPT_DIR/../.ahg-cochange.json"
    fi
fi

if [ -z "$CONFIG" ]; then
    # No config -> skip silently
    exit 0
fi

# -- Mode: warn or block --
MODE="${COCHANGE_MODE:-warn}"

# -- Get staged files --
STAGED=$(git diff --cached --name-only 2>/dev/null || echo "")
if [ -z "$STAGED" ]; then
    # Nothing staged, nothing to check
    exit 0
fi

# -- Check for [no-cochange] bypass in commit message --
COMMIT_MSG=""
if [ -f "$PROJECT_ROOT/.git/COMMIT_EDITMSG" ]; then
    COMMIT_MSG=$(cat "$PROJECT_ROOT/.git/COMMIT_EDITMSG" 2>/dev/null || echo "")
fi
if echo "$COMMIT_MSG" | grep -qi "\[no-cochange\]"; then
    ok "[co-change] Bypass: [no-cochange] in commit message"
    exit 0
fi

# -- Parse config and check --
VIOLATIONS=0
WARNINGS=0

# Use python3 to parse JSON config
if ! command -v python3 &>/dev/null; then
    # No python3 -> skip
    exit 0
fi

# Export variables for python3
export COCHANGE_CONFIG="$CONFIG"
export COCHANGE_STAGED="$STAGED"
export COCHANGE_MODE="$MODE"

python3 -c '
import json, sys, os

config_path = os.environ.get("COCHANGE_CONFIG", "")
staged_raw = os.environ.get("COCHANGE_STAGED", "")
mode = os.environ.get("COCHANGE_MODE", "warn")

if not config_path:
    sys.exit(0)

staged = set(staged_raw.strip().split("\n")) if staged_raw.strip() else set()

with open(config_path) as f:
    config = json.load(f)

pairs = config.get("pairs", [])
violations = 0
warnings = 0

for pair in pairs:
    trigger = pair.get("trigger", "")
    buddies = pair.get("expect", [])
    severity = pair.get("severity", "warn")
    message = pair.get("message", "")

    # Check if any staged file matches the trigger pattern
    triggered = False
    for s in staged:
        if "*" in trigger:
            # Glob pattern: use fnmatch
            import fnmatch
            if fnmatch.fnmatch(s, trigger):
                triggered = True
                break
        else:
            if s == trigger:
                triggered = True
                break

    if not triggered:
        continue

    # Trigger file is in commit. Check if buddies are also present.
    missing = []
    for buddy in buddies:
        found = False
        if "*" in buddy:
            import fnmatch
            for s in staged:
                if fnmatch.fnmatch(s, buddy):
                    found = True
                    break
        else:
            found = buddy in staged

        if not found:
            missing.append(buddy)

    if missing:
        sev_label = severity
        if severity == "block":
            violations += 1
        else:
            warnings += 1

        print("  [%s] Trigger: %s" % (sev_label.upper(), trigger))
        print("    Missing buddy files: %s" % ", ".join(missing))
        if message:
            print("    %s" % message)

# Output result
if violations > 0:
    print("\n  CO-CHANGE BLOCKED: %d required buddy file(s) not in commit." % violations)
    sys.exit(1)
elif warnings > 0:
    print("\n  CO-CHANGE WARNING: %d buddy file(s) not in commit." % warnings)
    print("  Consider updating the listed files before committing.")
    sys.exit(0)
else:
    print("  [OK] All co-change buddies present")
    sys.exit(0)
'

result=$?
if [ $result -ne 0 ] && [ "$MODE" = "block" ]; then
    echo ""
    err "Co-change violations found. Commit blocked."
    err "Add missing buddy files or use [no-cochange] in commit message."
    exit 1
fi

exit $result

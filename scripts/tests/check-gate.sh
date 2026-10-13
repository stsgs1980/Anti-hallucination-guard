#!/usr/bin/env bash
# ============================================================
# anti-hallucination-guard / tests/check-gate.sh
# Self-tests for scripts/check.sh, the single gate.
#
# What has to hold:
#   - a missing tool is reported as SKIP, never as PASS;
#   - --strict turns that SKIP into a failure;
#   - a failing check propagates to the gate exit code;
#   - unknown check or stage names are a usage error, not a pass;
#   - a selection that matches nothing is an error, not a pass.
#
# Fixtures are built under a temporary directory and removed on exit.
# Run: bash scripts/tests/check-gate.sh
# ============================================================

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHECK="$MODULE_ROOT/scripts/check.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ahg-gate-XXXXXX")"

PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ok()  { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

eq() { # name expected actual
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 -- expected '$2', got '$3'"; fi
}

has() { # name haystack needle
    case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 -- output lacks '$3'" ;; esac
}

# A PATH without bun, so dependency handling can be observed.
NO_BUN_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "=== check.sh: registry and usage ==="

OUT="$(bash "$CHECK" --list 2>&1)"; CODE=$?
eq "--list exits 0" "0" "$CODE"
for id in syntax linecount cochange verifydocs autodiscover purity \
          branchprotect tests_engine tests_shell tests_gate; do
    has "--list contains '$id'" "$OUT" "$id"
done

bash "$CHECK" --only=does_not_exist >/dev/null 2>&1
eq "unknown check name is a usage error" "2" "$?"

bash "$CHECK" --stage=does_not_exist >/dev/null 2>&1
eq "unknown stage is a usage error" "2" "$?"

bash "$CHECK" --nonsense >/dev/null 2>&1
eq "unknown option is a usage error" "2" "$?"

echo ""
echo "=== check.sh: running checks ==="

OUT="$(bash "$CHECK" --only=syntax 2>&1)"; CODE=$?
eq "--only=syntax exits 0" "0" "$CODE"
has "syntax is reported as PASS" "$OUT" "[PASS] syntax"
has "summary is printed" "$OUT" "Summary:"

OUT="$(bash "$CHECK" --only=syntax,linecount --skip=linecount 2>&1)"
has "--skip removes a check from the run" "$OUT" "1 passed"

echo ""
echo "=== check.sh: a tool that is missing must not look like a pass ==="

OUT="$(env PATH="$NO_BUN_PATH" bash "$CHECK" --only=verifydocs 2>&1)"; CODE=$?
eq "missing bun exits 0 without --strict" "0" "$CODE"
has "missing bun is reported as SKIP" "$OUT" "[SKIP] verifydocs"
case "$OUT" in
    *"[PASS] verifydocs"*) bad "missing bun must not be reported as PASS" ;;
    *) ok "missing bun is not reported as PASS" ;;
esac

env PATH="$NO_BUN_PATH" bash "$CHECK" --only=verifydocs --strict >/dev/null 2>&1
eq "--strict turns the skip into a failure" "1" "$?"

echo ""
echo "=== check.sh: failures and empty selections ==="

# A disposable project with a file over the line limit.
FIX="$TMP/over-limit"
mkdir -p "$FIX/scripts"
git -C "$FIX" init -q
cp "$CHECK" "$FIX/scripts/"
cp "$MODULE_ROOT/scripts/line-count-check.sh" "$FIX/scripts/"
: > "$FIX/scripts/big.sh"
for i in $(seq 1 300); do echo "echo $i" >> "$FIX/scripts/big.sh"; done

OUT="$(cd "$FIX" && bash scripts/check.sh --only=linecount 2>&1)"; CODE=$?
eq "a failing check fails the gate" "1" "$CODE"
has "the failing check is named" "$OUT" "[FAIL] linecount"

# Same project is a consumer context, so the module-only check is not
# applicable and the selection matches nothing.
OUT="$(cd "$FIX" && bash scripts/check.sh --only=purity 2>&1)"; CODE=$?
eq "empty selection is an error, not a pass" "2" "$CODE"
has "empty selection says so" "$OUT" "Nothing ran"

echo ""
echo "=== Result ==="
echo "  passed: $PASS"
echo "  failed: $FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

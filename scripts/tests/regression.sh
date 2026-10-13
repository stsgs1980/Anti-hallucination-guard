#!/usr/bin/env bash
# ============================================================
# anti-hallucination-guard / tests/regression.sh
# Regression tests for the shell-level defects found in review.
#
# Every test runs the REAL scripts from this module inside a disposable
# git repository under a temporary directory. Nothing in the module repo
# or the caller's project is modified.
#
# Covered regressions:
#   1. co-change "block" violation was not blocking: `set -e` aborted the
#      script before python's exit status was translated, so the pre-commit
#      hook saw code 2 ("unexpected error") and only warned.
#   2. audit.sh could never detect repeated commit messages: `git log
#      --oneline` prefixes each line with the hash, so `uniq -d` found
#      nothing.
#   3. audit.sh MAX_SCORE (100) was higher than the attainable sum (90).
#
# Run: bash scripts/tests/regression.sh
# ============================================================

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ahg-regression-XXXXXX")"

PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

# eq <name> <expected> <actual>
eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 -- expected '$2', got '$3'"; fi
}

# has <name> <haystack> <needle>
has() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) bad "$1 -- output does not contain '$3'" ;;
    esac
}

# hasnt <name> <haystack> <needle>
hasnt() {
    case "$2" in
        *"$3"*) bad "$1 -- output still contains '$3'" ;;
        *) ok "$1" ;;
    esac
}

new_repo() {
    local dir="$TMP/$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "regression@example.invalid"
    git -C "$dir" config user.name "Regression Test"
    echo "$dir"
}

write_cochange_config() { # <dir> <severity>
    cat > "$1/.ahg-cochange.json" <<EOF
{
  "version": "test",
  "pairs": [
    {
      "trigger": "src/feature.ts",
      "expect": ["docs/feature.md"],
      "severity": "$2",
      "message": "docs must change with the feature"
    }
  ]
}
EOF
}

write_worklog() { # <dir>
    cat > "$1/worklog.md" <<'EOF'
---
Task ID: T-1
Work Log: added the feature and its documentation
Stage Summary: complete
---
EOF
}

echo "=== co-change-check.sh ==="

# -- Regression 1a: block violation must exit 1 ---------------------------
REPO="$(new_repo cc-block)"
write_cochange_config "$REPO" block
mkdir -p "$REPO/src"
echo "export const a = 1;" > "$REPO/src/feature.ts"
git -C "$REPO" add -A
OUT="$(cd "$REPO" && bash "$MODULE_ROOT/scripts/co-change-check.sh" 2>&1)"
CODE=$?
eq "block violation exits 1" "1" "$CODE"
has "block violation says CO-CHANGE BLOCKED" "$OUT" "CO-CHANGE BLOCKED"

# -- Regression 1b: buddy present must exit 0 -----------------------------
REPO="$(new_repo cc-pass)"
write_cochange_config "$REPO" block
mkdir -p "$REPO/src" "$REPO/docs"
echo "export const a = 1;" > "$REPO/src/feature.ts"
echo "# feature" > "$REPO/docs/feature.md"
git -C "$REPO" add -A
OUT="$(cd "$REPO" && bash "$MODULE_ROOT/scripts/co-change-check.sh" 2>&1)"
CODE=$?
eq "buddy present exits 0" "0" "$CODE"

# -- Regression 1c: warn severity stays non-blocking ----------------------
REPO="$(new_repo cc-warn)"
write_cochange_config "$REPO" warn
mkdir -p "$REPO/src"
echo "export const a = 1;" > "$REPO/src/feature.ts"
git -C "$REPO" add -A
OUT="$(cd "$REPO" && bash "$MODULE_ROOT/scripts/co-change-check.sh" 2>&1)"
CODE=$?
eq "warn severity exits 0 (non-blocking)" "0" "$CODE"
has "warn severity still reports the warning" "$OUT" "CO-CHANGE WARNING"

# -- Regression 1d: the pre-commit hook must actually block ---------------
REPO="$(new_repo cc-hook)"
write_cochange_config "$REPO" block
write_worklog "$REPO"
mkdir -p "$REPO/scripts" "$REPO/src" "$REPO/.git/hooks"
cp "$MODULE_ROOT/scripts/co-change-check.sh" "$REPO/scripts/"
cp "$MODULE_ROOT/scripts/line-count-check.sh" "$REPO/scripts/"
cp "$MODULE_ROOT/.git-hooks/pre-commit" "$REPO/.git/hooks/pre-commit"
chmod +x "$REPO/.git/hooks/pre-commit"
echo "export const a = 1;" > "$REPO/src/feature.ts"
git -C "$REPO" add -A
OUT="$(cd "$REPO" && git -c commit.gpgsign=false commit -m "add feature without docs" 2>&1)"
CODE=$?
if [ "$CODE" -ne 0 ]; then ok "pre-commit blocks the commit (exit $CODE)"; else bad "pre-commit let the commit through"; fi
has "hook names the co-change violation" "$OUT" "Co-change violations"
if git -C "$REPO" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    bad "no commit was created"
else
    ok "no commit was created"
fi

echo ""
echo "=== audit.sh ==="

# -- Regression 2: repeated commit messages are detected ------------------
REPO="$(new_repo audit-loop)"
mkdir -p "$REPO/scripts"
cp "$MODULE_ROOT/scripts/audit.sh" "$REPO/scripts/"
for i in 1 2 3 4 5; do
    echo "change $i" > "$REPO/file-$i.txt"
    git -C "$REPO" add -A
    git -C "$REPO" -c commit.gpgsign=false commit -q -m "update the thing"
done
OUT="$(cd "$REPO" && bash scripts/audit.sh 2>&1)"
has "repeated commit messages are reported" "$OUT" "Repeated commit messages"
hasnt "no false 'No repeated commit messages'" "$OUT" "No repeated commit messages"
hasnt "no dishonesty verdict" "$OUT" "faking activity"

# -- Regression 2b: clean history is not flagged --------------------------
REPO="$(new_repo audit-clean)"
mkdir -p "$REPO/scripts"
cp "$MODULE_ROOT/scripts/audit.sh" "$REPO/scripts/"
for i in 1 2 3 4 5; do
    echo "change $i" > "$REPO/file-$i.txt"
    git -C "$REPO" add -A
    git -C "$REPO" -c commit.gpgsign=false commit -q -m "distinct message $i"
done
OUT="$(cd "$REPO" && bash scripts/audit.sh 2>&1)"
has "clean history reports no repeats" "$OUT" "No repeated commit messages"

# -- Regression 3: MAX_SCORE must equal the attainable sum ----------------
# Each weight line looks like: SCORE=$((SCORE + 20))
SUM=$(grep -o 'SCORE=$((SCORE + [0-9]\+))' "$MODULE_ROOT/scripts/audit.sh" \
    | grep -oE '[0-9]+' | awk '{ total += $1 } END { print total }')
DECLARED=$(grep -m1 '^MAX_SCORE=' "$MODULE_ROOT/scripts/audit.sh" | grep -o '[0-9]\+$')
eq "audit MAX_SCORE equals the sum of weights" "$SUM" "$DECLARED"

echo ""
echo "=== Result ==="
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0

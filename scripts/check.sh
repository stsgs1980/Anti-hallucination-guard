#!/usr/bin/env bash
# ============================================================
# anti-hallucination-guard / check.sh
# The single list of checks. Every surface (CI, hooks, humans)
# runs this instead of keeping its own list.
#
# Usage: bash scripts/check.sh [--stage=all|ci|push|commit]
#            [--only=a,b] [--skip=a,b] [--strict] [--list] [--quiet]
#
#   --stage   which set to run (default: all)
#   --only    run just these checks; --skip drops checks from the stage
#   --strict  a skipped check counts as a failure
#   --list    print the registry and exit
#   --quiet   print only failures and the summary
#
# Exit: 0 all applicable checks passed, 1 a check failed (or a skip
# under --strict), 2 usage error or nothing matched.
#
# A check that cannot run because a tool is missing is reported as
# SKIP, never as PASS. Silently passing an unchecked gate is the
# failure mode this module exists to prevent.
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(git -C "$MODULE_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$MODULE_ROOT")"

# -- Context: are we the AHG module itself, or a consumer project? ------------
CONTEXT="consumer"
if [ -f "$MODULE_ROOT/setup.sh" ] && [ -f "$MODULE_ROOT/AGENT_RULES.md" ]; then
    CONTEXT="module"
fi

# -- Registry -----------------------------------------------------------------
# Parallel arrays, not an associative array: bash 3.2 (macOS) has no declare -A.
IDS=()
STAGES=()
SCOPES=()
NEEDS=()
TITLES=()

register() { # id stages scope needs title
    IDS+=("$1"); STAGES+=("$2"); SCOPES+=("$3"); NEEDS+=("$4"); TITLES+=("$5")
}

register syntax         "ci push commit all" both    ""        "Shell syntax (bash -n)"
register linecount      "ci push commit all" both    ""        "Anti-monolith line limit (Rule 12)"
register cochange       "commit all"         both    "python3" "Co-change buddy files (Rule 10)"
register verifydocs     "ci push commit all" both    "bun"     "verify-docs consistency"
register autodiscover   "ci all"             both    "bun"     "verify-docs auto-discover (no config)"
register purity         "ci push all"        module  ""        "Module purity + Unicode policy"
register branchprotect  "ci all"             module  ""        "Branch protection self-test"
register tests_engine   "ci push all"        module  "bun"     "verify-docs engine tests"
register tests_shell    "ci push all"        module  ""        "Shell regression tests"
register tests_gate     "ci push all"        module  ""        "Gate self-tests"

# -- Check implementations ----------------------------------------------------

run_syntax() {
    local f rc=0
    while IFS= read -r f; do
        bash -n "$f" || { echo "  SYNTAX ERROR: $f"; rc=1; }
    done < <(find "$TARGET_ROOT" -name '*.sh' \
        -not -path '*/.git/*' -not -path '*/node_modules/*' \
        -not -path '*/vendor/*' -not -path '*/dist/*' -not -path '*/build/*')
    return "$rc"
}

run_linecount() { bash "$SCRIPT_DIR/line-count-check.sh"; }

run_cochange() {
    # 0 = pass, 1 = blocked, 2 = rules could not be evaluated.
    bash "$SCRIPT_DIR/co-change-check.sh"
    local rc=$?
    [ "$rc" -eq 2 ] && return 3   # 3 = could not run -> SKIP
    return "$rc"
}

run_verifydocs() {
    (cd "$PROJECT_ROOT" && bun run "$MODULE_ROOT/tools/verify-docs/src/cli.ts" --ci)
}

run_autodiscover() {
    # Run the same engine with the config out of the way, then always put it
    # back: a check must not leave the workspace different from how it found it.
    local cfg="$PROJECT_ROOT/verify-docs.json" backup=""
    if [ -f "$cfg" ]; then
        backup="$(mktemp)"
        mv "$cfg" "$backup"
    fi
    (cd "$PROJECT_ROOT" && bun run "$MODULE_ROOT/tools/verify-docs/src/cli.ts" --ci)
    local rc=$?
    if [ -n "$backup" ]; then
        mv "$backup" "$cfg"
    fi
    return "$rc"
}

run_purity() { bash "$SCRIPT_DIR/validate.sh"; }

run_branchprotect() { bash "$SCRIPT_DIR/branch-protect.sh" --test; }

run_tests_engine() { (cd "$MODULE_ROOT" && bun test tools/verify-docs/tests/); }

run_tests_shell() { bash "$SCRIPT_DIR/tests/regression.sh"; }

run_tests_gate() { bash "$SCRIPT_DIR/tests/check-gate.sh"; }

# -- Argument parsing ---------------------------------------------------------

STAGE="all"
ONLY=""
SKIP=""
STRICT=0
QUIET=0
LIST=0

for arg in "$@"; do
    case "$arg" in
        --stage=*)  STAGE="${arg#*=}" ;;
        --only=*)   ONLY="${arg#*=}" ;;
        --skip=*)   SKIP="${arg#*=}" ;;
        --strict)   STRICT=1 ;;
        --quiet)    QUIET=1 ;;
        --list)     LIST=1 ;;
        --help|-h)  sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "check: unknown option '$arg' (see --help)" >&2; exit 2 ;;
    esac
done

case "$STAGE" in
    all|ci|push|commit) ;;
    *) echo "check: unknown stage '$STAGE' (all|ci|push|commit)" >&2; exit 2 ;;
esac

in_list() { # needle csv
    local item
    [ -z "$2" ] && return 1
    local IFS=','
    for item in $2; do
        [ "$item" = "$1" ] && return 0
    done
    return 1
}

# Validate --only / --skip names against the registry before running anything.
for wanted in "$ONLY" "$SKIP"; do
    if [ -n "$wanted" ]; then
        saved_ifs="$IFS"; IFS=','
        for name in $wanted; do
            IFS="$saved_ifs"
            known=0
            for id in "${IDS[@]}"; do
                [ "$id" = "$name" ] && known=1
            done
            if [ "$known" -eq 0 ]; then
                echo "check: unknown check '$name'. Known: ${IDS[*]}" >&2
                exit 2
            fi
            IFS=','
        done
        IFS="$saved_ifs"
    fi
done

if [ "$LIST" -eq 1 ]; then
    echo "id              stages                 scope     needs    title"
    for i in "${!IDS[@]}"; do
        printf '%-15s %-22s %-9s %-8s %s\n' \
            "${IDS[$i]}" "${STAGES[$i]}" "${SCOPES[$i]}" "${NEEDS[$i]:--}" "${TITLES[$i]}"
    done
    exit 0
fi

# -- Runner -------------------------------------------------------------------

PASSED=0; FAILED=0; SKIPPED=0; SELECTED=0
FAILED_IDS=""

echo "ahg check -- stage: $STAGE, context: $CONTEXT, strict: $([ "$STRICT" -eq 1 ] && echo on || echo off)"
echo ""

for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"

    # Stage filter
    case " ${STAGES[$i]} " in *" $STAGE "*) ;; *) continue ;; esac
    # Scope filter
    [ "${SCOPES[$i]}" = "module" ] && [ "$CONTEXT" != "module" ] && continue
    # Explicit selection
    if [ -n "$ONLY" ] && ! in_list "$id" "$ONLY"; then continue; fi
    if [ -n "$SKIP" ] && in_list "$id" "$SKIP"; then continue; fi

    SELECTED=$((SELECTED + 1))

    # Dependency filter: missing tool = SKIP, not PASS
    if [ -n "${NEEDS[$i]}" ] && ! command -v "${NEEDS[$i]}" &>/dev/null; then
        echo "  [SKIP] $id -- ${NEEDS[$i]} not installed (${TITLES[$i]})"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # The check runs from the directory that owns the files it inspects.
    TARGET_ROOT="$PROJECT_ROOT"
    [ "${SCOPES[$i]}" = "module" ] && TARGET_ROOT="$MODULE_ROOT"
    export TARGET_ROOT

    if [ "$QUIET" -eq 0 ]; then
        echo "  [RUN ] $id -- ${TITLES[$i]}"
    fi
    out="$("run_$id" 2>&1)"
    rc=$?

    case "$rc" in
        0)
            PASSED=$((PASSED + 1))
            [ "$QUIET" -eq 0 ] && echo "  [PASS] $id"
            ;;
        3)
            SKIPPED=$((SKIPPED + 1))
            echo "  [SKIP] $id -- could not be evaluated (${TITLES[$i]})"
            ;;
        *)
            FAILED=$((FAILED + 1))
            FAILED_IDS="$FAILED_IDS $id"
            echo "  [FAIL] $id -- ${TITLES[$i]} (exit $rc)"
            echo "$out" | sed 's/^/         /' | tail -25
            ;;
    esac
done

echo ""
echo "Summary: $PASSED passed, $FAILED failed, $SKIPPED skipped"

if [ "$FAILED" -gt 0 ]; then
    echo "Failed:$FAILED_IDS"
    exit 1
fi
if [ "$SKIPPED" -gt 0 ] && [ "$STRICT" -eq 1 ]; then
    echo "Strict mode: $SKIPPED check(s) could not run, so the gate is not proven."
    exit 1
fi
if [ "$SELECTED" -eq 0 ]; then
    echo "Nothing ran: the selection matched no check in this context."
    exit 2
fi
exit 0

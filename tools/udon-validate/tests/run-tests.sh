#!/usr/bin/env bash
# Self-test for udon-validate. Runs the validator against known fixtures and
# checks exit codes plus required/forbidden findings.
#
#   ./tools/udon-validate/tests/run-tests.sh
#
# No dependencies beyond bash and the validator itself.

set -u

TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TOOL_DIR=$(dirname -- "$TESTS_DIR")
VALIDATOR="$TOOL_DIR/udon-validate.sh"

FAIL=0
PASS=0

# run_case <name> <file> <expected_exit> <must_contain> <must_not_contain> [extra args...]
run_case() {
    name="$1"; file="$2"; want_exit="$3"; must="$4"; mustnot="$5"
    shift 5

    out=$(bash "$VALIDATOR" "$file" "$@" 2>&1)
    code=$?

    ok=1
    [ "$code" -eq "$want_exit" ] || ok=0
    if [ -n "$must" ]; then
        printf '%s' "$out" | grep -q -F -- "$must" || ok=0
    fi
    if [ -n "$mustnot" ]; then
        if printf '%s' "$out" | grep -q -F -- "$mustnot"; then ok=0; fi
    fi

    if [ "$ok" -eq 1 ]; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s (exit=%s, wanted %s)\n' "$name" "$code" "$want_exit"
        [ -n "$must" ] && printf '        expected to contain: %s\n' "$must"
        [ -n "$mustnot" ] && printf '        expected NOT to contain: %s\n' "$mustnot"
        FAIL=$((FAIL + 1))
    fi
}

printf '\nudon-validate self-test\n'
printf '========================\n'

# --- violations are caught -------------------------------------------------

run_case 'async is blocked'        "$TESTS_DIR/BadExample.cs" 1 'async methods are not supported' ''
run_case 'try/catch is blocked'    "$TESTS_DIR/BadExample.cs" 1 'try/catch is not supported' ''
run_case 'coroutine is blocked'    "$TESTS_DIR/BadExample.cs" 1 'yield return (coroutines)' ''
run_case 'StartCoroutine blocked'  "$TESTS_DIR/BadExample.cs" 1 'StartCoroutine is not available' ''
run_case 'AddListener blocked'     "$TESTS_DIR/BadExample.cs" 1 'AddListener() takes a delegate' ''
run_case 'System.IO blocked'       "$TESTS_DIR/BadExample.cs" 1 'System.IO' ''
run_case 'multi-dim array blocked' "$TESTS_DIR/BadExample.cs" 1 'Multi-dimensional arrays' ''
run_case 'missing RequestSerialization flagged' "$TESTS_DIR/BadExample.cs" 1 'never calls RequestSerialization()' ''
run_case 'missing ownership guard flagged'      "$TESTS_DIR/BadExample.cs" 1 'no ownership check' ''

# --- false positives are suppressed ----------------------------------------

run_case 'compliant file passes'   "$TESTS_DIR/GoodExample.cs" 0 'PASS' 'BLOCKED'
run_case 'comments do not trip rules' "$TESTS_DIR/GoodExample.cs" 0 'PASS' 'List<T> is not supported'
run_case 'strings do not trip rules'  "$TESTS_DIR/GoodExample.cs" 0 'PASS' 'Lambda expressions'
run_case 'plain C# skips udon rules'  "$TESTS_DIR/PlainCSharp.cs" 0 'PASS' 'async methods are not supported'

# --- flags ------------------------------------------------------------------

run_case '--errors-only hides warnings' "$TESTS_DIR/BadExample.cs" 1 'BLOCKED' 'WARNING' --errors-only
run_case '--no-exit-code returns 0'     "$TESTS_DIR/BadExample.cs" 0 'BLOCKED/ERROR' '' --no-exit-code

# --- directory mode ---------------------------------------------------------

out=$(bash "$VALIDATOR" "$TESTS_DIR" --errors-only 2>&1); code=$?
if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'BLOCKED'; then
    printf '  PASS  directory mode scans recursively\n'; PASS=$((PASS + 1))
else
    printf '  FAIL  directory mode scans recursively (exit=%s)\n' "$code"; FAIL=$((FAIL + 1))
fi

# --- bad input --------------------------------------------------------------

bash "$VALIDATOR" "$TESTS_DIR/does-not-exist.cs" >/dev/null 2>&1
[ $? -eq 2 ] && { printf '  PASS  missing path exits 2\n'; PASS=$((PASS + 1)); } || { printf '  FAIL  missing path exits 2\n'; FAIL=$((FAIL + 1)); }

bash "$VALIDATOR" "$TESTS_DIR/run-tests.sh" >/dev/null 2>&1
[ $? -eq 2 ] && { printf '  PASS  non-.cs file exits 2\n'; PASS=$((PASS + 1)); } || { printf '  FAIL  non-.cs file exits 2\n'; FAIL=$((FAIL + 1)); }

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf 'all %s checks passed\n' "$PASS"
    exit 0
fi
printf '%s passed, %s FAILED\n' "$PASS" "$FAIL"
exit 1

#!/usr/bin/env bash
# udon-validate — UdonSharp static validator (POSIX shell, zero dependencies)
#
# Usage:
#   ./tools/udon-validate/udon-validate.sh <file.cs | directory> [--errors-only] [--no-exit-code]
#
# Exit codes: 0 = pass or warnings only, 1 = BLOCKED/ERROR found, 2 = bad input
#
# Requires: bash 3.2+, awk, grep, sed — standard on macOS, Linux, WSL, Git Bash.
# Does NOT require jq, python, node, or network access.
#
# Rules live in rules.tsv (same directory). This script is a generic engine:
# adding or correcting a rule means editing that file, not this script.

set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RULES_FILE="$SELF_DIR/rules.tsv"

ERRORS_ONLY=0
NO_EXIT_CODE=0
TARGET=""

for arg in "$@"; do
    case "$arg" in
        --errors-only)  ERRORS_ONLY=1 ;;
        --no-exit-code) NO_EXIT_CODE=1 ;;
        -h|--help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        -*)
            printf 'udon-validate: unknown option: %s\n' "$arg" >&2
            exit 2 ;;
        *)
            [ -z "$TARGET" ] && TARGET="$arg" ;;
    esac
done

if [ -z "$TARGET" ]; then
    printf 'usage: %s <file.cs | directory> [--errors-only] [--no-exit-code]\n' "$0" >&2
    exit 2
fi
if [ ! -e "$TARGET" ]; then
    printf 'udon-validate: no such path: %s\n' "$TARGET" >&2
    exit 2
fi
if [ ! -f "$RULES_FILE" ]; then
    printf 'udon-validate: rules file missing: %s\n' "$RULES_FILE" >&2
    exit 2
fi

# ---- collect files --------------------------------------------------------

FILES=""
if [ -d "$TARGET" ]; then
    FILES=$(find "$TARGET" -type f -name '*.cs' 2>/dev/null | sort)
    if [ -z "$FILES" ]; then
        printf 'udon-validate: no .cs files under: %s\n' "$TARGET" >&2
        exit 2
    fi
else
    case "$TARGET" in
        *.cs) FILES="$TARGET" ;;
        *)    printf 'udon-validate: not a .cs file: %s\n' "$TARGET" >&2; exit 2 ;;
    esac
fi

# ---- masking --------------------------------------------------------------
# Blank out comments and string/char literals so prose never trips a rule.
# Offsets are preserved (each masked char becomes a space), so line numbers
# stay meaningful. Conservative scanner, not a full C#/JS tokenizer.

mask_source() {
    awk '
    BEGIN { in_block=0; in_str=0; in_verb=0; in_char=0; esc=0 }
    {
        line=$0; out=""; i=1; n=length(line); in_line=0
        while (i<=n) {
            c=substr(line,i,1); c2=substr(line,i,2)
            if (in_block) {
                if (c2=="*/") { out=out "  "; i+=2; in_block=0; continue }
                out=out " "; i++; continue
            }
            if (in_line) { out=out " "; i++; continue }
            if (in_str) {
                if (esc) { out=out " "; i++; esc=0; continue }
                if (c=="\\") { out=out " "; i++; esc=1; continue }
                if (c=="\"") { out=out " "; i++; in_str=0; continue }
                out=out " "; i++; continue
            }
            if (in_verb) {
                if (c=="\"") {
                    if (substr(line,i+1,1)=="\"") { out=out "  "; i+=2; continue }
                    out=out " "; i++; in_verb=0; continue
                }
                out=out " "; i++; continue
            }
            if (in_char) {
                if (esc) { out=out " "; i++; esc=0; continue }
                if (c=="\\") { out=out " "; i++; esc=1; continue }
                if (c=="\047") { out=out " "; i++; in_char=0; continue }
                out=out " "; i++; continue
            }
            if (c2=="//") { out=out "  "; i+=2; in_line=1; continue }
            if (c2=="/*") { out=out "  "; i+=2; in_block=1; continue }
            if (c=="\"") { out=out " "; i++; in_str=1; continue }
            if (c=="\047") { out=out " "; i++; in_char=1; continue }
            if (c=="@" && substr(line,i+1,1)=="\"") { out=out "  "; i+=2; in_verb=1; continue }
            out=out c; i++
        }
        print out
    }'
}

# ---- evaluate one file ----------------------------------------------------
# load_rules / run_rules use globals deliberately; the script runs sequentially.

TOTAL_FILES=0
REPORTED_FILES=0
BLOCKED_COUNT=0
WARN_COUNT=0

MASKED=$(mktemp "${TMPDIR:-/tmp}/udon-validate.XXXXXX") || exit 2
trap 'rm -f "$MASKED"' EXIT INT TERM

for f in $FILES; do
    [ -f "$f" ] || continue
    TOTAL_FILES=$((TOTAL_FILES + 1))

    mask_source < "$f" > "$MASKED"

    # Scope check runs on masked text, so a comment that mentions
    # UdonSharpBehaviour does not make a plain C# file count as Udon code.
    IS_UDON=0
    if grep -q 'UdonSharpBehaviour' "$MASKED" 2>/dev/null; then
        IS_UDON=1
    fi

    FILE_OUT=""
    while IFS='	' read -r level id scope kind pattern absent message; do
        case "$level" in ''|'#'*) continue ;; esac
        [ -n "${pattern:-}" ] || continue
        if [ "$scope" = "udon" ] && [ "$IS_UDON" -ne 1 ]; then continue; fi
        if [ "$level" = "WARNING" ] && [ "$ERRORS_ONLY" -eq 1 ]; then continue; fi

        # `literal` patterns are compared verbatim, so C# punctuation such as
        # `(` or `[` cannot be misread as regex syntax. Others use ERE.
        case "${kind:-regex}" in
            literal) if grep -q -F -- "$pattern" "$MASKED" 2>/dev/null; then HIT=1; else HIT=0; fi ;;
            *)       if grep -q -E -- "$pattern" "$MASKED" 2>/dev/null; then HIT=1; else HIT=0; fi ;;
        esac

        # `absent` turns a rule into "A is present but B is missing", which is
        # what actually indicates a bug. Without it, a rule like "[UdonSynced]"
        # fires on every correct file and gets ignored.
        if [ "$HIT" -eq 1 ] && [ -n "${absent:-}" ] && [ "$absent" != "-" ]; then
            if grep -q -E -- "$absent" "$MASKED" 2>/dev/null; then
                HIT=0
            fi
        fi

        if [ "$HIT" -eq 1 ]; then
            FILE_OUT="$FILE_OUT$(printf '  %-8s %s\n' "$level" "$message")
"
            case "$level" in
                BLOCKED|ERROR) BLOCKED_COUNT=$((BLOCKED_COUNT + 1)) ;;
                *)             WARN_COUNT=$((WARN_COUNT + 1)) ;;
            esac
        fi
    done < "$RULES_FILE"

    if [ -n "$FILE_OUT" ]; then
        REPORTED_FILES=$((REPORTED_FILES + 1))
        printf '\n-- %s\n' "${f#"$PWD"/}"
        printf '%s' "$FILE_OUT"
    fi
done

printf '\n'
if [ "$BLOCKED_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
    printf 'udon-validate: PASS - %s file(s), no findings\n' "$TOTAL_FILES"
    exit 0
fi

if [ "$ERRORS_ONLY" -eq 1 ]; then
    printf 'udon-validate: %s/%s file(s) - BLOCKED/ERROR %s\n' \
        "$REPORTED_FILES" "$TOTAL_FILES" "$BLOCKED_COUNT"
else
    printf 'udon-validate: %s/%s file(s) - BLOCKED/ERROR %s, WARNING %s\n' \
        "$REPORTED_FILES" "$TOTAL_FILES" "$BLOCKED_COUNT" "$WARN_COUNT"
fi

[ "$NO_EXIT_CODE" -eq 1 ] && exit 0
[ "$BLOCKED_COUNT" -gt 0 ] && exit 1
exit 0

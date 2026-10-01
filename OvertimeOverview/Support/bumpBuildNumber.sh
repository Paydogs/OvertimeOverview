#!/bin/sh
# Bump the build counter once per archive; runs as the scheme's archive PRE-action so the
# value is final before any target builds — both stamp phases then read the same number.
set -eu

FILE="$SRCROOT/Support/buildNumber"

CUR=$(cat "$FILE" 2>/dev/null || true)
case "$CUR" in
    ''|*[!0-9]*) CUR=0 ;;
esac
# Strip leading zeros: shell arithmetic would treat e.g. "08" as octal.
CUR=$(echo "$CUR" | sed 's/^0*//')
[ -n "$CUR" ] || CUR=0

# max(counter, commit count) + 1: a fresh clone where the counter file is stale/absent
# still rises above any number reachable from committed history.
if ROOT=$(git -C "$SRCROOT" rev-parse --show-toplevel 2>/dev/null); then
    BASE=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)
    case "$BASE" in ''|*[!0-9]*) BASE=0 ;; esac
    if [ "$BASE" -gt "$CUR" ]; then CUR=$BASE; fi
    REL=${FILE#"$ROOT"/}
    if ! git -C "$ROOT" diff --quiet HEAD -- "$REL" 2>/dev/null; then
        echo "warning: Support/buildNumber has uncommitted changes — commit it after archiving, or a fresh clone can regress below numbers App Store Connect has already seen."
    fi
fi

NEXT=$((CUR + 1))
printf '%s\n' "$NEXT" > "$FILE"
echo "Build number bumped to $NEXT"

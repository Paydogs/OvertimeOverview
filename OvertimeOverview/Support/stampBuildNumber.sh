#!/bin/sh
# Stamp the bumped counter as CFBundleVersion into the built plist. Shared by the app and
# widget post-actions; fails the archive loudly rather than letting the two diverge.
set -eu
[ "$ACTION" = "install" ] || exit 0

FILE="$SRCROOT/Support/buildNumber"
CUR=$(cat "$FILE" 2>/dev/null || true)
case "$CUR" in
    ''|*[!0-9]*)
        echo "error: build counter is missing or not a number: '$CUR'" >&2
        exit 1
        ;;
esac

PLIST="$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH"
if [ ! -f "$PLIST" ]; then
    echo "error: plist not found: $PLIST" >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CUR" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $CUR" "$PLIST"

#!/bin/sh
# platform: macOS-only -- pkgutil expands the shim's pkg and lipo reads the static library's slices
set -eu
here=$(cd "$(dirname "$0")/../build" && pwd)          # test/ -> build/
TMP=$(mktemp -d "${TMPDIR:-/tmp}/legacy-support-fetch.XXXXXX"); trap 'rm -rf "$TMP"' EXIT   # template: 10.9 BSD mktemp requires one
export MAVERICKS_WORK="$TMP/work"                     # keep all artifacts out of the repo

A=$(sh "$here/build-legacy-support.sh" | tail -1)
[ -f "$A" ] || { echo "FAIL: no .a at '$A'"; exit 1; }
[ "$A" = "$MAVERICKS_WORK/legacy-support/lib/libMacportsLegacySupport.a" ] \
  || { echo "FAIL: unexpected .a path: $A"; exit 1; }
[ "$(lipo -info "$A" | sed -n 's/.*: //p' | xargs)" = x86_64 ] || { echo "FAIL: .a not x86_64-only"; exit 1; }
[ -d "$MAVERICKS_WORK/legacy-support/include/LegacySupport" ] \
  || { echo "FAIL: LegacySupport headers not extracted"; exit 1; }

# Tamper: corrupt the cached pkg; the next run must fail the SHA256SUMS check (fail-closed).
pkg=$(find "$MAVERICKS_WORK/legacy-support-dl" -type f -name '*.pkg' | head -1)
[ -n "$pkg" ] || { echo "FAIL: cached pkg not found"; exit 1; }
echo garbage >> "$pkg"
if sh "$here/build-legacy-support.sh" >/dev/null 2>&1; then
  echo "FAIL: tampered pkg was not caught"; exit 1
fi
echo "legacy-support-fetch OK"

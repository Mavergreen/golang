#!/bin/sh
# version.sh: derives <upstream>-mavericks.N + RELEASE decision. Upstream is read from
# UPSTREAM_VERSION (NOT hardcoded) so a Renovate bump never breaks this test.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../build/version.sh"
# Per-line upstream: a Go minor line is a product here (lines/126, lines/127, ...).
GO_LINE="${GO_LINE:-126}"
U="$(tr -d '[:space:]' < "$here/../lines/$GO_LINE/UPSTREAM_VERSION")"

# auto, no existing tags -> N=1, RELEASE=yes
out="$(MAVERICKS_TAGS='' sh "$script" auto)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.1$"  || { echo "FAIL auto/new FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=yes$'            || { echo "FAIL auto/new REL: $out"; exit 1; }

# auto, existing tags -> N=max, RELEASE=no
out="$(MAVERICKS_TAGS="${U}-mavericks.1
${U}-mavericks.3
${U}-mavericks.2" sh "$script" auto)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.3$"  || { echo "FAIL auto/exist FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=no$'             || { echo "FAIL auto/exist REL: $out"; exit 1; }

# local -> N=max+1, RELEASE=yes
out="$(MAVERICKS_TAGS="${U}-mavericks.3" sh "$script" local)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.4$"  || { echo "FAIL local FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=yes$'            || { echo "FAIL local REL: $out"; exit 1; }

echo "PASS: version"

# GO_LINE is DERIVED from the upstream version, not configured. Two sources of truth for "which
# line is this" is how a repo ends up building 1.26 and stamping a go127 pkg identifier.
R="$here/.."
derived="$(GO_LINE= sh "$R/build/version.sh" line)"
[ "$derived" = 126 ] || { echo "FAIL: derived line '$derived', expected 126"; exit 1; }

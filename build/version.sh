#!/bin/sh
# Thin wrapper: the logic lives in shipyard (scripts/version.sh) so it cannot drift between repos.
# Every call site -- tests/version-test.sh, build/versions.sh, the release workflow, and a plain
# `sh build/version.sh auto` -- keeps working through this.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT

# This repo ships parallel Go minor LINES (go126, and a future go127) as separate products, so the
# upstream version is per line rather than a single file at the root. Everything else -- the shared
# logic, the tag scan, the RELEASE decision -- is unchanged.
# The LINE is derived from the upstream version (1.26.5 -> 126), never configured separately:
# CMakeLists.txt already derives MAVGO_LINE the same way, and two sources of truth for "which line
# is this" is how a repo builds 1.26 and stamps a go127 identifier. $GO_LINE is still honoured so a
# caller can build a line whose files live elsewhere, but it is no longer required.
_up_root="$MAVERICKS_ROOT/UPSTREAM_VERSION"
[ -f "$_up_root" ] || _up_root="$MAVERICKS_ROOT/lines/${GO_LINE:-126}/UPSTREAM_VERSION"
[ -f "$_up_root" ] || { echo "version.sh: no UPSTREAM_VERSION at repo root or lines/" >&2; exit 1; }
GO_LINE="${GO_LINE:-$(tr -d '[:space:]' < "$_up_root" | sed -n 's/^\([0-9]*\)\.\([0-9]*\)\..*$/\1\2/p')}"
[ -n "$GO_LINE" ] || { echo "version.sh: cannot derive GO_LINE from $_up_root" >&2; exit 1; }
export GO_LINE
MAVERICKS_UPSTREAM_FILE="$_up_root"; export MAVERICKS_UPSTREAM_FILE
if [ "${1:-}" = line ]; then printf '%s\n' "$GO_LINE"; exit 0; fi

. "$SELF/msc.sh"
exec sh "$SHIPYARD/version.sh" "$@"

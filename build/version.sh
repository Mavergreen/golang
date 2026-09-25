#!/bin/sh
# platform: host-agnostic
# Thin wrapper: the logic lives in shipyard (scripts/version.sh) so it cannot drift between repos.
# Every call site -- tests/version-test.sh, build/versions.sh, the release workflow, and a plain
# `sh build/version.sh auto` -- keeps working through this.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT

# One repo ships ONE Go minor LINE, from the root UPSTREAM_VERSION -- never a per-line file. The
# LINE is derived from the upstream version (1.26.5 -> 126), never configured separately:
# CMakeLists.txt already derives MAVGO_LINE the same way, and two sources of truth for "which line
# is this" is how a repo builds 1.26 and stamps a go127 identifier. A caller-supplied $GO_LINE is
# honoured only as a CHECK against the derived value, never as an override -- pairing GO_LINE=127
# with a 1.26.x UPSTREAM_VERSION is a bug, not a way to build a different line.
_up_root="$MAVERICKS_ROOT/UPSTREAM_VERSION"
[ -f "$_up_root" ] || { echo "version.sh: no UPSTREAM_VERSION at repo root" >&2; exit 1; }
_derived_line="$(tr -d '[:space:]' < "$_up_root" | sed -n 's/^\([0-9]*\)\.\([0-9]*\)\..*$/\1\2/p')"
[ -n "$_derived_line" ] || { echo "version.sh: cannot derive GO_LINE from $_up_root" >&2; exit 1; }
if [ -n "${GO_LINE:-}" ] && [ "$GO_LINE" != "$_derived_line" ]; then
  echo "version.sh: GO_LINE=$GO_LINE was given but $_up_root derives $_derived_line -- one source of truth" >&2
  exit 1
fi
GO_LINE="$_derived_line"
export GO_LINE
MAVERICKS_UPSTREAM_FILE="$_up_root"; export MAVERICKS_UPSTREAM_FILE
if [ "${1:-}" = line ]; then printf '%s\n' "$GO_LINE"; exit 0; fi

. "$SELF/msc.sh"
exec sh "$SHIPYARD/version.sh" "$@"

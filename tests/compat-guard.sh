#!/bin/sh
# platform: macOS-only -- shipyard's assert_binary_compatible.sh reads Mach-O load commands with otool
set -eu
# Resolve the shared compat guard from mavericks-shipyard's INSTALLED location
# (via versions.sh's SHIPYARD_SCRIPTS resolver -- registry/prefix, not a sibling copy).
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../build/versions.sh"
: "${SHIPYARD_SCRIPTS:?mavericks-shipyard not found; install it -- see its README}"
# Called with no binaries (as the shared test runner does, before anything is built) there is nothing
# to guard yet: exit 77 = SKIP, the family convention. The real gate is the explicit post-build
# invocation in release.yml, which passes the shipped binaries.
[ "$#" -gt 0 ] || { echo "no binaries given (nothing built yet) -- skipping"; exit 77; }
MAVERICKS_REQUIRE_DEFINED_SYMBOLS='_clock_gettime' sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$@"

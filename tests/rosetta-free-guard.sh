#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
fail=0
say() { echo "GUARD: $1"; }
# Match CODE only, not prose: strip comments (# to end of line) before grepping, so
# a comment that *describes* the removed antipattern doesn't trip the guard.
code() { sed 's/#.*//' "$1"; }

# build-native.sh must never do an amd64-host make.bash, nor arch-shim to x86_64.
if code "$root/build/build-native.sh" | grep -Eq 'GOHOSTARCH=amd64'; then
  say "FAIL: build-native.sh sets GOHOSTARCH=amd64 (would run amd64 under Rosetta)"; fail=1
fi
if code "$root/build/build-native.sh" | grep -Eq 'arch[[:space:]]+-(-?)(arch[[:space:]]+)?x86_64'; then
  say "FAIL: build-native.sh invokes \`arch ... x86_64\` (amd64 execution)"; fail=1
fi
# It must run a native make.bash (host arch left to the arm64 bootstrap).
grep -q 'make.bash' "$root/build/build-native.sh" || { say "FAIL: no make.bash in build-native.sh"; fail=1; }

# release.yml must not gate the build on Rosetta: any Rosetta install must be
# best-effort (|| true) AND must not be a standalone pre-build prerequisite step.
wf="$root/.github/workflows/release.yml"
if grep -Eq 'install-rosetta' "$wf"; then
  grep -Eq 'install-rosetta[^|]*\|\|[[:space:]]*true' "$wf" || {
    say "FAIL: release.yml installs Rosetta without '|| true' (build would depend on it)"; fail=1; }
fi

[ "$fail" -eq 0 ] && say "OK: native build path is Rosetta-free" || exit 1

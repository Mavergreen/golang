#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/../.."
fail=0
# Directories to scan. 'test' never existed -- a grep aimed at a missing directory checks nothing
# while still looking like a guard.
scan="patches build tests"
if grep -ril pkgsrc $scan 2>/dev/null | grep -v rename-check.sh | grep -q .; then
  echo "FAIL: 'pkgsrc' still present:"; grep -ril pkgsrc $scan | grep -v rename-check.sh
  fail=1
fi
[ -f build/extract-patches.sh ] && { echo "FAIL: extract-patches.sh not removed"; fail=1; }
# Patches live under patches/ at the repo root now: one repo ships one line, and this repo owns
# exactly one patch set.
for f in patches/0007-root-keychainunion.patch patches/0008-root-keychainunion-darwin.patch patches/0009-root-keychainunion-test.patch; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; }
done
[ "$fail" = 0 ] && echo "rename-check OK"
exit $fail

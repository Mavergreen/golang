#!/bin/sh
# Build the patched go126 for the HOST and run the keychain-union trust unit tests.
# The trust logic (buildKeychainUnionPool, the veto, and the env resolver) is
# build-tag-free, so a host build on macOS exercises it. This is the automated gate
# the trust patches previously lacked. Needs a Go >=1.24 bootstrap.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# Isolated work dir so this never collides with build-native's $WORK/go.
export MAVERICKS_WORK="${MAVERICKS_WORK:-$HOME/.cache/mavericks-golang/work}/trusttest"
# versions.sh defaults REPO_ROOT from dirname($0), assuming a one-level-deep
# sourcer (build/*.sh). `.` (source) never rebinds $0, and this script lives
# two levels down (test/trust/), so that default would land in test/, not the
# repo root. Set it explicitly from $here instead.
export REPO_ROOT="$(cd "$here/../.." && pwd)"
. "$here/../../build/versions.sh"
: "${GOROOT_BOOTSTRAP:=$( (command -v go >/dev/null 2>&1 && go env GOROOT) || true )}"
[ -n "${GOROOT_BOOTSTRAP:-}" ] && [ -d "$GOROOT_BOOTSTRAP" ] \
  || { echo "FATAL: set GOROOT_BOOTSTRAP to a Go >=1.24 GOROOT" >&2; exit 1; }

rm -rf "$WORK/go"
sh "$here/../../build/fetch-go.sh"
sh "$here/../../build/apply-patches.sh"
( cd "$WORK/go/src" && GOROOT_BOOTSTRAP="$GOROOT_BOOTSTRAP" ./make.bash ) 1>&2
out=$(GOROOT="$WORK/go" "$WORK/go/bin/go" test crypto/x509 -run 'KeychainUnion|Fallback' -count=1 -v 2>&1)
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^ok[[:space:]]' || { echo "FATAL: crypto/x509 trust tests did not pass" >&2; exit 1; }
# On CI a skipped trust test is a failure: the Apple-verifier tests skip only when the host's
# keychain doesn't trust the fixture, and CI's macOS does, so a skip there hides a broken path.
# Subtests print indented, so match any leading space.
if [ -n "${CI:-}" ]; then
  skipped=$(printf '%s\n' "$out" | grep -E '^[[:space:]]*--- SKIP: Test[A-Za-z_]*KeychainUnion' || true)
  [ -z "$skipped" ] || { printf 'FATAL: KeychainUnion tests skipped on CI (they must run):\n%s\n' "$skipped" >&2; exit 1; }
fi
passed=$(printf '%s\n' "$out" | grep -c '^--- PASS: Test[A-Za-z_]*KeychainUnion')
# Top-level tests only: 9 portable + 6 darwin, all of which run on CI (the skip guard above).
[ "$passed" -ge 15 ] || { echo "FATAL: expected >=15 KeychainUnion tests to run+pass, saw $passed -- did -run match nothing?" >&2; exit 1; }
for t in TestFallback TestFallbackPanic; do
  printf '%s\n' "$out" | grep -q "^--- PASS: $t " || { echo "FATAL: upstream $t did not pass" >&2; exit 1; }
done
echo "unit-trust OK ($passed trust tests passed)"

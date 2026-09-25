#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/versions.sh"
mkdir -p "$WORK"
tarball="$WORK/go${GO_VERSION}.src.tar.gz"
[ -f "$tarball" ] || curl -fSL -o "$tarball" "$GO_SRC_URL"

# Verify against go.dev's OWN published SHA256 (fetched fresh; not pinned in-repo).
# This makes a Renovate version bump self-contained — no committed hash to sync.
want=$(sh "$here/go-src-sha256.sh" "$GO_VERSION")
[ -n "$want" ] || { echo "FATAL: no sha256 for go${GO_VERSION} in go.dev feed" >&2; exit 1; }
got=$(shasum -a 256 "$tarball" | awk '{print $1}')
[ "$got" = "$want" ] || { echo "FATAL: go src SHA256 mismatch: got $got want $want" >&2; exit 1; }

rm -rf "$WORK/go"
tar -C "$WORK" -xzf "$tarball"
test -f "$WORK/go/src/make.bash" || { echo "FATAL: unexpected archive layout" >&2; exit 1; }
echo "fetched + verified go${GO_VERSION} (sha256 $got) -> $WORK/go"

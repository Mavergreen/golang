#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../build/versions.sh"
# This is an ON-BOX smoke: it needs a real 10.9 machine reachable over passwordless ssh. Without one
# there is nothing to smoke, so exit 77 = SKIP (the family convention) rather than fail -- a CI runner
# was never going to have a Mavericks box.
[ -n "${MAVERICKS_HOST:-}" ] || { echo "MAVERICKS_HOST unset (no 10.9 box) -- skipping"; exit 77; }
MODE="${1:-staged}"   # staged | installer
stage="$WORK/staging"

if [ "$MODE" = installer ]; then
  pkg="$WORK/out/golang-${GO_VERSION}-native-${PKG_VERSION#*-}.pkg"
  test -f "$pkg" || { echo "run package-pkg.sh first" >&2; exit 1; }
  rsync -a "$pkg" "$MAVERICKS_HOST:/tmp/go126.pkg"
  ssh "$MAVERICKS_HOST" "sudo installer -pkg /tmp/go126.pkg -target /"
else
  test -x "$stage$PREFIX/bin/go" || { echo "run build-native.sh first" >&2; exit 1; }
  # /usr/local needs root on the box; use passwordless sudo (rsync as root).
  # Remove+recreate the dir (no glob: the remote shell is zsh, which errors on
  # an empty `$PREFIX/*` match).
  ssh "$MAVERICKS_HOST" "sudo rm -rf $PREFIX && sudo mkdir -p $PREFIX"
  rsync -a --delete --rsync-path="sudo rsync" "$stage$PREFIX/" "$MAVERICKS_HOST:$PREFIX/"
fi

ssh "$MAVERICKS_HOST" "mkdir -p /tmp/hello-cgo"
rsync -a "$here/hello-cgo/" "$MAVERICKS_HOST:/tmp/hello-cgo/"
# No CGO_ENABLED/CGO_LDFLAGS/CC here on purpose: the shipped $GOROOT/go.env bakes
# them in, so a plain `go build` must work out-of-the-box on the 10.9 box.
ssh "$MAVERICKS_HOST" "sh -c '
  set -e
  export PATH=$PREFIX/bin:\$PATH GOROOT=$PREFIX
  export GOCACHE=/tmp/gocache GOPATH=/tmp/gopath
  go version
  rm -rf /tmp/hb && cp -r /tmp/hello-cgo /tmp/hb && cd /tmp/hb
  (test -f go.mod || go mod init hello-cgo) && go build -o /tmp/hello . && /tmp/hello
'"

# Pure-Go programs (no cgo, CGO_ENABLED=0, go test binaries) must run too -- see tests/pure-go-link.sh.
rsync -a "$here/pure-go-link.sh" "$MAVERICKS_HOST:/tmp/pure-go-link.sh"
ssh "$MAVERICKS_HOST" "PURE_GO_GOROOT=$PREFIX sh /tmp/pure-go-link.sh"

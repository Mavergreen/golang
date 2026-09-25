#!/bin/sh
# platform: macOS-only -- runs the darwin/arm64 cross toolchain and reads the Mach-O it emits with otool
# Cross-build the sample app on THIS arm64 host with the -cross toolchain (no env needed: go.env
# defaults GOOS/GOARCH/CC), guard it as a 10.9 binary, and run it on the real 10.9 box.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$here/../.." && pwd)"; export REPO_ROOT   # test/cross is two levels down
. "$REPO_ROOT/build/versions.sh"
: "${MAVERICKS_HOST:?set MAVERICKS_HOST}"
stage="$WORK/staging-cross"
test -x "$stage$CROSS_PREFIX/bin/go" || { echo "run build-cross.sh first" >&2; exit 1; }

export PATH="$stage$CROSS_PREFIX/bin:$PATH" GOROOT="$stage$CROSS_PREFIX"
export GOCACHE="$WORK/.gc-xtest" GOPATH="$WORK/.gp-xtest"
# go.env's CC is the INSTALL path; for a staged (uninstalled) test, point at the staged wrapper
# (which self-locates its own lib/libexec). Env overrides go.env.
export CC="$stage$CROSS_PREFIX/bin/mavericks-cross-clang"
cd "$here/sample" && (test -f go.mod || go mod init sample) >/dev/null 2>&1
rm -rf "$GOCACHE"   # force a clean cross-compile of std + cgo
go build -o /tmp/xsample .

echo "=== the cross-built app is a 10.9 amd64 binary ==="
file /tmp/xsample
otool -l /tmp/xsample | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&/version/{print;exit}'
sh "$here/../compat-guard.sh" /tmp/xsample

echo "=== run it on the real 10.9 box (native .pkg there provides the CA) ==="
rsync -a /tmp/xsample "$MAVERICKS_HOST:/tmp/xsample"
ssh "$MAVERICKS_HOST" 'unset HTTPS_PROXY HTTP_PROXY ALL_PROXY GODEBUG; /tmp/xsample'

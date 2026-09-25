#!/bin/sh
# platform: macOS-only -- runs the staged darwin/amd64 toolchain under Rosetta
# Best-effort: run the STAGED amd64 toolchain under emulation as a pre-publish sanity
# gate -- does the cross-produced amd64 `go` actually execute, compile, link, and run
# a program? Skips cleanly (exit 0) when amd64 execution is unavailable; must NEVER
# fail the build. Uses a pure-Go program (CGO_ENABLED=0): the staged go.env bakes the
# ABSOLUTE install CC path (/usr/local/mavergreen/go126/bin/mavericks-clang) + shim, which only
# exist once installed, so cgo is validated by the on-box 10.9 smoke, not here. The
# authoritative runtime gate is the real 10.9 box.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../build/versions.sh"
stage="$WORK/staging$PREFIX"
go_bin="$stage/bin/go"
[ -x "$go_bin" ] || { echo "selftest: no staged go -- skip"; exit 0; }

# Can this host execute an amd64 Mach-O at all? (Rosetta present + working.)
if ! "$go_bin" version >/dev/null 2>&1; then
  echo "selftest: amd64 exec unavailable (no Rosetta) -- skip"; exit 0
fi

echo "selftest: $("$go_bin" version)"
tmp="$WORK/selftest"; rm -rf "$tmp"; mkdir -p "$tmp"
cat > "$tmp/main.go" <<'GO'
package main

import "fmt"

func main() { fmt.Println("mavericks-go126 amd64 toolchain ok") }
GO
cd "$tmp"
# GO_EXTLINK_ENABLED=0: the staged CC wrapper names install paths absent here; internal-link just to prove amd64 exec.
PATH="$stage/bin:$PATH" GOROOT="$stage" GOFLAGS= CGO_ENABLED=0 GO_EXTLINK_ENABLED=0 \
GOCACHE="$WORK/.gocache-selftest" GOPATH="$tmp/gp" \
  sh -c 'go mod init selftest >/dev/null 2>&1; go build -o prog . && ./prog'
echo "selftest: staged amd64 toolchain compiled + linked + ran a program under emulation: OK"
echo "selftest: (cgo/TLS validated by the on-box 10.9 smoke, not here)"

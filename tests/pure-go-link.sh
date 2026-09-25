#!/bin/sh
# platform: macOS-only -- builds darwin/amd64 programs with the toolchain and inspects their Mach-O
# A PURE-Go program (no cgo) built by our toolchain must be 10.9-safe: external-linked through the
# CC wrapper (legacy shim + 10.9 minimum), not internal-linked to Go's 12.0 floor with clock_gettime
# unresolved. Covers the default build, CGO_ENABLED=0 and a `go test` binary, and checks that a
# cross-OS build (GOOS=linux CGO_ENABLED=0) still links internally.
#   On the 10.9 box: builds AND runs.            PURE_GO_GOROOT=/usr/local/mavergreen/go126 sh pure-go-link.sh
#   Elsewhere (CI):  builds with the staged cross toolchain and inspects the Mach-O + compat guard.
# No toolchain to test -> exit 77 (SKIP).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"

on_109=no
case "$(sw_vers -productVersion 2>/dev/null)" in 10.9|10.9.*) on_109=yes ;; esac

if [ -n "${PURE_GO_GOROOT:-}" ]; then
  goroot="$PURE_GO_GOROOT"
else
  . "$here/../build/versions.sh"
  if [ "$on_109" = yes ]; then
    goroot="$PREFIX"
  else
    goroot="$WORK/staging-cross$CROSS_PREFIX"
    # Staged, not installed: go.env's CC names the install path, so use the staged wrapper.
    export CC="$goroot/bin/mavericks-cross-clang"
  fi
fi
[ -x "$goroot/bin/go" ] || { echo "no toolchain at $goroot -- skipping"; exit 77; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/purego.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export GOROOT="$goroot" PATH="$goroot/bin:$PATH" GOCACHE="$tmp/gocache" GOPATH="$tmp/gopath" GOFLAGS=
unset GO_EXTLINK_ENABLED GOOS GOARCH CGO_ENABLED
mkdir -p "$tmp/app"
cat > "$tmp/app/main.go" <<'EOF'
package main

import (
	"fmt"
	"time"
)

// time.Now reaches clock_gettime, which 10.9's libSystem lacks: the legacy shim must be linked in.
func main() { fmt.Println("pure-go ok", time.Now().Year() > 2000) }
EOF
cat > "$tmp/app/main_test.go" <<'EOF'
package main

import "testing"

func TestPure(t *testing.T) {}
EOF
printf 'module purego\n\ngo 1.26\n' > "$tmp/app/go.mod"
cd "$tmp/app"

fail=0
check() { # binary label
  if [ "$on_109" = yes ]; then
    if out="$("$1" 2>&1)"; then echo "ok   [$2]: runs on 10.9: $(printf '%s' "$out" | tail -1)"
    else echo "FAIL [$2]: does not run on 10.9: $out"; fail=1; fi
  else
    minos="$(otool -l "$1" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&/ version /{print $2; exit}')"
    if [ "$minos" != "10.9" ]; then echo "FAIL [$2]: no LC_VERSION_MIN_MACOSX 10.9 (got '${minos:-none}'; internal-linked?)"; fail=1
    elif ! sh "$here/compat-guard.sh" "$1" >/dev/null 2>&1; then echo "FAIL [$2]: compat guard"; fail=1
    else echo "ok   [$2]: LC_VERSION_MIN_MACOSX 10.9, compat-clean"; fi
  fi
}
build() { # label, then go args
  label="$1"; shift
  if "$@"; then :; else echo "FAIL [$label]: build failed"; fail=1; return 1; fi
}
build default go build -o "$tmp/default" . && check "$tmp/default" default
build "CGO_ENABLED=0" env CGO_ENABLED=0 go build -o "$tmp/nocgo" . && check "$tmp/nocgo" "CGO_ENABLED=0"
build "go test binary" go test -c -o "$tmp/app.test" . && check "$tmp/app.test" "go test binary"
if build "GOOS=linux" env GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "$tmp/linux" .; then
  if file "$tmp/linux" | grep -q ELF; then echo "ok   [GOOS=linux]: internal-linked ELF"
  else echo "FAIL [GOOS=linux]: not an ELF binary"; fail=1; fi
fi
exit "$fail"

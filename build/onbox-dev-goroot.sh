#!/bin/sh
# 10.9 fast loop for patch work -- run ON the Mavericks box. Builds a writable GOROOT from the
# INSTALLED toolchain (its 10.9 binaries and generated sources), resets every file this line's
# patches touch to pristine upstream of the installed Go version, and re-applies the patches.
# std compiles from source on demand, so `go test crypto/x509` runs the patched code natively.
# When the patched linker knows the darwin/amd64 GO_EXTLINK_ENABLED value, bake it and rebuild
# cmd/link, as make.bash would. Re-run after every patch change. Prints the GOROOT.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$here/.." && pwd)"
GO_LINE="${GO_LINE:-126}"
installed="${INSTALLED_GOROOT:-/usr/local/go$GO_LINE}"
base="${DEV_BASE:-$HOME/.cache/mavericks-golang/dev}"
pdir="$REPO_ROOT/patches"
ca_dir="/usr/local/go$GO_LINE/etc/openssl"
[ -x "$installed/bin/go" ] || { echo "FATAL: no installed toolchain at $installed" >&2; exit 1; }
ver="$(head -1 "$installed/VERSION" | sed 's/^go//')"
pristine="$base/pristine-$ver"
goroot="$base/goroot-$ver"
mkdir -p "$base"

if [ ! -d "$pristine" ]; then
  tarball="$base/go$ver.src.tar.gz"
  curl -fsSL -o "$tarball" "https://go.dev/dl/go$ver.src.tar.gz"
  want="$(sh "$here/go-src-sha256.sh" "$ver")"
  got="$(shasum -a 256 "$tarball" | awk '{print $1}')"
  { [ -n "$want" ] && [ "$got" = "$want" ]; } || { echo "FATAL: go$ver source sha256 mismatch" >&2; exit 1; }
  rm -rf "$base/extract" && mkdir "$base/extract"
  tar -C "$base/extract" -xzf "$tarball"
  mv "$base/extract/go" "$pristine" && rmdir "$base/extract" && rm -f "$tarball"
fi
if [ ! -d "$goroot" ]; then
  mkdir -p "$goroot" && ( cd "$installed" && pax -rw . "$goroot" )
fi

# Reset what any patch touches now, or touched last run, then re-apply everything.
touched="$(grep -h '^+++ ' "$pdir"/*.patch | awk '{print $2}')"
prev="$(cat "$goroot/.dev-patched" 2>/dev/null || true)"
for rel in $(printf '%s\n%s\n' "$touched" "$prev" | sort -u); do
  if [ -f "$pristine/$rel" ]; then cp "$pristine/$rel" "$goroot/$rel"; else rm -f "$goroot/$rel"; fi
done
( cd "$goroot" && for p in "$pdir"/*.patch; do patch -s -p0 -F 3 < "$p"; done )
find "$goroot/src" -name '*.go.orig' -exec rm -f {} +
printf '%s\n' "$touched" > "$goroot/.dev-patched"
f="$goroot/src/crypto/x509/root_keychainunion_darwin.go"
if [ -f "$f" ]; then sed -i '' "s#@SSLDIR@#$ca_dir#g" "$f"; fi

zb="$goroot/src/internal/buildcfg/zbootstrap.go"
if grep -q '"darwin/amd64"' "$goroot/src/cmd/link/internal/ld/config.go"; then val='darwin\/amd64'; else val=''; fi
sed -i '' "s/^const defaultGO_EXTLINK_ENABLED = \`.*\`\$/const defaultGO_EXTLINK_ENABLED = \`$val\`/" "$zb"
GOROOT="$goroot" GO_EXTLINK_ENABLED=1 GOCACHE="$base/gocache" GOFLAGS= "$goroot/bin/go" install cmd/link >&2
echo "$goroot"

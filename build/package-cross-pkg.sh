#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild (via set_install_floor.sh) build the installer archive
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/versions.sh"
export COPYFILE_DISABLE=1
stage="$WORK/staging-cross"
test -x "$stage$CROSS_PREFIX/bin/go" || { echo "run build-cross.sh first" >&2; exit 1; }
test -x "$stage$CROSS_PREFIX/bin/mavericks-cross-clang" || { echo "FATAL: cross CC wrapper not staged" >&2; exit 1; }

out="$WORK/out"; mkdir -p "$out"
base="golang-${GO_VERSION}-cross-${PKG_VERSION#*-}"   # golang-1.26.5-cross-mavericks.<rev>
pkg="$out/$base.pkg"

: "${SHIPYARD_SCRIPTS:?mavericks-shipyard not found; install it -- see its README}"
UPD_APP="${UPD_APP:-/updater-cross/go${GO_LINE}-cross-updater.app}"
scr="$out/pkg-scripts-cross"; rm -rf "$scr"
set -- --stage "$stage" --product "go${GO_LINE}-cross" --name "Go ${GO_VERSION%.*} cross toolchain for Mavericks" \
  --group go --line "${GO_LINE}-cross" --version "$PKG_VERSION" \
  --exclude bin/mavericks-cross-clang --scripts-out "$scr"
if [ -d "$UPD_APP" ]; then
  set -- "$@" --updater-app "$UPD_APP"
else
  echo ">> WARNING: no cross updater at $UPD_APP; packaging toolchain only" >&2
fi
find "$stage" -name '._*' -delete 2>/dev/null || true
sh "$SHIPYARD_SCRIPTS/stage_product.sh" "$@"

comp="$out/golang-go${GO_LINE}-cross-component.pkg"
pkgbuild --root "$stage" --identifier "dev.mavergreen.golang.go${GO_LINE}-cross" --version "$PKG_VERSION" \
         --scripts "$scr" --install-location / "$comp"
sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" \
  --identifier "dev.mavergreen.golang.go${GO_LINE}-cross" \
  --title "go${GO_LINE}-cross — build 10.9 programs on modern macOS" \
  --component "$comp" --out "$pkg" --min-os 11.0 --host-arch arm64 --require-scripts
rm -f "$comp"
# Provenance: input pins in build/versions.sh, output hash in the release's SHA256SUMS.
echo "$pkg"

# Same record for the cross variant; conformance fails the release if the two disagree about an
# ingredient (see check-artifact-conformance.sh).
sh "$SHIPYARD_SCRIPTS/build-info.sh" "$out/build-info-cross.txt" \
  variant=cross arch=arm64 prefix="$CROSS_PREFIX" \
  go_version="$GO_VERSION" go_line="$GO_LINE" \
  mls_version="$MLS_VERSION" ca_sha256="$CA_SHA256"

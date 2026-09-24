#!/bin/sh
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

# Stage the modern Sparkle updater + shim + LaunchAgent + postinstall via the shared helper.
# Skipped if the cross updater isn't built.
: "${SHIPYARD_SCRIPTS:?mavericks-shipyard not found; install it -- see its README}"
UPD_APP="${UPD_APP:-/updater-cross/GoCrossUpdater.app}"
set --
if [ -d "$UPD_APP" ]; then
  scr="$out/pkg-scripts-cross"; rm -rf "$scr"; mkdir -p "$scr"
  sh "$SHIPYARD_SCRIPTS/stage_updater.sh" \
    --stage "$stage" \
    --app "$UPD_APP" \
    --app-dir "/Library/Application Support/Mavergreen" \
    --agent-label "dev.mavergreen.golang.go${GO_LINE}-cross-updatecheck" \
    --scripts-out "$scr"
  set -- --scripts "$scr"
else
  echo ">> WARNING: no cross updater at $UPD_APP; packaging toolchain only" >&2
fi

find "$stage" -name '._*' -delete 2>/dev/null || true

# Plain product pkg -- NO 10.9.5 floor (this installs on modern macOS, arm64 host).
pkgbuild --root "$stage" --identifier "dev.mavergreen.golang.go${GO_LINE}-cross" --version "$PKG_VERSION" \
         "$@" --install-location / "$pkg"
# Provenance: input pins in build/versions.sh, output hash in the release's SHA256SUMS.
echo "$pkg"

# Same record for the cross variant; conformance fails the release if the two disagree about an
# ingredient (see check-artifact-conformance.sh).
sh "$SHIPYARD_SCRIPTS/build-info.sh" "$out/build-info-cross.txt" \
  variant=cross arch=arm64 prefix="$CROSS_PREFIX" \
  go_version="$GO_VERSION" go_line="$GO_LINE" \
  mls_version="$MLS_VERSION" ca_sha256="$CA_SHA256"

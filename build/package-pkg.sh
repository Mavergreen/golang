#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild (via set_install_floor.sh) build the installer archive
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/versions.sh"
export COPYFILE_DISABLE=1   # no ._AppleDouble files in tar/cp payloads
stage="$WORK/staging"
test -x "$stage$PREFIX/bin/go" || { echo "run build-native.sh first" >&2; exit 1; }
test -f "$stage$PREFIX/etc/openssl/certs/ca-certificates.crt" || { echo "FATAL: CA bundle not staged" >&2; exit 1; }
test -x "$stage$PREFIX/bin/mavericks-clang" || { echo "FATAL: CC wrapper not staged" >&2; exit 1; }

out="$WORK/out"; mkdir -p "$out"
base="golang-${GO_VERSION}-native-${PKG_VERSION#*-}"   # golang-1.26.5-native-mavericks.<rev>
pkg="$out/$base.pkg"

: "${SHIPYARD_SCRIPTS:?mavericks-shipyard not found; install it -- see its README}"
UPD_APP="${UPD_APP:-/updater/go${GO_LINE}-updater.app}"
scr="$out/pkg-scripts"; rm -rf "$scr"
set -- --stage "$stage" --product "go${GO_LINE}" --name "Go ${GO_VERSION%.*} for Mavericks" \
  --group go --line "$GO_LINE" --version "$PKG_VERSION" \
  --exclude bin/mavericks-clang --scripts-out "$scr"
if [ -d "$UPD_APP" ]; then
  set -- "$@" --updater-app "$UPD_APP"
else
  echo ">> WARNING: no updater at $UPD_APP; packaging toolchain only (build it: shipyard-cmake --build)" >&2
fi
find "$stage" -name '._*' -delete 2>/dev/null || true   # strip AppleDouble cruft
sh "$SHIPYARD_SCRIPTS/stage_product.sh" "$@"

# Install resources (welcome + Go license shown at install).
RES="$out/resources"; mkdir -p "$RES"
cp "$REPO_ROOT/scripts/resources/Welcome.html" "$RES/"
[ -f "$stage$PREFIX/LICENSE" ] && cp "$stage$PREFIX/LICENSE" "$RES/LICENSE.txt" || true

comp="$out/golang-go${GO_LINE}-component.pkg"
pkgbuild --root "$stage" --identifier "dev.mavergreen.golang.go${GO_LINE}" --version "$PKG_VERSION" --scripts "$scr" --install-location / "$comp"

# Product archive with the 10.9.5 OS floor (shared helper, from the installed prefix).
HELPER="$SHIPYARD_SCRIPTS/set_install_floor.sh"
lic=""; [ -f "$RES/LICENSE.txt" ] && lic="--license LICENSE.txt"
sh "$HELPER" \
  --identifier "dev.mavergreen.golang.go${GO_LINE}" \
  --title "go${GO_LINE} — modern Go ${GO_VERSION%.*} for OS X 10.9" \
  --component "$comp" --out "$pkg" \
  --resources "$RES" --welcome Welcome.html $lic --host-arch x86_64 --require-scripts
rm -f "$comp"   # intermediate: only the floored product archive ships
# Provenance lives in versioned form: input pins in build/versions.sh, output hash in the
# release's SHA256SUMS. No separate manifest or tarball artifact.
echo "$pkg"

# Record what this variant was built FROM. The artifacts cannot say: this .pkg carries the CA bundle
# and the shim, the cross one legitimately does not, so "both were built from the same shim" is a
# claim about inputs that only the build knows. Conformance compares the two records.
sh "$SHIPYARD_SCRIPTS/build-info.sh" "$out/build-info-native.txt" \
  variant=native arch=x86_64 prefix="$PREFIX" \
  go_version="$GO_VERSION" go_line="$GO_LINE" \
  mls_version="$MLS_VERSION" ca_sha256="$CA_SHA256"

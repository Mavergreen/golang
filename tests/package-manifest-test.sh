#!/bin/sh
# platform: macOS-only -- pkgbuild, productbuild and PlistBuddy build and read the two archives
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
: "${SHIPYARD_SCRIPTS:=$R/../mavergreen-shipyard/scripts}"
[ -f "$SHIPYARD_SCRIPTS/stage_product.sh" ] || { echo "no shipyard with stage_product.sh at $SHIPYARD_SCRIPTS -- skipping" >&2; exit 77; }
command -v pkgbuild >/dev/null 2>&1 || { echo "no pkgbuild -- skipping" >&2; exit 77; }
export SHIPYARD_SCRIPTS
W="$(mktemp -d "${TMPDIR:-/tmp}/package-manifest.XXXXXX")"; trap 'rm -rf "$W"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
export MAVERICKS_WORK="$W/work" MAVERICKS_BUILD_ROOT="$W/build" UPD_APP="$W/no-updater.app"
. "$R/build/versions.sh"
mk() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n' > "$1"; chmod 755 "$1"; }
n="$WORK/staging$PREFIX"; c="$WORK/staging-cross$CROSS_PREFIX"
for f in bin/go bin/gofmt bin/mavericks-clang; do mk "$n/$f"; done
mkdir -p "$n/etc/openssl/certs"; : > "$n/etc/openssl/certs/ca-certificates.crt"
for f in bin/go bin/gofmt bin/mavericks-cross-clang; do mk "$c/$f"; done
sh "$R/build/package-pkg.sh" > "$W/native.log" 2>&1 || { cat "$W/native.log"; fail "the native archive must package from a staged tree"; }
sh "$R/build/package-cross-pkg.sh" > "$W/cross.log" 2>&1 || { cat "$W/cross.log"; fail "the cross archive must package from a staged tree"; }
V="$W/vol"; mkdir -p "$V"
for p in "$WORK"/out/golang-*-native-*.pkg "$WORK"/out/golang-*-cross-*.pkg; do
  [ -f "$p" ] || fail "no archive at $p"
  x="$W/x-$(basename "$p")"; pkgutil --expand "$p" "$x"
  [ "$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$x/Distribution" | grep -v '^default$' | head -1)" = dev.mavergreen.base ] \
    || fail "$(basename "$p"): the base component comes first"
  for comp in "$x"/*.pkg; do (cd "$V" && gzip -dc "$comp/Payload" | cpio -id --quiet); done
done
grep -q 'os-version min="11.0"' "$W"/x-golang-*-cross-*.pkg/Distribution || fail "the cross archive's floor is 11.0 (R3)"
pb() { /usr/libexec/PlistBuddy -c "Print :$2" "$V/usr/local/mavergreen/$1/mavergreen.plist"; }
[ "$(pb go126 group)/$(pb go126 line)" = go/126 ] || fail "go126 is group go, line 126"
[ "$(pb go126-cross group)/$(pb go126-cross line)" = go/126-cross ] || fail "go126-cross is group go, line 126-cross"
MG() { sh "$SHIPYARD_SCRIPTS/mavergreen.sh" --root "$V" "$@"; }
F="$V/usr/local/mavergreen/bin"
MG link go126 || fail "linking the native toolchain must succeed"
MG link go126-cross || fail "linking the cross toolchain beside the native one must succeed"
MG check || fail "a box with both toolchains installed must pass mavergreen check"
[ "$(MG select go)" = go126 ] || fail "the first member installed keeps the selection; installing the second never takes it"
[ "$(readlink "$F/go")" = ../go126/bin/go ] || fail "bare go belongs to the selected member, the native toolchain"
[ "$(readlink "$F/go-126")" = ../go126/bin/go ] || fail "go-126 runs the native toolchain"
[ "$(readlink "$F/go-126-cross")" = ../go126-cross/bin/go ] || fail "go-126-cross runs the cross toolchain, selected or not"
MG select go go126-cross || fail "select must move the go group to the cross toolchain"
[ "$(readlink "$F/go")" = ../go126-cross/bin/go ] && [ "$(readlink "$F/gofmt")" = ../go126-cross/bin/gofmt ] \
  || fail "after select, every bare name belongs to the cross toolchain"
[ "$(readlink "$F/go-126")" = ../go126/bin/go ] || fail "select leaves the native toolchain's versioned names alone"
MG check || fail "mavergreen check must stay clean after select"
for gone in mavericks-clang mavericks-clang-126 mavericks-cross-clang mavericks-cross-clang-126-cross; do
  [ ! -e "$F/$gone" ] && [ ! -L "$F/$gone" ] || fail "$gone is go.env's CC wrapper, not a user command"
done
echo "PASS: package-manifest"

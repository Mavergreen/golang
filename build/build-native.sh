#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/versions.sh"
command -v go >/dev/null || { echo "FATAL: need a stock arm64 bootstrap go on PATH" >&2; exit 1; }
GOROOT_BOOTSTRAP=$(go env GOROOT); export GOROOT_BOOTSTRAP

# 1. inputs (identical to build-cross.sh: same patched source, same shim + CA).
: "${SHIPYARD_SCRIPTS:?mavericks-shipyard not found; install it -- see its README}"
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh"); export SDK
[ -d "$SDK" ] || { echo "FATAL: 10.9 SDK not found: '$SDK'" >&2; exit 1; }
sh "$here/fetch-go.sh"
sh "$here/apply-patches.sh"
LEGACY_A=$(sh "$here/build-legacy-support.sh" | tail -1); export LEGACY_A
[ -f "$LEGACY_A" ] || { echo "FATAL: legacy-support .a not built: '$LEGACY_A'" >&2; exit 1; }
CA=$(sh "$here/fetch-ca.sh" | tail -1)
[ -f "$CA" ] || { echo "FATAL: CA bundle not produced: '$CA'" >&2; exit 1; }

# 2. Phase A -- native arm64 BUILDER toolchain. No Rosetta: bootstrap tools AND the
# 2nd-stage toolchain are arm64 and run natively (this is the fix -- the old script
# set GOHOSTARCH=amd64, so the 2nd-stage tools were amd64 and ran under Rosetta).
# min-10.9/legacy apply only to the amd64 PRODUCT (Phase C), never the builder, so
# clear every legacy/target var here -- mirrors build-cross.sh. The builder does NOT
# ship. GO_BOOTSTRAP_LDFLAGS stays unset so patches 0001/0002 leave the arm64
# bootstrap link untouched.
( unset GOOS GOARCH GOHOSTOS GOHOSTARCH GOROOT_FINAL \
        GO_LDFLAGS BOOT_GO_LDFLAGS GO_BOOTSTRAP_LDFLAGS CGO_LDFLAGS CGO_CFLAGS GO_EXTLINK_ENABLED
  # Baked into internal/buildcfg as the shipped linker's default (patches 0011/0012): darwin/amd64
  # binaries -- pure Go included -- external-link through the 10.9 CC wrapper. The arm64 builder's
  # own links are not darwin/amd64, so they are unaffected.
  export GO_EXTLINK_ENABLED=darwin/amd64
  export GOROOT_FINAL="$PREFIX"
  export GOCACHE="$WORK/.gocache"
  cd "$WORK/go/src" && ./make.bash -v )
test -x "$WORK/go/bin/go" || { echo "FATAL: arm64 builder go not built" >&2; exit 1; }

# 3. Phase B -- build-time amd64/min-10.9 CC wrapper. On this arm64 host clang
# defaults to an arm64 target, so linking amd64 objects REQUIRES -arch x86_64 (the
# on-box shipped wrapper in step 7 needs no -arch: on 10.9 clang is already x86_64).
# Forces arch/sysroot/min on every step; adds the static shim + -Wl,-U on LINK steps
# only. NOT shipped -- regenerated under $WORK each run. (This runs under /bin/sh, so
# the `for s in $WLU_SYMS` word-splits -- do not run this generation under zsh.)
BUILDCC="$WORK/mavericks-build-clang"
_wlu=""; for s in $WLU_SYMS; do _wlu="$_wlu \\
  -Wl,-U,$s"; done
cat > "$BUILDCC" <<EOF
#!/bin/sh
# Build-time cross CC (build-native.sh): link darwin/amd64 min-10.9 objects on an
# arm64 host WITHOUT executing amd64. Compile-only steps (-c/-E/-S) skip the shim.
TARGET="-arch x86_64 -isysroot $SDK -mmacosx-version-min=$MACOS_MIN"
for a in "\$@"; do
  case "\$a" in -c|-E|-S) exec /usr/bin/clang \$TARGET "\$@" ;; esac
done
exec /usr/bin/clang \$TARGET "\$@" \\
  "$LEGACY_A"$_wlu
EOF
chmod 755 "$BUILDCC"

# 4. Phase C -- cross-install the amd64-HOSTED toolchain into the builder GOROOT.
# The arm64 builder runs natively and cross-compiles amd64 binaries -- nothing amd64
# is executed. CGO_ENABLED + the wrapper make every external link 10.9-safe, so no
# -extldflags plumbing is needed (the wrapper injects the shim directly; this is why
# link-recipe.sh is no longer sourced). `go install cmd` lays go/gofmt in
# bin/darwin_amd64/ and every tool in pkg/tool/darwin_amd64/.
#
# -linkmode=external is REQUIRED: Go 1.26 INTERNAL-links pure-Go binaries on darwin
# (go, gofmt, and the pure-Go tools have no cgo), and the internal linker stamps Go's
# own supported floor -- macOS 12.0 -- which no external -mmacosx-version-min can undo.
# Forcing external linking routes EVERY binary through the CC wrapper, so all get
# min-10.9 + the legacy shim (the baked darwin/amd64 default from Phase A would do this too; the
# flag keeps the toolchain's own link explicit).
( export GOROOT="$WORK/go"
  export GOOS=darwin GOARCH=amd64
  export CGO_ENABLED=1 CC="$BUILDCC"
  export GOROOT_FINAL="$PREFIX"
  export GOCACHE="$WORK/.gocache"
  "$WORK/go/bin/go" install -v -ldflags=-linkmode=external cmd )

# 5. Phase D -- assemble the shipped amd64 GOROOT in $WORK/go: promote the amd64 host
# binaries to bin/, drop ALL arm64 host artifacts, keep pkg/tool/darwin_amd64 + the
# patched src/ (std ships as source, compiled on-demand on the box).
cd "$WORK/go"
rm -rf pkg/obj pkg/bootstrap
for b in go gofmt; do
  [ -x "bin/darwin_amd64/$b" ] && mv -f "bin/darwin_amd64/$b" "bin/$b"
done
rmdir bin/darwin_amd64 2>/dev/null || true
rm -rf pkg/tool/darwin_arm64
# Prune dev-only tools `go install cmd` emits but a release GOROOT doesn't ship
# (cmd/dist, cmd/api, ...). Reference = the arm64 bootstrap go's own tool dir.
ref="$(go env GOROOT)/pkg/tool/$(go env GOOS)_$(go env GOARCH)"
if [ -d "$ref" ]; then
  for t in pkg/tool/darwin_amd64/*; do
    [ -e "$ref/$(basename "$t")" ] || rm -f "$t"
  done
fi
# Fail loudly if anything arm64 slipped in, or a binary wasn't linked min-10.9 (a
# 12.0 stamp means it internal-linked and bypassed the wrapper -- see Phase C).
for b in bin/go bin/gofmt pkg/tool/darwin_amd64/compile; do
  file "$b" | grep -q 'x86_64' || { echo "FATAL: $b is not x86_64" >&2; exit 1; }
  vtool -show-build "$b" | grep -q 'version 10.9' || {
    echo "FATAL: $b is not min-10.9 (internal-linked? see -linkmode=external)" >&2; exit 1; }
done

# 6. stage into a DESTDIR tree mirroring the install prefix, + CA bundle.
stage="$WORK/staging"
rm -rf "$stage"; mkdir -p "$stage$PREFIX"
( cd "$WORK/go" && pax -rw . "$stage$PREFIX" )
mkdir -p "$stage$PREFIX/etc/openssl/certs"
cp "$CA" "$stage$PREFIX/etc/openssl/certs/ca-certificates.crt"

# 7. downstream-link defaults (verbatim from the previous build-native.sh). Ship the
# static shim + an INTERNAL on-box CC wrapper as the default CC in go.env, so a plain
# on-box `go build` links 10.9-safe cgo invisibly. On the 10.9 box clang is already
# x86_64, so THIS wrapper -- unlike the build-time one in step 3 -- adds NO -arch.
mkdir -p "$stage$PREFIX/lib"
cp "$LEGACY_A" "$stage$PREFIX/lib/libMacportsLegacySupport.a"

_wlu=""; for s in $WLU_SYMS; do _wlu="$_wlu \\
  -Wl,-U,$s"; done
cat > "$stage$PREFIX/bin/mavericks-clang" <<EOF
#!/bin/sh
# Internal Mavericks downstream-link wrapper (default CC via go.env). Appends the
# static legacy shim + the -Wl,-U allowances on LINK steps so every 10.9 binary
# resolves clock_gettime, the *at family, and notify/xpc. Compile-only steps
# (-c/-E/-S) pass through untouched. Generated by build-native.sh.
for a in "\$@"; do
  case "\$a" in -c|-E|-S) exec /usr/bin/clang "\$@" ;; esac
done
exec /usr/bin/clang "\$@" \\
  "$PREFIX/lib/libMacportsLegacySupport.a"$_wlu
EOF
chmod 755 "$stage$PREFIX/bin/mavericks-clang"

{
  echo "CGO_ENABLED=1"
  echo "CC=$PREFIX/bin/mavericks-clang"
} >> "$stage$PREFIX/go.env"

test -x "$stage$PREFIX/bin/go" || { echo "FATAL: no bin/go staged" >&2; exit 1; }
echo "$stage$PREFIX"

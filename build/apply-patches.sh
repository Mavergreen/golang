#!/bin/sh
set -eu
. "$(cd "$(dirname "$0")" && pwd)/versions.sh"

# One repo, one line, one patch set. The old cross-line fallback ("lines/127 has no patches of its
# own; trying line 126's") existed because several lines shared a checkout. They no longer do: a new
# line is a new repo, forked from this one, and it INHERITS these patches as its starting point
# rather than reaching sideways for them at build time.
pdir="$REPO_ROOT/patches"
ls "$pdir"/*.patch >/dev/null 2>&1 || { echo "no patches in $pdir" >&2; exit 1; }

cd "$WORK/go"
# -F 3 allows the context to have drifted by a few lines, which is the ordinary case for a new Go
# minor and the difference between "might just work" and "always needs a human". These are traditional -p0
# patches with .orig headers, so `git apply --3way` is not an option: it reads those as renames.
#
# Fuzz decides only whether a patch APPLIES, never whether the result is CORRECT. Patches 0005-0010 are
# the keychain-union trust model in src/crypto/x509 -- exactly where Go churns between minors -- so a
# fuzzy apply that "succeeds" is precisely the case the gates exist for: the compat guard,
# tests/trust/unit-trust.sh, and the distrust acceptance test. If a new line is red, write real patches
# in that line's own repo's patches/; do not relax the gates to get it green.
#
# Glob rather than a hardcoded 0001..0010 list: adding a patch should not require editing this script.
for p in "$pdir"/*.patch; do
  echo "applying $(basename "$p")"
  patch -p0 -F 3 < "$p"
done

# Toolchain's own CA path: @SSLDIR@ -> $CA_DIR (the native convention; bundle at .../certs/ca-certificates.crt).
# Same for native and cross so cross-built apps look where the native product populates.
sed -i '' "s#@SSLDIR@#$CA_DIR#g" src/crypto/x509/root_keychainunion_darwin.go
grep -q "$CA_DIR/certs/ca-certificates.crt" src/crypto/x509/root_keychainunion_darwin.go
echo "patches applied from patches/ + @SSLDIR@ substituted"

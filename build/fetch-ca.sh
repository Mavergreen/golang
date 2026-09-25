#!/bin/sh
# platform: host-agnostic
# Provide the pinned CA bundle at $WORK/ca-certificates.crt.
#
# The bundle is VENDORED at vendor/cacert.pem and used from there by default, so
# builds are reproducible and independent of the network. curl.se serves only the
# LATEST cacert.pem at CA_URL and rotates it ~quarterly, so once it rotates the old
# bytes are gone -- a download-only pin would become permanently unsatisfiable.
#
# To refresh to a newer Mozilla bundle: run with MAVERICKS_CA_REFRESH=1, which
# downloads, (TOFU-)prints the new sha for CA_SHA256, and rewrites vendor/cacert.pem.
set -eu
. "$(cd "$(dirname "$0")" && pwd)/versions.sh"
mkdir -p "$WORK"
out="$WORK/ca-certificates.crt"
vend="$REPO_ROOT/vendor/cacert.pem"

# Default path: use the vendored bundle, verified against the pin.
if [ -f "$vend" ] && [ -n "$CA_SHA256" ] && [ "${MAVERICKS_CA_REFRESH:-0}" != 1 ]; then
  got=$(shasum -a 256 "$vend" | awk '{print $1}')
  [ "$got" = "$CA_SHA256" ] || { echo "FATAL: vendored CA sha256 mismatch: got $got" >&2; exit 1; }
  grep -q 'ISRG Root X1' "$vend" || { echo "FATAL: vendored bundle missing ISRG Root X1" >&2; exit 1; }
  cp "$vend" "$out"
  echo "$out"
  exit 0
fi

# Refresh / bootstrap path: download the latest and (re)pin + (re)vendor.
curl -fSL -o "$out" "$CA_URL"
got=$(shasum -a 256 "$out" | awk '{print $1}')
if [ -z "$CA_SHA256" ]; then
  echo "TOFU: CA bundle sha256 = $got"
  echo "  -> paste into versions.sh CA_SHA256, then MAVERICKS_CA_REFRESH=1 re-run to vendor it"
  exit 3
fi
[ "$got" = "$CA_SHA256" ] || { echo "FATAL: CA bundle sha256 mismatch: got $got" >&2; exit 1; }
grep -q 'ISRG Root X1' "$out" || { echo "FATAL: bundle missing ISRG Root X1" >&2; exit 1; }
mkdir -p "$REPO_ROOT/vendor"; cp "$out" "$vend"   # keep the vendored copy in sync
echo "$out"

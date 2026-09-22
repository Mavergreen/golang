#!/bin/sh
# Single source of truth for every pinned input. Sourced, not executed.
: "${REPO_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
export REPO_ROOT
# platform: a family checkout may live on NFS, where a build cost 11.16s wall / 25% CPU against
# 2.96s / 88% on local disk, with identical user time -- the whole difference is I/O wait.
: "${MAVERICKS_BUILD_ROOT:=${TMPDIR:-/tmp}/mm-build}"
export MAVERICKS_BUILD_ROOT
# MAVERICKS_WORK still wins when set (build/patch-worktree.sh gives itself a private one so a build
# never clobbers edits); otherwise the build lands under MAVERICKS_BUILD_ROOT, out of this NFS-mounted
# tree entirely. MAVERICKS_BUILD_ROOT="$PWD" is the deliberate in-tree escape hatch.
export WORK="${MAVERICKS_WORK:-$MAVERICKS_BUILD_ROOT/golang-native}"

# Package version, shaped like ../mavericks-swift's VERSION: <upstream>-mavericks.<rev>
# (e.g. 1.26.4-mavericks.1). A packaging-only re-release (patch/recipe changes, independent
# of upstream Go) is now cut via workflow_dispatch local_release=true, which computes the
# next -mavericks.N itself — do not hand-edit VERSION. The source tarball checksum is NOT
# pinned here: build/fetch-go.sh verifies the download against go.dev's own published
# SHA256 (build/go-src-sha256.sh), so a Renovate version bump is self-contained.
#
# Upstream Go version is the Renovate-tracked UPSTREAM_VERSION (bare x.y.z). The full
# package version lives in VERSION (<upstream>-mavericks.N), which the release workflow
# writes and .gitignore excludes; before a release is cut (local/CI build) fall back to
# the computed auto version so a build never depends on a committed VERSION file.
. "$REPO_ROOT/build/lib.sh"
# A Go MINOR LINE is a product: go126 and a future go127 install side by side (each in its own
# repo), each with its own prefix, identifier, updater and feed, so a 1.26 user is never carried onto
# 1.27 unasked. GO_LINE is derived from the root UPSTREAM_VERSION, not configured -- see
# build/version.sh, which owns the derivation; this just asks it.
GO_LINE="$(sh "$REPO_ROOT/build/version.sh" line)"; export GO_LINE
export MAVERICKS_UPSTREAM_FILE="$REPO_ROOT/UPSTREAM_VERSION"
export GO_VERSION="$(upstream_version)"
# The line must match the upstream it points at, or every derived name is a lie.
case "$GO_VERSION" in
  "$(printf '%s' "$GO_LINE" | sed 's/^\(.\)\(.*\)$/\1.\2/')".*) : ;;
  *) echo "versions.sh: UPSTREAM_VERSION holds Go $GO_VERSION -- line ($GO_LINE) and upstream disagree" >&2; exit 1 ;;
esac
if [ -f "$REPO_ROOT/VERSION" ]; then
  export PKG_VERSION="$(cat "$REPO_ROOT/VERSION")"
else
  export PKG_VERSION="$(sh "$REPO_ROOT/build/version.sh" auto | sed -n 's/^FULL=//p')"
fi
export GO_SRC_URL="https://go.dev/dl/go${GO_VERSION}.src.tar.gz"

# The 10.9 legacy-support shim is fetched PREBUILT from the mavericks-legacysupport
# release (ModernMavericks/macports-legacy-support) — no from-source build here. Integrity is
# checked against the release's SHA256SUMS every run. Renovate bumps this pin via the
# shared preset's `# mavericks-legacysupport` customManager (unquoted, marker on the line).
export MLS_VERSION=1.5.2-mavericks.4   # mavericks-legacysupport

export PREFIX="/usr/local/go${GO_LINE}"
export MACOS_MIN="10.9"

# Both products bake the SAME CA convention path into the std trust model: the
# NATIVE prefix's bundle dir. Native populates it; cross-built apps look there
# (a box with the native .pkg installed, or an app that drops/embeds its CA).
export NATIVE_PREFIX="/usr/local/go${GO_LINE}"
export CROSS_PREFIX="/usr/local/go${GO_LINE}-cross"
export CA_DIR="$NATIVE_PREFIX/etc/openssl"   # @SSLDIR@ substitution target (native == cross)

export WLU_SYMS="_SecTrustEvaluateWithError _SecTrustCopyCertificateChain _notify_is_valid_token _xpc_date_create_from_current"

# CA bundle: curl.se cacert.pem. CA_SHA256 is blessed (TOFU) in Task 5.
export CA_URL="https://curl.se/ca/cacert.pem"
export CA_SHA256="3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91"  # curl.se cacert.pem, Mozilla 2026-07-16

# $SHIPYARD / $SHIPYARD_SCRIPTS -- which the shell callers read after sourcing this file (SDK fetch,
# compat guard, productbuild floor, signer, appcast) -- come from build/lib.sh above, which sources
# build/msc.sh. This file used to resolve them a second time, its own way.

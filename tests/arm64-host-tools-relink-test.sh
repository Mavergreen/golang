#!/bin/sh
# build-cross.sh's ./make.bash internal-links the arm64 host tools (bin/go, bin/gofmt,
# pkg/tool/darwin_arm64/*), and Go's internal linker stamps its own floor (12.0) that no
# -mmacosx-version-min can undo. The fix -- mirroring build-native.sh's amd64 external-link --
# is a re-link: `go install -ldflags=-linkmode=external cmd` through a CC that forces arch,
# the pinned arm64 SDK and the arm64 minos floor. This asserts that re-link is actually wired
# up, not just present in prose: strip comments first, so a comment that merely DESCRIBES the
# fix (as this file's own header does) can never satisfy the grep.
set -eu
cd "$(dirname "$0")/.."
src=build/build-cross.sh
code() { sed 's/#.*//' "$1"; }

fail=0
say() { echo "FAIL: $1"; fail=1; }

# The CC wrapper must be built from the pinned arm64 SDK (fetch_sdk.sh --arch arm64), not the
# default (x86_64) SDK the rest of this script fetches.
code "$src" | grep -Eq '\$SHIPYARD_SCRIPTS/fetch_sdk\.sh"[[:space:]]+--arch[[:space:]]+arm64' \
  || say "no fetch_sdk.sh --arch arm64 call (the arm64 SDK is never fetched)"

# That wrapper must actually be handed to `go install` as CC, and the install must force
# external linking -- an internal link is exactly what stamps the un-fixable 12.0 floor.
install_line="$(code "$src" | grep -E 'go[["]* install .*-ldflags=-linkmode=external.*cmd' || true)"
[ -n "$install_line" ] || say "no 'go install -ldflags=-linkmode=external ... cmd' call"

code "$src" | grep -Eq 'CC="\$HOSTCC"' \
  || say "the relink's go install does not set CC=\"\$HOSTCC\" (the arm64-SDK wrapper)"

# The wrapper script content itself (inside the heredoc) must carry the pinned arm64 floor and
# arch -- not just fetch the SDK and then ignore it.
code "$src" | grep -Eq -- '-arch arm64 -isysroot \$SDK_ARM64 -mmacosx-version-min=\$ARM64_MACOS_MIN' \
  || say "HOSTCC's clang invocation does not force -arch arm64 / \$SDK_ARM64 / \$ARM64_MACOS_MIN"

# The relink must run AFTER make.bash produced the tools it's fixing, and BEFORE they're staged
# (staging a still-12.0 tool would ship the bug the relink exists to fix).
make_line="$(grep -n '\./make\.bash -v' "$src" | head -1 | cut -d: -f1)"
install_line_no="$(grep -n -- '-ldflags=-linkmode=external' "$src" | head -1 | cut -d: -f1)"
stage_line="$(grep -n 'stage="\$WORK/staging-cross"' "$src" | head -1 | cut -d: -f1)"
[ -n "$make_line" ] && [ -n "$install_line_no" ] && [ -n "$stage_line" ] \
  || say "could not locate make.bash / relink / staging lines to order-check"
if [ -n "${make_line:-}" ] && [ -n "${install_line_no:-}" ] && [ -n "${stage_line:-}" ]; then
  [ "$make_line" -lt "$install_line_no" ] || say "relink does not come after ./make.bash -v"
  [ "$install_line_no" -lt "$stage_line" ] || say "relink does not come before staging"
fi

# The build-time check: every re-linked tool must be asserted arm64-only, pinned-SDK, before
# staging ships it.
code "$src" | grep -Eq 'MAVERICKS_ALLOW_ARCHS=arm64 sh "\$SHIPYARD_SCRIPTS/assert_binary_compatible\.sh"' \
  || say "no MAVERICKS_ALLOW_ARCHS=arm64 assert_binary_compatible.sh build-time gate"
code "$src" | grep -Eq '"\$WORK/go/bin/go" "\$WORK/go/bin/gofmt" "\$WORK/go/pkg/tool/darwin_arm64/"\*' \
  || say "assert_binary_compatible.sh is not given bin/go, bin/gofmt and every pkg/tool/darwin_arm64/* tool"

# The arm64 minos floor lives in ONE variable (build/versions.sh), not hardcoded in build-cross.sh --
# so a future line repo only has to change it in one obvious place.
grep -Eq '^export ARM64_MACOS_MIN=' build/versions.sh \
  || say "ARM64_MACOS_MIN is not declared as a single source of truth in build/versions.sh"
code "$src" | grep -Eq '11\.0|12\.0' \
  && say "build-cross.sh hardcodes an SDK-min value; it must use \$ARM64_MACOS_MIN instead" || :

[ "$fail" -eq 0 ] && echo "arm64-host-tools-relink-test OK" || exit 1

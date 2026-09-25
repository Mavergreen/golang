#!/bin/sh
# platform: host-agnostic
# Regenerate one patch file from the tree build/patch-worktree.sh prepared (same MAVERICKS_WORK).
#   usage: sh build/mkpatch.sh <patch-file> [src/relative/path ...]
# With no paths, uses the patch's own '+++' paths. Keeps the description (everything before the
# first '--- ' line), so for a NEW patch write the description into the file first. A path absent
# from go.pristine is emitted as a new file. apply-patches.sh's @SSLDIR@ substitution is reversed,
# so the patch stays neutral about who packages the toolchain.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/versions.sh"
patch_file="$1"; shift
[ -f "$patch_file" ] || { echo "no $patch_file -- write its description first" >&2; exit 1; }
[ -d "$WORK/go.pristine" ] || { echo "run build/patch-worktree.sh first (same MAVERICKS_WORK)" >&2; exit 1; }
[ "$#" -gt 0 ] || set -- $(grep '^+++ ' "$patch_file" | awk '{print $2}')
[ "$#" -gt 0 ] || { echo "no paths given and none in $patch_file" >&2; exit 1; }
tmp="$(mktemp "${TMPDIR:-/tmp}/mkpatch.XXXXXX")"
awk '/^--- /{exit} {print}' "$patch_file" > "$tmp"
for rel in "$@"; do
  old="$WORK/go.pristine/$rel"; [ -f "$old" ] || old=/dev/null
  rc=0; ( cd "$WORK/go" && diff -u "$old" "$rel" ) > "$tmp.d" || rc=$?
  [ "$rc" -le 1 ] || { echo "diff failed for $rel" >&2; rm -f "$tmp" "$tmp.d"; exit 1; }
  sed -e "1s#^--- .*#--- $rel.orig#" -e "2s#^+++ .*#+++ $rel#" -e "s#$CA_DIR#@SSLDIR@#g" "$tmp.d" >> "$tmp"
done
rm -f "$tmp.d"
cat "$tmp" > "$patch_file" && rm -f "$tmp"

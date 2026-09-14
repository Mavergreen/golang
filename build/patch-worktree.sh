#!/bin/sh
# Prepare an editable Go tree for patch work: $WORK/go = upstream (UPSTREAM_VERSION) + this line's
# patches, and $WORK/go.pristine = the same upstream untouched, which build/mkpatch.sh diffs against.
# Give it a WORK of its own so a build never clobbers edits:
#   MAVERICKS_WORK=$HOME/.cache/mavericks-golang/patchwork sh build/patch-worktree.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/versions.sh"
sh "$here/fetch-go.sh"
rm -rf "$WORK/go.pristine"
mkdir -p "$WORK/go.pristine"
( cd "$WORK/go" && pax -rw . "$WORK/go.pristine" )
sh "$here/apply-patches.sh"
echo "editable: $WORK/go   pristine: $WORK/go.pristine"

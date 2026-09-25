#!/bin/sh
# platform: host-agnostic
# Print the URL of the release notes for one upstream Go version. shipyard's
# upstream-notes.sh links it from our release notes when a release ships a NEW upstream.
#   usage: upstream-release-notes-url.sh <upstream-version>      (bare: 1.26.8)
set -eu
printf 'https://go.dev/doc/devel/release#go%s\n' "${1:?usage: upstream-release-notes-url.sh <upstream-version>}"

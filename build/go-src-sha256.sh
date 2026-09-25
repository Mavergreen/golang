#!/bin/sh
# platform: host-agnostic
# Print the official SHA256 of go<version>.src.tar.gz from go.dev's release feed.
# Set GO_DL_JSON to a local feed file to skip the network (tests, or a caller that
# already fetched it). No in-repo pin: the feed is the source of truth (see the
# renovate-auto-release spec).
set -eu
VER="${1:?usage: go-src-sha256.sh <go-version, e.g. 1.26.5>}"
file="go${VER}.src.tar.gz"

if [ -n "${GO_DL_JSON:-}" ]; then
  feed="$GO_DL_JSON"
else
  feed="$(mktemp "${TMPDIR:-/tmp}/go-src-sha256.XXXXXX")"   # template: 10.9 BSD mktemp requires one
  curl -fSL -o "$feed" 'https://go.dev/dl/?mode=json&include=all'
fi

python3 - "$feed" "$file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
target = sys.argv[2]
for rel in data:
    for f in rel.get("files", []):
        if f.get("filename") == target:
            print(f["sha256"]); sys.exit(0)
sys.exit("FATAL: %s not found in go.dev feed" % target)
PY

#!/bin/sh
# platform: host-agnostic
# Unit test for build/go-src-sha256.sh (offline, via GO_DL_JSON).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../build/go-src-sha256.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/go-src-sha256-test.XXXXXX")"   # template: 10.9 BSD mktemp requires one
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/feed.json" <<'JSON'
[
  {"version":"go1.26.5","files":[
    {"filename":"go1.26.5.src.tar.gz","kind":"source","sha256":"495be4bc87176ac567392e5b4116abd98466d33d7b49d41e764ccc6976b2dc42"},
    {"filename":"go1.26.5.darwin-amd64.tar.gz","kind":"archive","sha256":"deadbeef"}
  ]},
  {"version":"go1.26.4","files":[
    {"filename":"go1.26.4.src.tar.gz","kind":"source","sha256":"4f668a32fbfc1132e6a881fb968c2f1dada631492a339211735fbb255a42602d"}
  ]}
]
JSON

# 1. resolves the source sha256 for a present version
got="$(GO_DL_JSON="$tmp/feed.json" sh "$script" 1.26.5)"
[ "$got" = "495be4bc87176ac567392e5b4116abd98466d33d7b49d41e764ccc6976b2dc42" ] \
  || { echo "FAIL: got '$got' for 1.26.5"; exit 1; }

# 2. picks the SOURCE tarball, not another file
got4="$(GO_DL_JSON="$tmp/feed.json" sh "$script" 1.26.4)"
[ "$got4" = "4f668a32fbfc1132e6a881fb968c2f1dada631492a339211735fbb255a42602d" ] \
  || { echo "FAIL: got '$got4' for 1.26.4"; exit 1; }

# 3. missing version fails non-zero
if GO_DL_JSON="$tmp/feed.json" sh "$script" 9.9.9 >/dev/null 2>&1; then
  echo "FAIL: expected non-zero for absent version"; exit 1
fi

echo "PASS: go-src-sha256"

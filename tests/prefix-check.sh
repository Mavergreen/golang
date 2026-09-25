#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
tracked=$(git ls-files build/versions.sh CMakeLists.txt .github/workflows/release.yml \
  scripts/resources/Welcome.html 'release-notes/*.md')
if printf '%s\n' $tracked | xargs grep -l '/usr/local/mavericks-go' 2>/dev/null | grep -q .; then
  echo "FAIL: old prefix still present in tracked files:"; printf '%s\n' $tracked | xargs grep -l '/usr/local/mavericks-go' 2>/dev/null
  exit 1
fi
# the otool self-link check must reference the new path, not the old bare fragment
grep -q "mavericks-go/go126" .github/workflows/release.yml && { echo "FAIL: bare 'mavericks-go/go126' fragment remains in release.yml"; exit 1; }
# Sanity: assert the prefixes' values, not their spelling -- they are derived from the
# Go line (/usr/local/mavergreen/go${GO_LINE}), so grepping the source text would only pin the syntax and
# would break the day a second line arrives.
eval_prefix() { REPO_ROOT="$(pwd)" sh -c ". ./build/versions.sh; printf '%s\n' \"\$$1\"" 2>/dev/null; }
[ "$(eval_prefix PREFIX)" = /usr/local/mavergreen/go126 ] \
  || { echo "FAIL: PREFIX is '$(eval_prefix PREFIX)', expected the product tree /usr/local/mavergreen/go126"; exit 1; }
[ "$(eval_prefix CROSS_PREFIX)" = /usr/local/mavergreen/go126-cross ] \
  || { echo "FAIL: CROSS_PREFIX is '$(eval_prefix CROSS_PREFIX)', expected /usr/local/mavergreen/go126-cross"; exit 1; }
[ "$(eval_prefix CA_DIR)" = /usr/local/mavergreen/go126/etc/openssl ] \
  || { echo "FAIL: CA_DIR is compiled into every program either toolchain builds, so it must be inside the native tree: got '$(eval_prefix CA_DIR)'"; exit 1; }
live=$(git ls-files build/versions.sh build/onbox-dev-goroot.sh CMakeLists.txt .github/workflows/release.yml \
  scripts/resources/Welcome.html tests/trust/acceptance-onbox.sh)
if printf '%s\n' $live | xargs grep -l '/usr/local/go126' 2>/dev/null | grep -q .; then
  echo "FAIL: the old /usr/local/go126 prefix is still named in:"; printf '%s\n' $live | xargs grep -l '/usr/local/go126'; exit 1
fi
echo "prefix-check OK"

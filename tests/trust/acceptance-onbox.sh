#!/bin/sh
# On-box trust acceptance -- run ON a 10.9 box whose System keychain trusts ISRG Root X1 (as
# ultimate-hat's does). Both verifiers against real endpoints: the default Go keychain union and
# Apple's (GODEBUG=x509usefallbackroots=0); the user trust domain via userdeny; and a program that
# calls SetFallbackRoots. Keychain Access steps that need a human are in smoke-trust.sh.
#   usage: [GOROOT=/path/to/goroot] sh tests/trust/acceptance-onbox.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
goroot="${GOROOT:-/usr/local/go126}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/accept.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
unset HTTPS_PROXY HTTP_PROXY ALL_PROXY GODEBUG
export GOROOT="$goroot" PATH="$goroot/bin:$PATH" GOCACHE="$tmp/gocache" GOPATH="$tmp/gopath" GOFLAGS=
mkdir -p "$tmp/vt" && cp "$here/verify_tls.go" "$tmp/vt/" && printf 'module vt\n\ngo 1.26\n' > "$tmp/vt/go.mod"
( cd "$tmp/vt" && go build -o "$tmp/verify_tls" . )
( cd "$here/userdeny" && go build -o "$tmp/userdeny" . )
( cd "$here/setfallback" && go build -o "$tmp/setfallback" . )

fail=0
expect() { # mode(union|native) url want(VERIFIED|REJECTED) [substring]
  mode="$1" url="$2" want="$3" sub="${4:-}"
  if [ "$mode" = native ]; then out="$(GODEBUG=x509usefallbackroots=0 "$tmp/verify_tls" "$url" 2>&1)" || true
  else out="$("$tmp/verify_tls" "$url" 2>&1)" || true; fi
  case "$out" in
    "$want"*"$sub"*) echo "ok   [$mode] $url: $out" ;;
    *) echo "FAIL [$mode] $url: want $want${sub:+ containing '$sub'}, got: $out"; fail=1 ;;
  esac
}
for mode in union native; do
  expect "$mode" https://valid-isrgrootx1.letsencrypt.org/ VERIFIED
  expect "$mode" https://valid-isrgrootx2.letsencrypt.org/ VERIFIED
  expect "$mode" https://expired.badssl.com/ REJECTED "expired"
  expect "$mode" https://wrong.host.badssl.com/ REJECTED "is valid for"
  expect "$mode" https://untrusted-root.badssl.com/ REJECTED "unknown authority"
done
# The documented difference between the two: Apple fetches a missing intermediate, Go does not.
expect union https://incomplete-chain.badssl.com/ REJECTED "unknown authority"
expect native https://incomplete-chain.badssl.com/ VERIFIED

for mode in union native; do
  rc=0
  if [ "$mode" = native ]; then GODEBUG=x509usefallbackroots=0 USERDENY_DENY_ONLY=1 "$tmp/userdeny" || rc=$?
  else "$tmp/userdeny" || rc=$?; fi
  case "$rc" in
    0) ;;
    77) echo "skip [$mode] userdeny: this account has no user-domain trust settings" ;;
    *) echo "FAIL [$mode] userdeny"; fail=1 ;;
  esac
done

if out="$("$tmp/setfallback" 2>&1)"; then echo "ok   [union] SetFallbackRoots program: $out"
else echo "FAIL [union] SetFallbackRoots program: $out"; fail=1; fi
exit "$fail"

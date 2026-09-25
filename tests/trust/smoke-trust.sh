#!/bin/sh
# platform: host-agnostic
# On-box trust smoke. Uses Let's Encrypt's PINNED single-root endpoints so the
# result is immune to CA-hierarchy churn (public sites like letsencrypt.org now
# dual-root via ISRG Root X2, so distrusting X1 alone no longer blocks them).
#
#   valid-isrgrootx2.letsencrypt.org  chains ONLY to ISRG Root X2  -> positive
#   valid-isrgrootx1.letsencrypt.org  chains ONLY to ISRG Root X1  -> distrust target
#
# Positive is fully automated. The distrust half is semi-manual (toggle ISRG
# Root X1 -> Never Trust in Keychain Access; scripted keychain writes wedge
# SecurityAgent -- see mavericks-tailscale ws1-keychain-enum-spike).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../build/versions.sh"
: "${MAVERICKS_HOST:?set MAVERICKS_HOST}"

ssh "$MAVERICKS_HOST" "rm -rf /tmp/trust && mkdir -p /tmp/trust"
rsync -a "$here/verify_tls.go" "$MAVERICKS_HOST:/tmp/trust/"

run() { # url
  ssh "$MAVERICKS_HOST" "sh -c '
    unset HTTPS_PROXY HTTP_PROXY ALL_PROXY GODEBUG
    export PATH=$PREFIX/bin:\$PATH GOROOT=$PREFIX GOCACHE=/tmp/gctrust GOPATH=/tmp/gptrust
    cd /tmp/trust && (test -f go.mod || go mod init trust) >/dev/null 2>&1
    go run ./verify_tls.go $1
  '"
}

echo "== positive: valid-isrgrootx2 (must VERIFY) =="
out=$(run "https://valid-isrgrootx2.letsencrypt.org/")
echo "$out"
case "$out" in *"VERIFIED"*) ;; *) echo "FAIL: positive trust broken" >&2; exit 1;; esac

echo "== positive: valid-isrgrootx1 with X1 TRUSTED (must VERIFY) =="
out=$(run "https://valid-isrgrootx1.letsencrypt.org/")
echo "$out"
case "$out" in
  *"VERIFIED"*) echo "OK (X1 trusted -> verified)";;
  *"REJECTED"*) echo "NOTE: X1 is currently distrusted on the box -> this is the negative case";;
esac

cat <<'EOF'

-- Distrust acceptance, admin domain (semi-manual) --
1. Keychain Access -> System keychain -> ISRG Root X1 -> Trust ->
   "When using this certificate: Never Trust" (authenticate as admin).
2. Re-run: valid-isrgrootx1 must flip to REJECTED ("certificate signed by unknown authority").
   If it still VERIFIES, check whether the CA bundle now carries a self-signed root for that
   chain (e.g. ISRG Root YR); if so the test target, not the code, needs changing.
3. Restore: set ISRG Root X1 back to "Use System Defaults".

-- User trust domain, both verifiers (semi-manual; issue #9) --
Run ON the box: sh tests/trust/acceptance-onbox.sh after each change below.
4. ( cd tests/trust/capture && go run . untrusted-root.badssl.com ) | awk '/BEGIN/{n++} n==2' > /tmp/badssl-root.pem
   Keychain Access -> File -> Import Items -> /tmp/badssl-root.pem into the "login" keychain.
   Get Info -> Trust -> "When using this certificate: Always Trust".
   Expect: untrusted-root.badssl.com VERIFIED in [union] AND [native] (the script's REJECTED
   expectation for it fails -- that failure is the pass here), and userdeny prints
   "ok user Always Trust ... BadSSL ... verifies".
5. Same certificate -> "Never Trust". Expect untrusted-root.badssl.com REJECTED in both modes, and
   userdeny "ok user Never Trust ... BadSSL ... rejected".
6. Restore: delete the BadSSL certificate from the "login" keychain.

-- User -> admin fall-through, [union] (semi-manual) --
The BadSSL root is untrusted anyway, so this check hands it in as its own CA bundle -- then only
a keychain Never Trust can reject it:
   ( cd tests/trust && SSL_CERT_FILE=/tmp/badssl-root.pem go run verify_tls.go https://untrusted-root.badssl.com/ )
7. With the BadSSL certificate in no keychain, run that: expect VERIFIED (the bundle anchors it).
8. Import /tmp/badssl-root.pem into the "System" keychain; Get Info -> Trust ->
   "Secure Sockets Layer (SSL)" = Never Trust (authenticate as admin). Import it into the
   "login" keychain too; Get Info -> Trust -> "Secure Mime (S/MIME)" = Always Trust, the rest
   "no value specified". Run it again: expect REJECTED ("unknown authority"). The user's
   S/MIME-only setting says nothing about SSL, so the admin's Never Trust applies.
9. Restore: delete the BadSSL certificate from both the "login" and "System" keychains.
EOF

#!/bin/sh
# The watch file is what tells us a new Go LINE exists and we may want a repo for it. It has to
# stay machine-checkable: a stale watch is worse than none, because it reads as "nothing new".
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
w="$R/NEXT-LINE-WATCH"
[ -f "$w" ] || { echo "FAIL: no NEXT-LINE-WATCH"; exit 1; }

got="$(sed -n 's/^LATEST_GO=//p' "$w" | tr -d '[:space:]')"
[ -n "$got" ] || { echo "FAIL: NEXT-LINE-WATCH has no LATEST_GO= line"; exit 1; }
echo "$got" | grep -q '^[0-9][0-9]*\.[0-9][0-9]*\.' || { echo "FAIL: LATEST_GO not dotted-numeric: $got"; exit 1; }

# It must be tracked by Renovate, or it will never move and never tell us anything.
grep -q 'NEXT-LINE-WATCH' "$R/.github/renovate.json" || { echo "FAIL: no Renovate manager for NEXT-LINE-WATCH"; exit 1; }

# A fresh 10.9 box may not have python3 -- skip the JSON-structural checks rather than fail
# the whole suite over a missing interpreter.
if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found -- cannot check renovate.json structure"
  exit 77
fi

# And it must NOT be capped: the cap on the shipping line is what keeps THIS repo on 1.26,
# and an identical cap here would hide the very thing this file exists to surface. It also must
# NOT be left to automerge: the shared preset's default is automerge=true, and an un-ruled
# go-latest PR would merge itself before anyone saw it -- the PR merging IS the notification
# reaching a human, so automerge must be explicitly false. Renovate applies packageRules in
# ARRAY ORDER, with a later matching rule overriding an earlier one for the same property, so
# "some matched rule says automerge:false" is not enough -- a later rule could still flip it back
# to true. What matters is the LAST matched rule that mentions automerge at all.
python3 - "$R/.github/renovate.json" <<'PY' || exit 1
import json, sys
cfg = json.load(open(sys.argv[1]))
mgrs = [m for m in cfg.get("customManagers", []) if any("NEXT-LINE-WATCH" in p for p in m.get("managerFilePatterns", []))]
if not mgrs: print("FAIL: no customManager for NEXT-LINE-WATCH"); sys.exit(1)
dep = mgrs[0].get("depNameTemplate")
matched = [r for r in cfg.get("packageRules", []) if dep in (r.get("matchDepNames") or [])]
for r in matched:
    if r.get("allowedVersions"):
        print("FAIL: %s is capped (%s) -- it would never report a new line" % (dep, r["allowedVersions"])); sys.exit(1)
automerge_rules = [r for r in matched if "automerge" in r]
if not automerge_rules:
    print("FAIL: %s has no rule that sets automerge -- the notification would silently automerge" % dep); sys.exit(1)
last = automerge_rules[-1]
if last.get("automerge") is not False:
    print("FAIL: %s's LAST automerge-setting rule sets automerge=%r, not False -- packageRules apply in order and a later match wins" % (dep, last.get("automerge"))); sys.exit(1)
print("ok: %s is tracked, uncapped, and its last automerge rule is False" % dep)
PY
echo "PASS: next-line-watch"

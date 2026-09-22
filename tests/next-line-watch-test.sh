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
python3 - "$R/.github/renovate.json" "$w" "$got" <<'PY' || exit 1
import json, re, sys
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

# The matchStrings regex must not depend on LATEST_GO= being the file's LAST line: an
# end-anchored `.+?\s*$` form (no MULTILINE) stops matching the instant anything -- even a
# trailing comment -- follows the value, so a perfectly good bump would go unseen.
matchstrings = mgrs[0].get("matchStrings") or []
if not matchstrings:
    print("FAIL: %s has no matchStrings" % dep); sys.exit(1)
pattern = matchstrings[0]
if ".+?)\\s*$" in pattern or pattern.rstrip().endswith(r"\s*$"):
    print("FAIL: %s matchStrings still uses the end-anchored '.+?\\s*$' form: %r" % (dep, pattern)); sys.exit(1)

# Apply the regex the way Renovate would (against the real file, no MULTILINE) and confirm it
# captures exactly the value on the LATEST_GO= line. Python's re needs (?P<name>...), not the
# (?<name>...) form Renovate's regex engine accepts, so translate before compiling.
py_pattern = pattern.replace("(?<", "(?P<")
text = open(sys.argv[2]).read()
expected = sys.argv[3]
m = re.search(py_pattern, text)
if not m:
    print("FAIL: matchStrings regex %r does not match NEXT-LINE-WATCH" % pattern); sys.exit(1)
captured = m.group("currentValue")
if captured != expected:
    print("FAIL: matchStrings captured %r, expected %r (the LATEST_GO= value)" % (captured, expected)); sys.exit(1)
print("ok: %s matchStrings captures exactly %r from NEXT-LINE-WATCH" % (dep, captured))
PY
echo "PASS: next-line-watch"

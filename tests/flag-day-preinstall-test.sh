#!/bin/sh
# The flag-day migration (2026-09-22, ModernMavericks -> Mavergreen) for both golang pkgs:
#   1. the preinstall build/flag-day-preinstall.sh renders forgets the pre-rename receipt on
#      Installer's target volume, only there, and never fails the install;
#   2. each variant's rendered postinstall retires that variant's OLD updater .app + update-check
#      agent -- shipyard's shared updater/agent-load.in does this, but only if the new label is the
#      old one with the prefix swapped and the old app has the same name, which is this repo's to get
#      right. The old names below are what the pre-flag-day pkgs actually installed.
# pkgutil, launchctl and sudo are PATH stubs that record their arguments, and everything happens under
# a fake volume, so nothing here touches a real receipt database, /Library or a launchd session.
# DELETABLE with build/flag-day-preinstall.sh (shipyard SKILL.md "Consolidation backlog").
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/flagday.XXXXXX")"   # template: 10.9 BSD mktemp requires one
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
GO_LINE="$(sh "$ROOT/build/version.sh" line)"

mkdir -p "$t/bin" "$t/vol"
for cmd in pkgutil launchctl sudo; do
  cat > "$t/bin/$cmd" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$t/$cmd.log"
exit \${STUB_RC:-0}
EOF
  chmod +x "$t/bin/$cmd"
done

# --- 1. the preinstall ---------------------------------------------------------------------------
sh "$ROOT/build/flag-day-preinstall.sh" "dev.modernmavericks.golang.go$GO_LINE" "$t/s/preinstall"
[ -x "$t/s/preinstall" ] || fail "no executable preinstall rendered"

# Installer runs preinstall as: $1 pkg path, $2 install location, $3 target volume, $4 system root.
PATH="$t/bin:$PATH" "$t/s/preinstall" /x.pkg / "$t/vol" / || fail "preinstall failed"
[ "$(cat "$t/pkgutil.log")" = "--volume $t/vol --forget dev.modernmavericks.golang.go$GO_LINE" ] \
  || fail "expected the old receipt forgotten on the target volume, got: $(cat "$t/pkgutil.log")"

# A pkgutil that fails (no such receipt: every fresh install) must not fail the install.
rm -f "$t/pkgutil.log"
PATH="$t/bin:$PATH" STUB_RC=1 "$t/s/preinstall" /x.pkg / "$t/vol" / || fail "a failing pkgutil failed the install"

# No target volume: nothing is known about where an old install lives, so nothing is done.
rm -f "$t/pkgutil.log"
PATH="$t/bin:$PATH" "$t/s/preinstall" || fail "preinstall with no args failed"
[ ! -f "$t/pkgutil.log" ] || fail "pkgutil ran with no target volume: $(cat "$t/pkgutil.log")"

# Only an OLD identifier may be forgotten: a slip that passed the new one would forget this very pkg.
if sh "$ROOT/build/flag-day-preinstall.sh" "dev.mavergreen.golang.go$GO_LINE" "$t/bad" 2>/dev/null; then
  fail "rendered a preinstall that forgets a dev.mavergreen.* receipt"
fi

# Each variant renders it for ITS OWN old identifier: native and cross can share a box, and
# forgetting the other one's receipt would orphan a toolchain that is still installed.
grep -q 'flag-day-preinstall.sh" "dev.modernmavericks.golang.go${GO_LINE}" "$scr/preinstall"' \
  "$ROOT/build/package-pkg.sh" || fail "package-pkg.sh does not render the flag-day preinstall for the native id"
grep -q 'flag-day-preinstall.sh" "dev.modernmavericks.golang.go${GO_LINE}-cross" "$scr/preinstall"' \
  "$ROOT/build/package-cross-pkg.sh" || fail "package-cross-pkg.sh does not render the flag-day preinstall for the cross id"
for v in package-pkg package-cross-pkg; do
  grep -q -- '--scripts "$scr"' "$ROOT/build/$v.sh" || fail "$v.sh does not hand pkgbuild the scripts dir"
done

# --- 2. the old updater + agent, per variant -----------------------------------------------------
# SHIPYARD_SCRIPTS is what CI packages with (install@v1 exports it), so it is what must retire the
# old updater. Unset (a plain local run), there is no shipyard to render with: skip this half.
if [ -z "${SHIPYARD_SCRIPTS:-}" ] || [ ! -f "$SHIPYARD_SCRIPTS/stage_updater.sh" ]; then
  echo "OK: flag-day preinstall (SHIPYARD_SCRIPTS unset: skipped the updater-retirement half)"
  exit 0
fi
# script  new label, as the package script spells it  updater app  old label, as the old pkg installed it
while read -r script spelled app old; do
  grep -qF -- "--agent-label \"$spelled\"" "$ROOT/build/$script.sh" \
    || fail "$script.sh no longer stages its updater as $spelled; update this test with it"
  grep -qF "/$app}\"" "$ROOT/build/$script.sh" \
    || fail "$script.sh no longer packages $app; update this test with it"
  label="$(printf '%s' "$spelled" | sed "s/[$]{GO_LINE}/$GO_LINE/")"
  old="$(printf '%s' "$old" | sed "s/[$]{GO_LINE}/$GO_LINE/")"

  V="$t/vol-$script"; OLDAPPS="$V/Library/Application Support/ModernMavericks"
  mkdir -p "$V/Library/LaunchAgents" "$OLDAPPS/$app/Contents/MacOS" "$t/$script/$app/Contents/MacOS"
  touch "$V/Library/LaunchAgents/$old.plist" "$OLDAPPS/$app/Contents/MacOS/x"
  sh "$SHIPYARD_SCRIPTS/stage_updater.sh" --stage "$t/$script/stage" --app "$t/$script/$app" \
    --app-dir "/Library/Application Support/Mavergreen" --agent-label "$label" \
    --scripts-out "$t/$script/scripts" 2>/dev/null || fail "$script: stage_updater.sh failed"
  PATH="$t/bin:$PATH" sh "$t/$script/scripts/postinstall" /x.pkg / "$V" / || fail "$script: postinstall failed"
  if [ -f "$V/Library/LaunchAgents/$old.plist" ] || [ -d "$OLDAPPS/$app" ]; then
    fail "$script: the postinstall rendered by $SHIPYARD_SCRIPTS left the old updater behind ($old, $app).
      A shipyard that predates the flag day retires nothing: package with one released after it."
  fi
done <<'EOF'
package-pkg dev.mavergreen.golang.go${GO_LINE}-updatecheck GoUpdater.app dev.modernmavericks.golang.go${GO_LINE}-updatecheck
package-cross-pkg dev.mavergreen.golang.go${GO_LINE}-cross-updatecheck GoCrossUpdater.app dev.modernmavericks.golang.go${GO_LINE}-cross-updatecheck
EOF
echo "OK: flag-day preinstall + old updater retirement (native and cross)"

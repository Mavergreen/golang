# mavericks-golang

Cross-builds a **patched Go 1.26.4 toolchain that installs and runs on Mac OS X 10.9
(Mavericks)** — with out-of-the-box cgo, keychain∪bundle verified TLS, and a Sparkle
auto-updater — entirely on modern hardware. No 10.9 build runner anywhere.

**Status:** built and proven end-to-end on real 10.9.5 hardware (`ultimate-hat`), and published to
GitHub Releases. Ships as `golang-<gover>-native-mavericks.<rev>.pkg` and
`golang-<gover>-cross-mavericks.<rev>.pkg` (native installs to `/usr/local/go126`).

## Build / release

- `sh build/build-native.sh` — **Rosetta-free**: fetch go1.26.4 → apply `patches/126/` → build
  static macports-legacy-support → native arm64 `make.bash` builder → cross `go install cmd` for
  amd64 (via a build-time `-arch x86_64`/min-10.9 CC wrapper) → assemble amd64 GOROOT (local `WORK`).
  No amd64 code runs in the build path; Rosetta is only an optional post-build self-test.
- `sh build/package-pkg.sh` — stage the updater + LaunchAgent, wrap with the 10.9.5 floor →
  `.pkg` + tarball + `manifest/`.
- `MAVERICKS_HOST=ultimate-hat sh test/smoke-mavericks.sh [installer]` — on-box smoke.
- `sh test/trust/smoke-trust.sh` — TLS-trust acceptance (pinned LE endpoints).
- `.github/workflows/release.yml` — CI build → EdDSA-sign → appcast → Release. Three triggers: push
  to `main` (auto-cuts `<upstream>-mavericks.1` if unreleased), a `*-mavericks.*` tag, or
  `workflow_dispatch local_release=true`.
- **This repo ships ONE Go minor line (1.26) from the repo root.** `UPSTREAM_VERSION` and `patches/`
  live at the top level, not under a per-line directory; everything else derives from the line number
  (`/usr/local/go126`, `dev.modernmavericks.golang.go126`, the LaunchAgent label, the product title,
  and the Sparkle feed `feed-126`). The line number is itself **derived** from `UPSTREAM_VERSION`
  (`build/version.sh line`; 1.26.5 → 126), never configured separately.
  - **A new Go minor line is a NEW REPO** (`Mavergreen/golang-127`), forked from this one — not a
    second directory here. It inherits this repo's `patches/` as its starting point. `docs/` is
    gitignored here (tracked out-of-band, not present in a clone) — for why, see the commits that
    made it so: "refactor: retire lines/, ship one line from the repo root" and ec77028
    ("ci: build one line, not a matrix — unblock the stuck Renovate PRs"). This repo's Renovate cap
    (`allowedVersions: "<1.27"` on `go-126`) is what keeps this repo on 1.26.x so it can never drift
    onto the next line by itself. A new line gets noticed the ordinary way: a consumer's routine
    Renovate bump (e.g. a tailscale bump needing Go 1.27) fails its build.
  - The gates are what keep a line safe to ship, not fuzzy patch application: patches 0005–0010 and
    0013–0015 are the keychain-union trust model in `src/crypto/x509`, exactly where Go churns between
    minors. A fuzzy apply (`patch -p0 -F 3`) can succeed and be wrong — that is what `tests/trust/` and
    the compat guard are for. **Never relax those to make a build green.**
- Upstream Go version lives in `UPSTREAM_VERSION` (bare `x.y.z`, Renovate-managed) at the repo root.
  `build/version.sh <auto|local>` derives the full `<upstream>-mavericks.N` + a `RELEASE=yes/no`
  decision from existing `*-mavericks.*` tags: `auto` is `N=1`/`RELEASE=yes` for a new upstream (no
  tag yet), else current `N`/`RELEASE=no`; `local` (via `workflow_dispatch local_release`) is always
  `N=maxN+1`/`RELEASE=yes`. `VERSION` (the full string) is workflow-written and **gitignored** —
  never committed.
- Renovate auto-bumps `UPSTREAM_VERSION` (capped to this repo's line) and automerges the PR **once the
  build is green** — patch, minor and major alike, per the family's ship-if-green policy. This repo
  needs no extra `packageRules` beyond the cap: a Go minor bump past the cap never opens a PR at all,
  and within the cap a bad bump just fails the build. `ignoreTests: false` comes from the **shared
  preset** — don't restate it here, or this repo silently stops tracking the preset.
- A push to `main` whose upstream has no release yet auto-cuts `<upstream>-mavericks.1` via
  `gh release create` in `release.yml` (no PAT — `gh` mints the tag itself). Don't also push a
  manual tag for that release; that re-triggers CI and rebuilds/republishes the same version.

## Non-obvious invariants (details in `memory/`)

- **Repo is on NFS — build on local disk** (`WORK` defaults to `~/.cache`). [[mavericks-golang-nfs-build-location]]
- **Every darwin/amd64 link goes through the CC wrapper, pure Go included.** The toolchains are built
  with `GO_EXTLINK_ENABLED=darwin/amd64` baked in (patches 0011/0012): Go internal-links cgo-free
  binaries otherwise, and those die on 10.9 (`_clock_gettime`). Other GOOS targets keep the automatic
  choice. `tests/pure-go-link.sh` is the gate (CI: cross toolchain; box: `smoke-mavericks.sh`).
- **The amd64 toolchain is cross-linked `-linkmode=external`** so the toolchain's own binaries (go/gofmt/tools)
  route through the min-10.9 CC wrapper — Go 1.26 internal-links them to a 12.0 floor otherwise.
  `link-recipe.sh` (the old `-extldflags`/`GO_EXTLINK_ENABLED` plumbing) is gone; the CC wrappers
  inject the shim directly. [[mavericks-go126-downstream-linking]]
- **The trust model:** crypto/x509's system roots on darwin are the keychain union — all three trust
  domains read with Go 1.17's precedence- and policy-aware code, ∪ the CA bundle, minus distrust —
  served lazily by `loadSystemRoots` (patches 0005–0010, 0013–0015). `GODEBUG=x509usefallbackroots=0`
  selects Apple's verifier, which works on 10.9: its crash was Go passing a NULL-callback CFArray of
  policies. Reading the USER domain doesn't prompt in any context tested (a locked login keychain is
  untested; the prompt guards writes). Acceptance: `tests/trust/acceptance-onbox.sh` + the
  semi-manual steps in `smoke-trust.sh`.
- **Sparkle updater + EdDSA keys** (private key = `SPARKLE_PRIVATE_KEY` secret). [[mavericks-go126-sparkle-updater]]
- **Renovate's Go patch auto-release trusts go.dev's feed-verified sha256** (`build/fetch-go.sh`,
  `build/go-src-sha256.sh`), not a pinned checksum, and requires no PAT/App token — deliberately,
  so don't add one.
- Apple `/usr/bin/clang` required for cgo/ObjC. Reuse `../mavergreen-shipyard`; don't duplicate.

## Design docs

`docs/superpowers/specs/2026-07-18-*.md` (spec) and `docs/superpowers/plans/2026-07-18-*.md`
(implementation plan) — `docs/` is gitignored here (tracked out-of-band, not present in a clone).
The `2026-07-14` spec is the older umbrella vision.

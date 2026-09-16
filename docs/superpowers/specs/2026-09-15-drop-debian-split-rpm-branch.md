# Drop Debian packaging, move RPM packaging off `main` onto a dedicated branch — Design Spec

**Status: Implemented 2026-09-16.** `main` @ `7d3d788` (packaging removal +
`dispatch-packaging.yml`) through `4a022f9` (cherry-picked unrelated
spf-tools-detection commit from the now-deleted `master`, see below);
`rpm` @ `d33fadd`. See "Implementation Notes" at the end for what changed
from the design below during execution — mainly the extraction method and
an unplanned `main`/`master` branch consolidation that surfaced along the
way. `dispatch-packaging.yml` has not yet been exercised against a real
release tag; that remains open, see Testing/Verification.

## Overview

`contrib/rpm/` and its tag-triggered package-build workflow
(`.github/workflows/build-rpm.yml`) currently live on `main` alongside
postallow's own source. This spec moves them onto a dedicated, disposable
`rpm` branch that gets rebased onto `main` at release time, so RPM
packaging is no longer mixed into the same branch as the software itself.

**Debian packaging is dropped from this repo entirely, not moved to a
branch** — the user will package postallow for Debian directly, outside
this repo, making `debian/` and `.github/workflows/build-deb.yml`
redundant here.

This was raised as a prerequisite blocking two other specs
(`2026-09-15-incorporate-spf-tools.md`,
`2026-09-15-vendor-route-summarization.md`, tracked in `TODO.md` item 1)
during `paad:pushback` review — "I only realised that now" — and is
written up here as its own architectural change per
`superpowers:brainstorming`. The original design (written earlier in the
same session) covered both `deb` and `rpm` branches; narrowed to RPM-only
plus outright Debian removal per direct user instruction.

## Background / Current State

- `.github/workflows/ci.yml` (general cross-platform test matrix, runs on
  every PR against `main`) does **not** reference `debian/` or
  `contrib/rpm/` at all — confirmed by grep. It stays on `main` unchanged,
  including its unrelated `debian-13` test job (a Docker image used to test
  postallow generically via `make install`, nothing to do with
  `dpkg-buildpackage` or the `debian/` directory).
- `.github/workflows/build-rpm.yml` is the only workflow that reads
  `contrib/rpm/`. It triggers on `push: tags: v*`, builds a source tarball
  via `git archive HEAD`, builds the RPM inside an AlmaLinux 10 Docker
  container using `contrib/rpm/postallow.spec`, and uploads to the GitHub
  Release matching `github.ref_name`.
- `.github/workflows/build-deb.yml` and `debian/` are simply removed —
  see Design, below.
- Release process today: bump `version=` in `postallow` (+ mirror it into
  `contrib/rpm/postallow.spec`'s `%global pkg_version`, same commit/PR) →
  tag `vX.Y.Z` on `main` → push tag → `build-rpm.yml` fires off that tag.
- **Hard constraint:** a git tag name can only point at one commit per
  repository. Once the `rpm` branch diverges from `main` (even by a rebase,
  which rewrites commit SHAs), `vX.Y.Z` cannot simultaneously mean "this
  commit on `main`" and "this commit on `rpm`". The design below avoids
  ever needing the same tag name to exist on both branches.

## Design

### Debian removal (one-time, not a branch)

- Delete `debian/` and `.github/workflows/build-deb.yml` from `main` (and
  from `release/4.5.1` as part of the main/release sync already tracked in
  `TODO.md`).
- Remove the `edmundlod/apt` `repository_dispatch` step (currently inside
  `build-deb.yml`, goes away with the file) — no replacement; not this
  repo's concern anymore.
- Drop the `spf-tools`/`route-summarization` `Depends:` lines that would
  otherwise need updating in `debian/control` — moot, the file is gone.
  This also means the spf-tools/route-summarization specs no longer need a
  "debian/copyright" attribution-file update; drop that from their scope
  too (tracked back in those specs, not here).
- Leave the `debian-13` job in `ci.yml` alone — it tests generic
  `make install` behavior on Debian, unrelated to packaging.

### Branch layout (RPM only)

- **`main`**: postallow source, `Makefile`, `contrib/install.sh`,
  `contrib/apparmor/`, man pages, docs, `.github/workflows/ci.yml`. No
  `contrib/rpm/`, no `build-rpm.yml`, no `debian/` (removed, not moved).
- **`rpm`**: everything from `main`, plus `contrib/rpm/` and
  `.github/workflows/build-rpm.yml`.

`rpm` is treated as a **rebase-only, disposable branch**: its history gets
rewritten on every release sync. Nobody should base long-lived work on its
tip — it's regeneratable at any time from `main` plus its own handful of
packaging-only commits (currently: the commits that added `contrib/rpm/*`
and `build-rpm.yml` — these already exist in the repo's history and just
need to be identified and cherry-picked onto a fresh branch cut from `main`
as the one-time extraction step, then maintained by rebase from then on).

### Release data flow

1. On `main`: bump `version=` in `postallow`, update `CHANGELOG.md`, commit,
   tag `vX.Y.Z`, push the tag. Unchanged from today, minus the
   `postallow.spec` version mirroring (that moves to step 2, on the branch
   that actually owns that file).
2. New workflow on `main`, `.github/workflows/dispatch-packaging.yml`,
   triggered by `push: tags: v*`:
   - Checkout `rpm`.
   - `git rebase vX.Y.Z` (replays `rpm`'s packaging-only commits on top of
     the newly tagged source).
   - Bump `contrib/rpm/postallow.spec`'s `%global pkg_version` to match
     `X.Y.Z` via `sed`. Commit as a small `release: sync to vX.Y.Z` commit
     directly on the branch.
   - `git push --force-with-lease` (rebase rewrites history — see Branch
     layout above).
3. `build-rpm.yml` changes trigger from `push: tags: v*` to
   `push: branches: [rpm]` — this is the one behavior change needed in the
   existing build workflow, and it's what avoids the tag-collision
   constraint: only `main` ever holds a real `vX.Y.Z` tag. It targets the
   existing GitHub Release (created off `main`'s tag) via
   `softprops/action-gh-release`'s explicit `tag_name:` input, reading the
   version back out of `postallow.spec` (just synced in step 2), rather
   than relying on `github.ref_name` being a tag.
4. Everything downstream of a successful build (GitHub Release asset
   upload) is unchanged.

### One-time extraction (this spec's actual migration work)

- Identify the commits currently on `main`/`release/4.5.1` that added or
  modified `contrib/rpm/*` and `build-rpm.yml` (visible in
  `git log -- contrib/rpm/ .github/workflows/build-rpm.yml`).
- Cut `rpm` from the synced `main` (post the prerequisite main/release sync
  already tracked in `TODO.md`), then either cherry-pick those packaging
  commits onto the branch, or recreate the current state of
  `contrib/rpm/`/`build-rpm.yml` as a single fresh commit if history isn't
  worth preserving — decide at implementation time based on how clean the
  cherry-pick turns out to be.
- Remove `contrib/rpm/`, `build-rpm.yml`, `debian/`, and `build-deb.yml`
  from `main` in the same pass.
- Add `dispatch-packaging.yml` to `main`.
- Update `build-rpm.yml`'s trigger and release-targeting as described
  above.

## Error Handling

- **Rebase conflict** during step 2 (e.g. an `rpm`-branch commit touched a
  file `main` also changed, like `Makefile`): the workflow fails, pushes
  nothing. The RPM release doesn't happen until someone resolves it
  manually (`git checkout rpm && git rebase vX.Y.Z`, fix, push) — same
  manual-resolution story a packager faces today, now surfaced as a CI
  failure instead of silently building stale packaging against new source.
- **Build failure on `rpm`** after a successful rebase: fails exactly as
  today — the GitHub Release exists (created off `main`'s tag) but is
  missing the RPM asset, same visibility as now.

## Testing / Verification

- Dry-run `dispatch-packaging.yml` against a scratch tag on a fork or test
  branch before wiring it to real releases.
- Confirm `build-rpm.yml` still builds correctly when triggered by
  push-to-branch instead of tag.
- Confirm `softprops/action-gh-release`'s explicit `tag_name:` targeting
  actually attaches the built RPM to the correct GitHub Release (the one
  behavior change in the build workflow itself).
- After the one-time extraction, confirm `main`'s `ci.yml` still passes
  unmodified (it never depended on the removed paths).
- Confirm `make install` (from `main`) and a fresh `rpm` checkout's
  packaging build both still produce a working install, to catch anything
  the extraction accidentally broke.
- Confirm no remaining references to `debian/`, `build-deb.yml`, or the
  `edmundlod/apt` dispatch anywhere in the repo after removal
  (`grep -rn "debian/\|build-deb\|edmundlod/apt" .` — man pages, README,
  and `contrib/rpm/postallow.spec`'s changelog references may need
  updating too).

## Non-Goals

- Changing what gets packaged or how `postallow` itself installs — this is
  purely a repo/CI restructuring.
- Debian packaging of any kind — dropped from this repo, handled directly
  by the user elsewhere.
- The spf-tools/route-summarization incorporation work — this spec is a
  prerequisite for those, not a replacement.

## Implementation Notes (2026-09-16)

- **Extraction method:** the "One-time extraction" section above left
  cherry-pick vs. recreate-as-one-commit as an implementation-time call.
  Checked: every commit touching `contrib/rpm/`/`build-rpm.yml` in history
  was heavily mixed with unrelated files (`postallow`, README, man pages,
  `CHANGELOG.md`, `contrib/archlinux/`, `debian/*`) — cherry-picking would
  have pulled in or conflicted with unrelated content. Went with the
  simpler path instead: since `main` was fast-forwarded to
  `release/4.5.1` first (a separate prerequisite, already tracked), the
  `rpm` branch was cut directly from that synced `main` — it already
  contained `contrib/rpm/postallow.spec` and `build-rpm.yml` in their
  current form, so no recreation was needed either; only `build-rpm.yml`'s
  trigger/version-extraction/release-targeting were changed on the branch.
- **Unplanned `main`/`master` consolidation:** while pushing, discovered
  the repo had two parallel trunk branches — `main` (this session's work)
  and `master` (GitHub's actual configured default branch, which had
  independently gained a PR, #38, unrelated to this spec). Both shared the
  exact same base (`release/4.5.1`'s tip) with one unique commit each, so
  no conflict; `master`'s unique commit was cherry-picked onto `main`
  (`4a022f9`), GitHub's default branch was switched to `main`, and `master`
  was deleted (no open PRs, no branch protection on either — confirmed via
  `gh api`/`gh pr list` before deleting). Not part of the original design;
  the design's Prerequisites (main/release sync, Debian/RPM removal) had
  no way to anticipate a second trunk branch existing.
- `README.md`'s "via apt" install section and its TOC entry were removed
  as part of the Debian removal (the install instructions depended on
  `build-deb.yml`'s now-deleted `edmundlod/apt` dispatch) — not explicitly
  called out in the Design above, added during implementation after
  confirming with the user.
- Outstanding from Testing/Verification: `dispatch-packaging.yml` has not
  been dry-run against a real or scratch tag yet — it's untested until the
  next actual release tag is pushed (or a deliberate test tag is used
  first).

# Move Debian/RPM packaging off `main` onto dedicated branches — Design Spec

## Overview

`debian/`, `contrib/rpm/`, and the two tag-triggered package-build workflows
(`.github/workflows/build-deb.yml`, `build-rpm.yml`) currently live on
`main` alongside postallow's own source. This spec moves them onto two
dedicated, disposable branches (`deb`, `rpm`) that get rebased onto `main`
at release time, so distro-specific packaging concerns are no longer mixed
into the same branch as the software itself.

This was raised as a prerequisite blocking two other specs
(`2026-09-15-incorporate-spf-tools.md`,
`2026-09-15-vendor-route-summarization.md`, tracked in `TODO.md` item 1)
during `paad:pushback` review — "I only realised that now" — and is
written up here as its own architectural change per
`superpowers:brainstorming`.

## Background / Current State

- `.github/workflows/ci.yml` (general cross-platform test matrix, runs on
  every PR against `main`) does **not** reference `debian/` or
  `contrib/rpm/` at all — confirmed by grep. It stays on `main` unchanged.
- `.github/workflows/build-deb.yml` and `build-rpm.yml` are the only two
  workflows that read those directories. Both currently trigger on
  `push: tags: v*` and run against whatever `debian/`/`contrib/rpm/`
  content exists on the tagged commit (today, `main`'s).
- `build-deb.yml`: runs `dpkg-buildpackage`, uploads the `.deb` to the
  GitHub Release matching `github.ref_name` (the pushed tag), then
  dispatches to a separate `edmundlod/apt` repo via `repository_dispatch`.
- `build-rpm.yml`: builds a source tarball from `git archive HEAD`, builds
  the RPM inside an AlmaLinux 10 Docker container using
  `contrib/rpm/postallow.spec`, uploads to the same GitHub Release.
- Release process today: bump `version=` in `postallow` (+ mirror it into
  `contrib/rpm/postallow.spec`'s `%global pkg_version` and
  `debian/changelog`, all in the same commit/PR) → tag `vX.Y.Z` on `main` →
  push tag → both build workflows fire independently off that one tag.
- **Hard constraint:** a git tag name can only point at one commit per
  repository. Once `deb`/`rpm` branches diverge from `main` (even by a
  rebase, which rewrites commit SHAs), `vX.Y.Z` cannot simultaneously mean
  "this commit on `main`" and "this commit on `deb`". The design below
  avoids ever needing the same tag name to exist on more than one branch.

## Design

### Branch layout

- **`main`**: postallow source, `Makefile`, `contrib/install.sh`,
  `contrib/apparmor/`, man pages, docs, `.github/workflows/ci.yml`. No
  `debian/`, no `contrib/rpm/`, no `build-deb.yml`/`build-rpm.yml`.
- **`deb`**: everything from `main`, plus `debian/` and
  `.github/workflows/build-deb.yml`.
- **`rpm`**: everything from `main`, plus `contrib/rpm/` and
  `.github/workflows/build-rpm.yml`.

`deb` and `rpm` are treated as **rebase-only, disposable branches**: their
history gets rewritten on every release sync. Nobody should base long-lived
work on their tips — they're regeneratable at any time from `main` plus
their own handful of packaging-only commits (currently: the commits that
added `debian/*`, `contrib/rpm/*`, and the two build workflows — these
already exist in the repo's history and just need to be identified and
cherry-picked onto fresh branches cut from `main` as the one-time
extraction step, then maintained by rebase from then on).

### Release data flow

1. On `main`: bump `version=` in `postallow`, update `CHANGELOG.md`, commit,
   tag `vX.Y.Z`, push the tag. Unchanged from today, minus the
   `debian/changelog`/`postallow.spec` version mirroring (that moves to
   step 2, on the branches that actually own those files).
2. New workflow on `main`, `.github/workflows/dispatch-packaging.yml`,
   triggered by `push: tags: v*`. For each of `deb` and `rpm`:
   - Checkout the branch.
   - `git rebase vX.Y.Z` (replays that branch's packaging-only commits on
     top of the newly tagged source).
   - Bump that branch's own version file to match `X.Y.Z`: `debian/changelog`
     via `dch --newversion X.Y.Z-1`, or `contrib/rpm/postallow.spec`'s
     `%global pkg_version` via `sed`. Commit as a small
     `release: sync to vX.Y.Z` commit directly on the branch.
   - `git push --force-with-lease` (rebase rewrites history — see Branch
     layout above).
3. `build-deb.yml`/`build-rpm.yml` change trigger from `push: tags: v*` to
   `push: branches: [deb]` / `[rpm]` respectively — this is the one
   behavior change needed in the existing build workflows, and it's what
   avoids the tag-collision constraint: only `main` ever holds a real
   `vX.Y.Z` tag. The build workflows target the existing GitHub Release
   (created off `main`'s tag) via `softprops/action-gh-release`'s explicit
   `tag_name:` input, reading the version back out of the file they just
   synced in step 2 (`debian/changelog` / `postallow.spec`), rather than
   relying on `github.ref_name` being a tag.
4. Everything downstream of a successful build (GitHub Release asset
   upload, `edmundlod/apt` repository_dispatch) is unchanged.

### One-time extraction (this spec's actual migration work)

- Identify the commits currently on `main`/`release/4.5.1` that added or
  modified `debian/*`, `contrib/rpm/*`, `build-deb.yml`, and `build-rpm.yml`
  (visible in `git log -- debian/ contrib/rpm/ .github/workflows/build-*.yml`).
- Cut `deb` and `rpm` from the synced `main` (post the prerequisite
  main/release sync already tracked in `TODO.md`), then either cherry-pick
  those packaging commits onto each branch, or recreate the current state
  of `debian/`/`contrib/rpm/`/the relevant workflow file as a single fresh
  commit per branch if history isn't worth preserving — decide at
  implementation time based on how clean the cherry-pick turns out to be.
- Remove `debian/`, `contrib/rpm/`, `build-deb.yml`, `build-rpm.yml` from
  `main` in the same pass.
- Add `dispatch-packaging.yml` to `main`.
- Update `build-deb.yml`/`build-rpm.yml`'s trigger and release-targeting as
  described above.

## Error Handling

- **Rebase conflict** during step 2 (e.g. a `deb`-branch commit touched a
  file `main` also changed, like `Makefile`): the workflow fails, pushes
  nothing. That distro's release doesn't happen until someone resolves it
  manually (`git checkout deb && git rebase vX.Y.Z`, fix, push) — same
  manual-resolution story a packager faces today, now surfaced as a CI
  failure instead of silently building stale packaging against new source.
- **Build failure on `deb`/`rpm`** after a successful rebase: fails exactly
  as today — the GitHub Release exists (created off `main`'s tag) but is
  missing that platform's asset, same visibility as now.
- No change to error handling for the downstream apt/COPR dispatch steps.

## Testing / Verification

- Dry-run `dispatch-packaging.yml` against a scratch tag on a fork or test
  branch before wiring it to real releases.
- Confirm `build-deb.yml`/`build-rpm.yml` still build correctly when
  triggered by push-to-branch instead of tag.
- Confirm `softprops/action-gh-release`'s explicit `tag_name:` targeting
  actually attaches the built package to the correct GitHub Release (the
  one behavior change in the build workflows themselves).
- After the one-time extraction, confirm `main`'s `ci.yml` still passes
  unmodified (it never depended on the removed paths).
- Confirm `make install` (from `main`) and a fresh `deb`/`rpm` checkout's
  packaging build both still produce a working install, to catch anything
  the extraction accidentally broke.

## Non-Goals

- Changing what gets packaged or how `postallow` itself installs — this is
  purely a repo/CI restructuring.
- The spf-tools/route-summarization incorporation work — this spec is a
  prerequisite for those, not a replacement.

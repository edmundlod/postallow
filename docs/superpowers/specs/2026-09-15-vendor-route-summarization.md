# Vendor route-summarization's aggregateCIDR.pl into postallow — Design Spec

## Overview

`postallow` currently locates `aggregateCIDR.pl` (from the
**route-summarization** project) via a PATH lookup at startup, relying on it
being fetched by `contrib/install.sh` or provided by an OS package. This
spec vendors the file directly into the postallow repo/package instead:

```
postallow
├── SPF parsing / recursion    — separate spec: 2026-09-15-incorporate-spf-tools.md
├── DNS querying                /
├── CIDR normalisation         /
├── route summarisation   \_ this spec
└── Postfix output
```

Originally written as one combined spec covering both spf-tools and
route-summarization; split into two independently-shippable specs/PRs
during `paad:pushback` review on 2026-09-15 (they share a motivation but
not an implementation — see that review for the cohesion rationale). This
piece carries far less risk than the spf-tools spec: one new vendored file,
one install-path change, no shell-logic porting.

## Background / Current State

`postallow` locates `aggregateCIDR.pl` via `command -v aggregateCIDR.pl`
(PATH lookup) at startup; failure aborts with a fatal message linking to
`https://github.com/edmundlod/route-summarization`.

## Licensing (verified via `gh api`, not assumed)

**nabbi/route-summarization: MIT License**, confirmed `LICENSE` file
(`Copyright (c) 2021-2026 Nic Boet`). This was unresolved when the spec was
first drafted — GitHub reported `license: null` with no `LICENSE` file
anywhere in the repo — but nabbi added one following the user's outreach.
Clear to vendor now: retain the copyright and permission notice (MIT's only
requirement). The user's own fork, `edmundlod/route-summarization`, still
carries a separately self-added BSD-3-Clause `LICENSE`
(`Copyright (c) 2025, Edmund Lodewijks`) predating nabbi's MIT grant — now
irrelevant; vendor against nabbi's MIT terms, not the fork's claim.

## Prerequisites (must land before this spec's implementation branches)

Same as the spf-tools spec (`2026-09-15-incorporate-spf-tools.md`):

1. **Sync `main` with `release/4.5.1`** (fast-forward and push, confirm
   with the user first — shared branch).
2. **Move `debian/`, `contrib/rpm/`, and `.github/workflows/ci.yml` off
   `main` onto their own dedicated branches** before this work starts —
   raised by the user during spec review; a separate architectural change,
   not designed here. Until it lands, this spec's implementation does not
   touch `debian/control`, `contrib/rpm/postallow.spec`, or
   `.github/workflows/ci.yml` — see Design, below.

## Design

`aggregateCIDR.pl` is Perl — can't be inlined into the POSIX-sh `postallow`
script. Vendor it as its own file, still invoked as a subprocess but no
longer externally fetched:

- Add `contrib/aggregateCIDR.pl` with an attribution header noting original
  author Nic Boet / `nabbi` (https://github.com/nabbi/route-summarization),
  MIT License, reproducing the copyright and permission notice verbatim as
  required by the license.
- Install via the `Makefile`'s `install` target alongside `postallow` in
  `$(BINDIR)`; replace the `command -v aggregateCIDR.pl` PATH lookup in
  `postallow` with a fixed install path.
- Remove the "Install aggregateCIDR.pl" block from `contrib/install.sh`.
- Update the `/usr/bin/aggregateCIDR.pl` path in
  `contrib/apparmor/usr.bin.postallow` to the new vendored install path.
- Update `README.md`/man pages to drop route-summarization as an external
  requirement; adjust the `nabbi` credit line.
- Add the MIT license text to the repo (e.g.
  `LICENSES/MIT-route-summarization.txt`, since it's a distinct copyright
  holder from postallow's own MIT grant) and reference it alongside the
  Apache-2.0 text (from the spf-tools spec) in `LICENSE.md`'s "Third-party
  code" section and in `debian/copyright` *(once that file is back on a
  branch this work can reach — see Prerequisites)*.
- *(Not included: removing `route-summarization` from
  `contrib/rpm/postallow.spec` `Requires:` / `debian/control` `Depends:`,
  or removing its clone/install step from `.github/workflows/ci.yml` — see
  Prerequisites. Also not included: adding the real transitive dependency,
  `libnet-cidr-lite-perl`/RPM equivalent, to those files — same reason,
  deferred to the packaging branches once they exist.)*

## Error Handling

If the vendored `aggregateCIDR.pl` isn't installed at its expected path,
fail the same way postallow already fails today (clear fatal message,
non-zero exit) — no behavior change, just no more PATH search.

## Testing / Verification

- `make install DESTDIR=/tmp/stage PREFIX=/usr/local` — confirm
  `aggregateCIDR.pl` installs cleanly at the new fixed path and postallow
  finds it there.
- End-to-end run against a real domain, before and after, confirming
  identical aggregated CIDR output.
- `grep -rn "route-summarization" .` — remaining hits should only be
  attribution/credit text and the `aggregateCIDR.pl` provenance header.

## Non-Goals

- Porting spf-tools (`despf.sh`/`normalize.sh`) — see
  `2026-09-15-incorporate-spf-tools.md`.
- Version bump to 4.6.0 — a separate `release: bump version to 4.6.0`
  commit after both specs land, matching existing repo convention.
- Moving `debian/`, `contrib/rpm/`, and `.github/workflows/ci.yml` off
  `main` — see Prerequisites; needs its own spec.

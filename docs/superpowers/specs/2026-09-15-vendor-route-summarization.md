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
2. **Drop Debian packaging from the repo entirely, and move RPM packaging
   (`contrib/rpm/`) off `main` onto a dedicated `rpm` branch** before this
   work starts — raised by the user during spec review; designed
   separately at
   `docs/superpowers/specs/2026-09-15-drop-debian-split-rpm-branch.md`.
   Until it lands, this spec's implementation does not touch
   `contrib/rpm/postallow.spec` — see Design, below.
   `.github/workflows/ci.yml` is unaffected by that other spec (stays on
   `main`) and *is* in scope here — it currently installs
   `aggregateCIDR.pl` as part of its test setup and needs the
   corresponding step removed. `debian/control`/`debian/copyright` no
   longer exist once the other spec lands, so there's nothing there to
   update.

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
- Remove the `aggregateCIDR.pl` clone/install step from
  `.github/workflows/ci.yml` (it stays on `main`, in scope here); keep the
  Perl module (`libnet-cidr-lite-perl`/`libnetaddr-ip-perl`) install steps.
- Add the MIT license text to the repo (e.g.
  `LICENSES/MIT-route-summarization.txt`, since it's a distinct copyright
  holder from postallow's own MIT grant) and reference it alongside the
  Apache-2.0 text (from the spf-tools spec) in `LICENSE.md`'s "Third-party
  code" section.
- *(Not included: removing `route-summarization` from
  `contrib/rpm/postallow.spec` `Requires:`, or adding the real transitive
  dependency — `perl-Net-CIDR-Lite` or equivalent — to that file. Deferred
  to the `rpm` branch once it exists, per Prerequisites. `debian/control`
  doesn't exist once that spec lands, so nothing to update there.)*

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
- Dropping Debian packaging and moving RPM packaging off `main` — see
  Prerequisites; spec written at
  `docs/superpowers/specs/2026-09-15-drop-debian-split-rpm-branch.md`.

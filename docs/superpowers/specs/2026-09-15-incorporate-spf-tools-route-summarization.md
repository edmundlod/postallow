# Incorporate spf-tools and route-summarization into postallow — Design Spec

## Overview

`postallow` currently shells out to two external projects at runtime:
**spf-tools** (`despf.sh`, `normalize.sh`) and **route-summarization**
(`aggregateCIDR.pl`), both fetched by `contrib/install.sh` or expected as OS
packages. This spec incorporates both directly into postallow's own
codebase/package so the project ships as one self-contained tool:

```
postallow
├── SPF parsing / recursion
├── DNS querying
├── CIDR normalisation
├── route summarisation
└── Postfix output
```

This is **project 1 of 2**. A follow-up `--check` (ad-hoc single-domain
SPF/DNS debugging query) is a separate spec/plan, deliberately out of scope
here — see Non-Goals.

## Background / Current State

- `despf.sh` sources `include/global.inc.sh` and `include/despf.inc.sh`
  relative to its own script directory — a dependency the current
  `contrib/install.sh` actually breaks today (it copies top-level `*.sh`
  files flat into `/usr/local/bin`, missing `include/`).
- `postallow` reads `spftoolspath` from config and calls
  `"${spftoolspath}"/despf.sh` and `"${spftoolspath}"/normalize.sh` at
  **four call sites** on the current codebase (`origin/release/4.5.1`):
  `query_host()`, `query_block_host()`, `query_yahoo_host()` (each call
  `despf.sh`), the `--quick-add` block (one `despf.sh` + one `normalize.sh`
  call), and the main aggregation pipeline for both the allowlist and (when
  `enable_blocklist=yes`) the blocklist (`normalize.sh`).
- `aggregateCIDR.pl` is located via `command -v aggregateCIDR.pl` (PATH
  lookup) at postallow startup; failure aborts with a link to
  `https://github.com/edmundlod/route-summarization`.
- Repo hygiene: local `main` is 22 commits behind `origin/release/4.5.1`
  (missing `--quick-add`, the rpm move, Arch packaging, apt-dispatch fixes).
  Per the user, `main` must be fast-forwarded to `release/4.5.1` and pushed
  before the implementation work branches off it.

## Licensing (verified via `gh api`, not assumed)

- **spf-tools/spf-tools: Apache License 2.0**, confirmed `LICENSE` file.
  `despf.sh`, `normalize.sh`, and both `include/*.inc.sh` carry Apache-2.0
  headers. Clear to incorporate, provided Apache-2.0 §4 obligations are met
  (retain copyright/license notices, state what changed).
- **nabbi/route-summarization: no license.** GitHub reports `license: null`;
  no `LICENSE` file or license text anywhere in the repo, including
  `aggregateCIDR.pl` itself. The user's own fork, `edmundlod/route-summarization`,
  has a self-added `LICENSE` claiming BSD-3-Clause
  (`Copyright (c) 2025, Edmund Lodewijks`), which does not by itself carry
  authority over nabbi's original, unlicensed code. The user has contacted
  nabbi about formalizing this; outcome unknown. **Per explicit user
  direction, incorporate it now anyway**, isolated in its own file with its
  own attribution header, so it is a one-file revert if nabbi objects.

## Design

### 0. Branch hygiene (prerequisite, not part of the technical design)

Fast-forward `main` to `origin/release/4.5.1` and push; branch the
implementation work from the resulting `main`. This pushes to a shared
branch — confirm with the user immediately before doing it, independent of
spec/plan approval.

### 1. SPF parsing / recursion / DNS querying / CIDR normalisation

Port, verbatim (straight copy to avoid behavioral drift), directly into
`postallow`:
- From `include/despf.inc.sh`: `myhost`, `get_txt`, `get_mx`, `get_addr`,
  `get_ns`, `findns`, `printip`, `dea`, `demx`, `parsepf`, `in_list`,
  `has_macro`, `getem`, `getamx`, `despf`, `cleanup`, `despfit`,
  `checkval4`, `numlesseq`, `checkval6`, `expand6`.
- From `include/global.inc.sh`: the `SPFTRC` default.
- From `normalize.sh`: `ip2int`, `int2ip`, `network`, and the stdin filter
  loop, preserving the existing `-i`/ignore-mode semantics that back
  postallow's `invalid_cidr=fix|remove` config option (`_norm_flag`).

No new sourced lib file — the project has no existing `lib/`-style
convention, and this logic is only ever used by postallow itself. Insert as
one clearly delimited block with a header comment: adapted from spf-tools,
Copyright 2015 spf-tools team (AUTHORS, https://github.com/spf-tools/spf-tools),
Apache License 2.0, noting the change made (namespacing/integration only,
no logic changes).

Replace all four `despf.sh`/`normalize.sh` call sites (listed in
Background) with direct calls to the now-local functions.

**Removals:** `spftoolspath` config option (`conf/postallow.conf.in`,
`man/man5/postallow.conf.5`); the "Install spf-tools" block in
`contrib/install.sh`; `spf-tools` from `Requires:`/`Depends:` in
`contrib/rpm/postallow.spec` / `debian/control`; spf-tools clone/install
steps in `.github/workflows/ci.yml`; `/usr/bin/spf-tools/`, `despf.sh`,
`/tmp/despf-loop-*` rules in `contrib/apparmor/usr.bin.postallow` (retain
whatever `host` command access `myhost()` needs, under postallow's own
profile).

**Attribution artifacts:** add full Apache-2.0 text to the repo (e.g.
`LICENSES/Apache-2.0.txt`); reference it from a new "Third-party code"
section in `LICENSE.md` and from `debian/copyright`.

**Docs:** update `README.md`, `man/man1/postallow.1`,
`man/man5/postallow.conf.5`, and add a `MIGRATING.md` entry, to drop
spf-tools as an external requirement; keep/adjust the "Thanks to Jan
Sarenik" credit; standardize the three inconsistent upstream URLs
currently in the repo (`edmundlod/spf-tools`, `spf-tools/spf-tools`,
`jsarenik/spf-tools`) on `https://github.com/spf-tools/spf-tools`.

### 2. Route summarisation

`aggregateCIDR.pl` is Perl — can't be inlined into the POSIX-sh script.
Vendor it as its own file, still invoked as a subprocess but no longer
externally fetched:

- Add `contrib/aggregateCIDR.pl` with an attribution header noting original
  author `nabbi` (https://github.com/nabbi/route-summarization) and the
  BSD-3-Clause terms as claimed in the user's fork — deliberately isolated
  given the pending license discussion.
- Install via the `Makefile`'s `install` target alongside `postallow` in
  `$(BINDIR)`; replace the `command -v aggregateCIDR.pl` PATH lookup with a
  fixed install path.
- Remove the "Install aggregateCIDR.pl" block from `contrib/install.sh`.
- Remove `route-summarization` from `Requires:`/`Depends:` in
  `contrib/rpm/postallow.spec` / `debian/control`; add the real transitive
  dependency: `libnet-cidr-lite-perl` (Debian, already used in
  `.github/workflows/ci.yml`) and its RPM equivalent (verify exact name,
  likely `perl-Net-CIDR-Lite`).
- Remove the route-summarization clone/install step from
  `.github/workflows/ci.yml`; keep the Perl module install steps.
- Update the `/usr/bin/aggregateCIDR.pl` path in
  `contrib/apparmor/usr.bin.postallow` to the new vendored install path.
- Update `README.md`/man pages to drop route-summarization as an external
  requirement; adjust the `nabbi` credit line.

### 3. Versioning

Bump to 4.6.0 (next minor) in `postallow` (`version=`),
`contrib/rpm/postallow.spec`, `debian/changelog`, and `CHANGELOG.md`,
matching the entry style already used for 4.5.0/4.5.1.

## Error Handling

- If the vendored `aggregateCIDR.pl` isn't installed at its expected path,
  fail the same way postallow already fails today (clear fatal message,
  non-zero exit) — no behavior change, just no more PATH search.
- Inlined `despf`/`normalize` functions keep their current error behavior
  verbatim (e.g. `myhost`'s existing retry-then-exit-1 on DNS failure) —
  this is a port, not a rewrite, so failure modes must not change.

## Testing / Verification

- `sh -n postallow` after the merge.
- `make install DESTDIR=/tmp/stage PREFIX=/usr/local` — confirm postallow
  and vendored `aggregateCIDR.pl` install cleanly, no remaining
  `spftoolspath`/PATH-found `aggregateCIDR.pl` references.
- End-to-end run against a real domain with a known SPF record, before and
  after, including `--quick-add <domain>`; diff output to confirm parity
  with the external scripts being replaced.
- `grep -rn "spftoolspath\|spf-tools\|route-summarization" .` — remaining
  hits should only be attribution/credit text and the `aggregateCIDR.pl`
  provenance header.

## Non-Goals

- `postallow --check [domain]` (ad-hoc single-domain SPF/DNS debug query,
  independent of `allowlist_hosts`/`custom_hosts`, reporting resolved
  CIDRs and a DNS lookup count) — separate follow-up spec/plan, to build on
  the now-inline despf functions from this project (which make instrumenting
  a lookup counter straightforward).

## Open Risks

- **route-summarization licensing is unresolved.** nabbi has not confirmed
  terms; the BSD-3-Clause claim in the user's fork has no demonstrated
  authority over the original code. Vendoring proceeds per explicit user
  instruction, isolated to one file for easy reversion if nabbi objects.

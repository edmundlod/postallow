# Incorporate spf-tools into postallow — Design Spec

## Overview

`postallow` currently shells out to **spf-tools** (`despf.sh`, `normalize.sh`)
at runtime, fetched by `contrib/install.sh` or expected as an OS package.
This spec ports spf-tools' SPF-parsing/recursion, DNS-querying, and
CIDR-normalisation logic directly into `postallow` itself, so it no longer
depends on an external spf-tools install:

```
postallow
├── SPF parsing / recursion   \_ this spec
├── DNS querying               /
├── CIDR normalisation        /
├── route summarisation        — separate spec: 2026-09-15-vendor-route-summarization.md
└── Postfix output
```

Originally written as one combined spec covering both spf-tools and
route-summarization; split into two independently-shippable specs/PRs during
`paad:pushback` review on 2026-09-15 (they share a motivation but not an
implementation — see that review for the cohesion rationale).

A follow-up `postallow --check [domain]` (ad-hoc single-domain SPF/DNS debug
query) is separate, later work — see Non-Goals.

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
- `query_yahoo_host()` calls `despf.sh -d ns1.yahoo.com "$1"` — `despf.sh`'s
  own wrapper parses `-d` into a `DNS_SERVER` global that `despf.inc.sh`'s
  `parsepf()` reads directly, forcing DNS resolution against Yahoo's own
  nameserver instead of auto-detecting one.
- `postallow` already defines its own `cleanup()` function (removes
  `tmp1`–`tmp5`/`blocktmp1`–`5`, called once at the end of a run) —
  `despf.inc.sh` also defines a function named `cleanup(loopfile)` (removes
  a per-query loop-detection tempfile). Same name, different signatures and
  purposes.
- Repo hygiene: local `main` is 22 commits behind `origin/release/4.5.1`
  (missing `--quick-add`, the rpm move, Arch packaging, apt-dispatch fixes).

## Licensing (verified via `gh api`, not assumed)

**spf-tools/spf-tools: Apache License 2.0**, confirmed `LICENSE` file.
`despf.sh`, `normalize.sh`, and both `include/*.inc.sh` carry Apache-2.0
headers. Clear to incorporate, provided Apache-2.0 §4 obligations are met
(retain copyright/license notices, state what changed).

## Prerequisites (must land before this spec's implementation branches)

1. **Sync `main` with `release/4.5.1`.** Fast-forward `main` to
   `origin/release/4.5.1` and push; branch this work from the resulting
   `main`. Pushing to a shared branch — confirm with the user immediately
   before doing it, independent of spec approval.
2. **Move Debian packaging (`debian/`), RPM packaging (`contrib/rpm/`), and
   CI (`.github/workflows/ci.yml`) off `main` onto their own dedicated
   branches.** Raised by the user during spec review (`paad:pushback`,
   2026-09-15) — realized only after the original combined spec was
   written, and explicitly wanted *before* this work starts. This is a
   separate architectural change in its own right (how those branches get
   built/released, how CI keeps running, how they stay in sync with `main`)
   and is **not designed here** — it needs its own brainstorming/spec pass.
   Until it lands, **this spec's implementation does not touch
   `debian/control`, `contrib/rpm/postallow.spec`, or
   `.github/workflows/ci.yml`** — see Design, below. Those files' updates
   (removing the `spf-tools` dependency/CI steps) become follow-up work on
   the respective packaging branches once they exist.

## Design

### SPF parsing / recursion / DNS querying / CIDR normalisation

Port, verbatim (straight copy to avoid behavioral drift), directly into
`postallow`:
- From `include/despf.inc.sh`: `myhost`, `get_txt`, `get_mx`, `get_addr`,
  `get_ns`, `findns`, `printip`, `dea`, `demx`, `parsepf`, `in_list`,
  `has_macro`, `getem`, `getamx`, `despf`, `cleanup` (loop-detection
  tempfile cleanup — keep this name, see Name Collision below), `despfit`,
  `checkval4`, `numlesseq`, `checkval6`, `expand6`.
- From `include/global.inc.sh`: the `SPFTRC` default.
- From `normalize.sh`: `ip2int`, `int2ip`, `network`, and the stdin filter
  loop, preserving the existing `-i`/ignore-mode semantics that back
  postallow's `invalid_cidr=fix|remove` config option (`_norm_flag`).

No new sourced lib file — the project has no existing `lib/`-style
convention, and this logic is only ever used by postallow itself. Insert as
one clearly delimited block with a header comment: adapted from spf-tools,
Copyright 2015 spf-tools team (AUTHORS, https://github.com/spf-tools/spf-tools),
Apache License 2.0, noting the changes made (see the two items below —
namespacing and the Yahoo DNS override — nothing else).

**Name collision — must fix, not optional:** rename postallow's own,
pre-existing `cleanup()` (the `tmp1`–`5`/`blocktmp1`–`5` remover) to
**`cleanup_tmpfiles()`**, and update its one call site (end of the run)
accordingly. Leave the ported despf `cleanup(loopfile)` named as-is. Without
this rename, both functions share the name `cleanup`; POSIX shell keeps only
the textually-last definition, so depending on insertion order either (a)
postallow's own end-of-run cleanup silently becomes a no-op (leaked tmp
files every run), or worse (b) the despf-side `cleanup "$loopfile"` calls
made once per SPF query instead invoke postallow's version, which ignores
its argument and unconditionally deletes `tmp1`–`5` — including mid-loop,
while later `query_host()` calls are still appending to `tmp1`, silently
discarding every previously-queried domain's results from the final
allowlist with no error. (Found and confirmed during `paad:pushback`
review, 2026-09-15, against the actual `despf.inc.sh` source and
`postallow`'s current `cleanup()`.)

**Yahoo DNS override — must preserve:** the new `query_yahoo_host()` call
site must set `DNS_SERVER=ns1.yahoo.com` before invoking the ported
`despf`/`despfit`, replicating what `despf.sh -d ns1.yahoo.com` does today
(`parsepf()` reads `DNS_SERVER` directly). Scope the assignment to that call
only (e.g. run in a subshell, or save/restore the variable) so it doesn't
leak into the other three call sites. Without this, Yahoo's SPF data would
silently come from whatever nameserver auto-detection picks instead of
Yahoo's own authoritative server — no error, just different query behavior.

Replace all four `despf.sh`/`normalize.sh` call sites (listed in
Background) with direct calls to the now-local functions.

**Removals:** `spftoolspath` config option (`conf/postallow.conf.in`,
`man/man5/postallow.conf.5`); the "Install spf-tools" block in
`contrib/install.sh`; `/usr/bin/spf-tools/`, `despf.sh`, `/tmp/despf-loop-*`
rules in `contrib/apparmor/usr.bin.postallow` (retain whatever `host`
command access `myhost()` needs, under postallow's own profile). *(Not
included: `contrib/rpm/postallow.spec`, `debian/control`,
`.github/workflows/ci.yml` — see Prerequisites.)*

**Attribution artifacts:** add full Apache-2.0 text to the repo (e.g.
`LICENSES/Apache-2.0.txt`); reference it from a new "Third-party code"
section in `LICENSE.md` and from `debian/copyright` *(once that file is
back on a branch this work can reach — see Prerequisites)*.

**Docs:** update `README.md`, `man/man1/postallow.1`,
`man/man5/postallow.conf.5`, and add a `MIGRATING.md` entry, to drop
spf-tools as an external requirement; keep/adjust the "Thanks to Jan
Sarenik" credit; standardize the three inconsistent upstream URLs
currently in the repo (`edmundlod/spf-tools`, `spf-tools/spf-tools`,
`jsarenik/spf-tools`) on `https://github.com/spf-tools/spf-tools`.

## Error Handling

Inlined `despf`/`normalize` functions keep their current error behavior
verbatim (e.g. `myhost`'s existing retry-then-exit-1 on DNS failure) — this
is a port, not a rewrite, so failure modes must not change.

## Testing / Verification

- `sh -n postallow` after the merge.
- `make install DESTDIR=/tmp/stage PREFIX=/usr/local` — confirm postallow
  installs cleanly with no remaining `spftoolspath` references.
- End-to-end run against a real domain with a known SPF record, before and
  after, including `--quick-add <domain>`; diff output to confirm parity
  with the external scripts being replaced.
- Specifically diff `query_yahoo_host()`'s output before/after to confirm
  the `DNS_SERVER=ns1.yahoo.com` override still takes effect.
- Confirm `cleanup_tmpfiles()` still removes `tmp1`–`5`/`blocktmp1`–`5` at
  end of run, and that no stray `despf`-loop tempfiles are left in `/tmp`
  after a multi-domain run.
- `grep -rn "spftoolspath\|spf-tools" .` — remaining hits should only be
  attribution/credit text.

## Non-Goals

- `postallow --check [domain]` (ad-hoc single-domain SPF/DNS debug query,
  independent of `allowlist_hosts`/`custom_hosts`, reporting resolved
  CIDRs and a DNS lookup count) — separate follow-up spec/plan, to build on
  the now-inline despf functions from this project (which make instrumenting
  a lookup counter straightforward).
- Vendoring `aggregateCIDR.pl` (route-summarization) — see
  `2026-09-15-vendor-route-summarization.md`.
- Version bump to 4.6.0 — a separate `release: bump version to 4.6.0`
  commit after both this spec and the route-summarization spec land,
  matching existing repo convention (e.g. commit `1b1a249`, a dedicated
  release-bump commit separate from the feature commits before it).
- Moving `debian/`, `contrib/rpm/`, and `.github/workflows/ci.yml` off
  `main` — see Prerequisites; needs its own spec.

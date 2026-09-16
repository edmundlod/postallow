# TODO

Tracked here until each item gets its own spec/branch. See
`docs/superpowers/specs/` for specs already written.

## 1. Drop Debian packaging, move RPM packaging off `main` — SPEC WRITTEN

Debian packaging (`debian/`, `build-deb.yml`) is being dropped from this
repo entirely — the user will package postallow for Debian directly,
outside this repo. RPM packaging (`contrib/rpm/`, `build-rpm.yml`) moves to
a dedicated `rpm` branch instead. The general `ci.yml` test matrix stays on
`main` unchanged — it never referenced either directory (it does currently
install spf-tools/`aggregateCIDR.pl` for its own test setup, but that's the
spf-tools/route-summarization specs' concern, not this one's).

- Raised during `paad:pushback` review of the spf-tools/route-summarization
  specs (2026-09-15) — realized only after those specs were first drafted,
  and wanted *before* that work starts, not after. The "drop Debian
  entirely" refinement came later in the same session.
- Design brainstormed and written up:
  `docs/superpowers/specs/2026-09-15-drop-debian-split-rpm-branch.md`
  (branch `docs/spec-split-deb-rpm-branches`) — `debian/` deleted outright;
  `rpm` branch rebased onto `main` at release time via a new dispatch
  workflow; `build-rpm.yml` retriggers on branch push instead of tag push
  to sidestep the one-tag-one-commit constraint. Awaiting review before
  `writing-plans`.
- **Blocks:** `docs/superpowers/specs/2026-09-15-incorporate-spf-tools.md`
  and `docs/superpowers/specs/2026-09-15-vendor-route-summarization.md`
  both list this as a prerequisite and currently exclude
  `contrib/rpm/postallow.spec` from their own scope until it lands
  (their `debian/control`/`debian/copyright` mentions were dropped
  entirely once Debian packaging left the repo).

## 2. `postallow --check [domain]`

Ad-hoc single-domain SPF/DNS lookup for debugging a customer's mail
delivery problem, independent of `allowlist_hosts`/`custom_hosts` — doesn't
touch the live allowlist/blocklist files.

- `postallow --check` — run the DNS/SPF processing pipeline without writing
  to the live output files.
- `postallow --check example.com` — resolve just that one domain and print
  something like:

  ```
  SPF evaluation for example.com

  192.0.2.0/24
  2001:db8::/32

  DNS lookups: 3
  ```

- Scoped as an **ad-hoc single-domain lookup** (not a dry-run of the full
  configured pipeline across `allowlist_hosts`) — confirmed with the user
  earlier.
- `--quick-add` (on `release/4.5.1`, not yet on `main`) is the existing
  precedent for this kind of operational tooling: resolves one domain's
  SPF, appends the resulting rules to the live allowlist, and reloads
  Postfix. `--check` is the read-only counterpart — same SPF/DNS
  resolution, no write, no reload.
- Depends on the spf-tools incorporation landing first
  (`2026-09-15-incorporate-spf-tools.md`) — once `despf`/`despfit` are
  inline functions in `postallow` rather than an external subprocess,
  instrumenting a DNS-lookup counter for the `DNS lookups: N` line is
  straightforward; doing it against the external `despf.sh` subprocess
  would not be.
- Separate spec/plan, run 2 of 2 (per the user's split of "incorporate,
  then check").

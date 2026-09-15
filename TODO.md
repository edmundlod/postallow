# TODO

Tracked here until each item gets its own spec/branch. See
`docs/superpowers/specs/` for specs already written.

## 1. Move packaging/CI off `main`

`debian/`, `contrib/rpm/`, and `.github/workflows/ci.yml` currently live on
`main` (and `release/4.5.1`) and need to move to their own dedicated
branches instead.

- Raised during `paad:pushback` review of the spf-tools/route-summarization
  specs (2026-09-15) — realized only after those specs were first drafted,
  and wanted *before* that work starts, not after.
- Separate architectural decision: how those branches get built/released,
  how CI keeps running, how they stay in sync with `main` as postallow
  itself changes. Needs its own brainstorming/spec pass — not scoped yet.
- **Blocks:** `docs/superpowers/specs/2026-09-15-incorporate-spf-tools.md`
  and `docs/superpowers/specs/2026-09-15-vendor-route-summarization.md`
  both list this as a prerequisite and currently exclude
  `debian/control`, `contrib/rpm/postallow.spec`, and
  `.github/workflows/ci.yml` from their own scope until it lands.

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

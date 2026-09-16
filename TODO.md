# TODO

Tracked here until each item gets its own spec/branch. See
`docs/superpowers/specs/` for specs already written.

## 1. `postallow --check [domain]`

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
- `--quick-add` (on `main`) is the existing precedent for this kind of
  operational tooling: resolves one domain's SPF, appends the resulting
  rules to the live allowlist, and reloads Postfix. `--check` is the
  read-only counterpart — same SPF/DNS resolution, no write, no reload.
- Depends on the spf-tools incorporation landing first
  (`2026-09-15-incorporate-spf-tools.md`) — once `despf`/`despfit` are
  inline functions in `postallow` rather than an external subprocess,
  instrumenting a DNS-lookup counter for the `DNS lookups: N` line is
  straightforward; doing it against the external `despf.sh` subprocess
  would not be.
- Separate spec/plan, run 2 of 2 (per the user's split of "incorporate,
  then check").

## Done

- **Drop Debian packaging, move RPM packaging off `main`** — implemented
  2026-09-16 per
  `docs/superpowers/specs/2026-09-15-drop-debian-split-rpm-branch.md`.
  `debian/`/`build-deb.yml` deleted outright; `contrib/rpm/`/`build-rpm.yml`
  moved to the `rpm` branch; `dispatch-packaging.yml` added to `main`.
  Along the way, also consolidated the repo's two parallel trunk branches
  (`main`/`master`) down to `main` alone, now GitHub's default branch too.

# Changelog

All notable changes to Postallow are recorded here.
Entries are newest-first. Dates are YYYY-MM-DD.

---

## 4.6.0 — 2026-09-16 — Edmund Lodewijks

- Port spf-tools' `despf.sh`/`despf.inc.sh` (SPF-record expansion) and
  `normalize.sh` (CIDR normalisation) directly into `postallow`; neither is
  an external dependency anymore. Remove the now-unused `spftoolspath`
  config option.
- Vendor route-summarization's `aggregateCIDR.pl` into `contrib/` (MIT,
  Nic Boet); `make install` installs it alongside `postallow` instead of
  `contrib/install.sh` fetching it separately. Add `aggregatecidrpath`
  config option (default `/usr/local/bin`) so `postallow` resolves it by
  fixed path instead of a `PATH` search.
- Fix `aggregateCIDR.pl`'s shebang (`#!/usr/bin/perl` → `#!/usr/bin/env
  perl`) so it resolves perl via `PATH`; FreeBSD's `pkg install perl5` puts
  perl at `/usr/local/bin/perl`, not `/usr/bin/perl`, which broke CIDR
  aggregation (and therefore the whole allowlist) on FreeBSD.
- Drop Debian packaging (`debian/`, `build-deb.yml`) from `main`; Debian
  packaging is now handled directly by the maintainer, outside this repo.
  Remove the README's "via apt" install section.
- Move RPM packaging (`contrib/rpm/`, `build-rpm.yml`) off `main` onto a
  dedicated `rpm` branch. Add `dispatch-packaging.yml`: on a new `main`
  tag, rebases `rpm` onto it, syncs the spec file's version, and pushes,
  which fires the RPM build on that branch.
- Consolidate the repo's two parallel trunk branches (`main`/`master`)
  down to `main` alone, now GitHub's default branch too.
- See `MIGRATING.md` for the 4.5.x → 4.6.0 upgrade path (removing
  `spftoolspath`, cleaning up manually-installed spf-tools scripts).

## 4.5.1 — 2026-05-27 — Edmund Lodewijks

- Fix `--quick-add`: `format_ip()` was defined after the early-exit block,
  causing `format_ip: not found` at runtime.
- Fix `--quick-add`: replace misleading `echo` hint (which would append a
  second `custom_hosts=` assignment) with a plain instruction to edit the
  `custom_hosts` variable in the custom hosts file directly.
- Fix Makefile AppArmor recipe block indentation (spaces → tabs); was causing
  `missing separator` errors in deb and rpm build workflows.
- Fix CI: pass `codename` in the apt dispatch payload; `reprepro` was failing
  with `Cannot find definition of distribution ''` and the job was silently
  passing due to `curl -s`.

## 4.5.0 — 2026-05-27 — Edmund Lodewijks

- Add `--quick-add` / `-q` option: resolve a single domain's SPF records,
  append the resulting permit rules to the live allowlist file, and reload
  Postfix in one step.  Intended for unblocking a domain immediately while
  waiting for a time-sensitive e-mail (OTP, account confirmation, etc.).
- The quick-added entries are temporary; the next full postallow run regenerates
  the allowlist from scratch.  postallow prints a ready-to-paste command to add
  the domain permanently to `custom_hosts`.
- `postfix reload` is attempted automatically; if privileges are insufficient
  the manual command is printed instead.
- man page updated: new SYNOPSIS form, OPTIONS entry with embedded WARNING
  (reload is live, root required, changes are temporary), and two new examples.

## 4.4.1 — 2026-04-13 — Edmund Lodewijks

- Add `MIGRATING.md` (replaces `UPGRADING.md`) with the Postwhite and pre-4.4
  migration path.
- Link to `MIGRATING.md` from `README.md`.

## 4.4.0 — 2026-04-13 — Edmund Lodewijks

- Delegate IPv4 CIDR normalisation to `normalize.sh` from spf-tools, run
  before aggregation with `aggregateCIDR.pl`.
- Remove internal `ip2int` / `int2ip` / `network_v4` / `normalize_ip` /
  `fix_invalid_ip` / `remove_invalid_ip` / `keep_invalid_ip` functions.
- Add `invalid_cidr` config option (`fix` / `remove`, default: `fix`).
  `fix` corrects the network address to the proper prefix (same result Postfix
  derives internally); `remove` drops the range entirely (original behaviour).
- Fix `postallow.conf` quoting consistency.

## 4.3.0 — 2026-04-11 — Edmund Lodewijks

- Split `allowlist_hosts` into a package-managed copy
  (`/usr/share/postallow/allowlist_hosts`, updated on upgrade) and a
  user-managed file (`/etc/postallow/custom_hosts`, preserved on upgrade).
- Add `custom_hosts_file` config option pointing at the user file.
- Remove `postinst` migration script; upgrade notes moved to changelog.

## 4.2.0 — 2026-04-11 — Edmund Lodewijks

- Rename `postfixpath` to `output_dir` in `postallow.conf`
  (backward-compatible: old name still accepted).
- Remove `allowlist`, `blocklist`, and `yahoo_static_hosts` from
  `postallow.conf`; values are now hardcoded defaults.
- `output_dir` stamped by `make install` for the correct platform
  (`/var/lib/postallow` Linux, `/var/db/postallow` FreeBSD/NetBSD,
  `/var/postallow` OpenBSD).
- Change `include_yahoo` default to `no`.

## 4.1.3 — 2026-04-11 — Edmund Lodewijks

- Add RPM spec file and GitHub Actions build workflow for AlmaLinux 10 / RHEL 10.

## 4.1.2 — 2026-04-04 — Edmund Lodewijks

- Harden systemd service unit with sandboxing directives.
- Rename `postallow.service` to `postallow.service.in` (template substituted
  by `make install`).
- Set `UMask=0022` in service unit for consistent output file permissions.

## 4.1.1 — 2026-04-04 — Edmund Lodewijks

- Fix service file to use `@BINDIR@` substitution; was hardcoded to
  `/usr/local/bin/postallow`, breaking systemd on Debian installs.
- Replace remaining upstream (lquidfire) URLs with `edmundlod`.

## 4.1.0 — 2026-04-01 — Edmund Lodewijks

- Initial Debian packaging (`.deb` via GitHub Actions, published to apt
  repository).
- Add AppArmor profile (`contrib/apparmor/usr.bin.postallow`).
- Add Arch Linux `PKGBUILD` and supporting sysusers/tmpfiles fragments.

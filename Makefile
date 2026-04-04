# Postallow – install / uninstall
#
# Override variables on the command line, e.g.:
#   make install PREFIX=/usr
#   make install PREFIX=/usr DESTDIR=/tmp/staging
#
# Typical packager invocations:
#   make install PREFIX=/usr SYSCONFDIR=/etc DESTDIR=%{buildroot}                 # RPM
#   make install PREFIX=/usr SYSCONFDIR=/etc DESTDIR=$(CURDIR)/debian/postallow   # Debian
#   make install PREFIX=/usr/local DESTDIR=/tmp/stage COMPRESS_MAN=no            # BSD ports
#
# NOTE: 'make install' does not create the postallow system user or the output
# directory it writes CIDR files to. For manual installs, run contrib/install.sh
# first. OS packagers should handle user creation in their pre-install hooks
# (%pre for RPM, preinst for Debian, pkg-install for BSD ports). See README.md.

PREFIX      ?= /usr/local
DESTDIR     ?=
BINDIR      ?= $(PREFIX)/bin
SYSCONFDIR  ?= $(PREFIX)/etc
DATADIR     ?= $(PREFIX)/share/postallow
MANDIR      ?= $(PREFIX)/share/man
DOCDIR      ?= $(PREFIX)/share/doc/postallow

# Init system unit directories – override if your layout differs.
# On Linux the systemd units go to the vendor preset directory (not /etc).
# On FreeBSD/NetBSD ports install rc.d scripts under PREFIX/etc/rc.d.
# On OpenBSD they go under /etc/rc.d regardless of PREFIX.
SYSTEMD_UNITDIR ?= $(PREFIX)/lib/systemd/system
RCDIR_FREEBSD   ?= $(PREFIX)/etc/rc.d
RCDIR_OPENBSD   ?= /etc/rc.d
RCDIR_NETBSD    ?= /etc/rc.d

# Man page compression.
# 'auto' (default): compress on Linux (gzip), leave uncompressed on BSDs.
#   BSD ports and pkgsrc compress man pages themselves as part of the package
#   build; pre-compressing breaks their tooling. Pass COMPRESS_MAN=no for BSD.
# Note: when cross-packaging with DESTDIR on a different host OS (e.g. building
#   a FreeBSD package on Linux CI), uname returns the BUILD machine's OS.
#   In that case, set COMPRESS_MAN explicitly rather than relying on 'auto'.
COMPRESS_MAN ?= auto
GZIP         ?= gzip
GZIP_FLAGS   ?= -9

.PHONY: install uninstall help

help:
	@echo "Targets:  install, uninstall, help"
	@echo ""
	@echo "Variables (override on the command line):"
	@printf "  %-20s script and tools                   [%s]\n" "BINDIR"          "$(BINDIR)"
	@printf "  %-20s sample config and allowlist_hosts  [%s]\n" "SYSCONFDIR"      "$(SYSCONFDIR)"
	@printf "  %-20s static data files                  [%s]\n" "DATADIR"         "$(DATADIR)"
	@printf "  %-20s man pages                          [%s]\n" "MANDIR"          "$(MANDIR)"
	@printf "  %-20s documentation                      [%s]\n" "DOCDIR"          "$(DOCDIR)"
	@printf "  %-20s systemd unit files (Linux)         [%s]\n" "SYSTEMD_UNITDIR" "$(SYSTEMD_UNITDIR)"
	@printf "  %-20s rc.d script (FreeBSD)              [%s]\n" "RCDIR_FREEBSD"   "$(RCDIR_FREEBSD)"
	@printf "  %-20s rc.d script (OpenBSD)              [%s]\n" "RCDIR_OPENBSD"   "$(RCDIR_OPENBSD)"
	@printf "  %-20s rc.d script (NetBSD)               [%s]\n" "RCDIR_NETBSD"    "$(RCDIR_NETBSD)"
	@printf "  %-20s compress man pages (auto/yes/no)   [%s]\n" "COMPRESS_MAN"    "$(COMPRESS_MAN)"
	@printf "  %-20s staged install root (packagers)    [%s]\n" "DESTDIR"         "$(DESTDIR)"
	@echo ""
	@echo "Init service units are installed automatically based on the detected"
	@echo "platform (uname -s). The service is NOT enabled automatically;"
	@echo "that is left to the administrator or package post-install hook."
	@echo ""
	@echo "See contrib/install.sh to create the postallow system user and output"
	@echo "directory before running 'make install' on a live system."

install:
	# --- script and tools ---
	install -d -m 755 $(DESTDIR)$(BINDIR)
	install -m 755 postallow $(DESTDIR)$(BINDIR)/postallow
	install -m 755 scripts/scrape_yahoo $(DESTDIR)$(BINDIR)/scrape_yahoo

	# --- static data ---
	install -d -m 755 $(DESTDIR)$(DATADIR)
	install -m 644 yahoo_static_hosts.txt $(DESTDIR)$(DATADIR)/yahoo_static_hosts.txt

	# --- sample config (do not overwrite an existing live config) ---
	install -d -m 755 $(DESTDIR)$(SYSCONFDIR)/postallow
	if [ ! -f $(DESTDIR)$(SYSCONFDIR)/postallow/postallow.conf ]; then \
		sed \
			-e 's|@BINDIR@|$(BINDIR)|g' \
			-e 's|@SYSCONFDIR@|$(SYSCONFDIR)|g' \
			-e 's|@DATADIR@|$(DATADIR)|g' \
			conf/postallow.conf.in \
			> $(DESTDIR)$(SYSCONFDIR)/postallow/postallow.conf; \
		chmod 644 $(DESTDIR)$(SYSCONFDIR)/postallow/postallow.conf; \
	fi
	if [ ! -f $(DESTDIR)$(SYSCONFDIR)/postallow/allowlist_hosts ]; then \
		install -m 644 conf/allowlist_hosts \
			$(DESTDIR)$(SYSCONFDIR)/postallow/allowlist_hosts; \
	fi

	# --- man pages ---
	install -d -m 755 $(DESTDIR)$(MANDIR)/man1
	install -m 644 man/man1/postallow.1 $(DESTDIR)$(MANDIR)/man1/postallow.1
	install -d -m 755 $(DESTDIR)$(MANDIR)/man5
	install -m 644 man/man5/postallow.conf.5 $(DESTDIR)$(MANDIR)/man5/postallow.conf.5
	@_cm="$(COMPRESS_MAN)"; \
	if [ "$$_cm" = "auto" ]; then \
		case "$$(uname -s)" in Linux) _cm=yes ;; *) _cm=no ;; esac; \
	fi; \
	if [ "$$_cm" = "yes" ]; then \
		echo "# man pages: compressing with $(GZIP)"; \
		$(GZIP) $(GZIP_FLAGS) $(DESTDIR)$(MANDIR)/man1/postallow.1; \
		$(GZIP) $(GZIP_FLAGS) $(DESTDIR)$(MANDIR)/man5/postallow.conf.5; \
	fi

	# --- documentation ---
	install -d -m 755 $(DESTDIR)$(DOCDIR)
	install -m 644 README.md  $(DESTDIR)$(DOCDIR)/README.md
	install -m 644 LICENSE.md $(DESTDIR)$(DOCDIR)/LICENSE.md
	# query_mailer_ovh is an example script for mailers without SPF records;
	# installed as documentation rather than an executable tool.
	install -m 644 scripts/query_mailer_ovh $(DESTDIR)$(DOCDIR)/query_mailer_ovh.example

	# --- AppArmor profile (Linux only) ---
	@case "$$(uname -s)" in \
	Linux) \
		echo "# apparmor"; \
		install -d -m 755 $(DESTDIR)/etc/apparmor.d; \
		install -m 644 contrib/apparmor/usr.bin.postallow \
			$(DESTDIR)/etc/apparmor.d/usr.bin.postallow; \
		echo "  installed: /etc/apparmor.d/usr.bin.postallow"; \
		;; \
	esac

	# --- init service units – platform detected at install time ---
	@case "$$(uname -s)" in \
	Linux) \
		echo "# init (systemd)"; \
		install -d -m 755 $(DESTDIR)$(SYSTEMD_UNITDIR); \
		sed -e 's|@BINDIR@|$(BINDIR)|g' \
			contrib/systemd/postallow.service.in \
			> $(DESTDIR)$(SYSTEMD_UNITDIR)/postallow.service; \
		chmod 644 $(DESTDIR)$(SYSTEMD_UNITDIR)/postallow.service; \
		install -m 644 contrib/systemd/postallow.timer \
			$(DESTDIR)$(SYSTEMD_UNITDIR)/postallow.timer; \
		echo "  installed: $(SYSTEMD_UNITDIR)/postallow.{service,timer}"; \
		echo "  Run 'systemctl daemon-reload && systemctl enable --now postallow.timer' to activate."; \
		;; \
	FreeBSD) \
		echo "# init (rc.d, FreeBSD)"; \
		install -d -m 755 $(DESTDIR)$(RCDIR_FREEBSD); \
		install -m 555 contrib/freebsd/postallow.rc \
			$(DESTDIR)$(RCDIR_FREEBSD)/postallow; \
		echo "  installed: $(RCDIR_FREEBSD)/postallow"; \
		echo "  Add 'postallow_enable=YES' to /etc/rc.conf to activate."; \
		;; \
	OpenBSD) \
		echo "# init (rc.d, OpenBSD)"; \
		install -d -m 755 $(DESTDIR)$(RCDIR_OPENBSD); \
		install -m 555 contrib/freebsd/postallow.rc \
			$(DESTDIR)$(RCDIR_OPENBSD)/postallow; \
		echo "  installed: $(RCDIR_OPENBSD)/postallow"; \
		echo "  Run 'rcctl enable postallow' to activate."; \
		;; \
	NetBSD) \
		echo "# init (rc.d, NetBSD)"; \
		install -d -m 755 $(DESTDIR)$(RCDIR_NETBSD); \
		install -m 555 contrib/freebsd/postallow.rc \
			$(DESTDIR)$(RCDIR_NETBSD)/postallow; \
		echo "  installed: $(RCDIR_NETBSD)/postallow"; \
		echo "  Add 'postallow=YES' to /etc/rc.conf to activate."; \
		;; \
	*) \
		echo "# init: unsupported platform $$(uname -s), skipping service unit install."; \
		echo "  See contrib/ for available units and README.md for instructions."; \
		;; \
	esac

uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/postallow
	rm -f  $(DESTDIR)$(BINDIR)/scrape_yahoo
	rm -f  $(DESTDIR)$(DATADIR)/yahoo_static_hosts.txt
	rm -df $(DESTDIR)$(DATADIR)
	rm -f  $(DESTDIR)$(MANDIR)/man1/postallow.1
	rm -f  $(DESTDIR)$(MANDIR)/man1/postallow.1.gz
	rm -f  $(DESTDIR)$(MANDIR)/man5/postallow.conf.5
	rm -f  $(DESTDIR)$(MANDIR)/man5/postallow.conf.5.gz
	rm -f  $(DESTDIR)$(DOCDIR)/README.md
	rm -f  $(DESTDIR)$(DOCDIR)/LICENSE.md
	rm -f  $(DESTDIR)$(DOCDIR)/query_mailer_ovh.example
	rm -df $(DESTDIR)$(DOCDIR)
	@case "$$(uname -s)" in \
	Linux) \
		rm -f $(DESTDIR)$(SYSTEMD_UNITDIR)/postallow.service; \
		rm -f $(DESTDIR)$(SYSTEMD_UNITDIR)/postallow.timer; \
		rm -f $(DESTDIR)/etc/apparmor.d/usr.bin.postallow; \
		;; \
	FreeBSD) \
		rm -f $(DESTDIR)$(RCDIR_FREEBSD)/postallow; \
		;; \
	OpenBSD) \
		rm -f $(DESTDIR)$(RCDIR_OPENBSD)/postallow; \
		;; \
	NetBSD) \
		rm -f $(DESTDIR)$(RCDIR_NETBSD)/postallow; \
		;; \
	esac
	@echo "Note: $(SYSCONFDIR)/postallow/ was not removed (may contain live config)."
	@echo "Note: disable and stop the service before uninstalling if it was enabled."

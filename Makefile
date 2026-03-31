# Postallow – install / uninstall
#
# Override variables on the command line, e.g.:
#   make install PREFIX=/usr
#   make install PREFIX=/usr DESTDIR=/tmp/staging
#
# Typical packager invocations:
#   make install PREFIX=/usr SYSCONFDIR=/etc DESTDIR=%{buildroot}              # RPM
#   make install PREFIX=/usr SYSCONFDIR=/etc DESTDIR=$(CURDIR)/debian/postallow  # Debian
#   make install PREFIX=/usr/local DESTDIR=/tmp/stage                         # BSD ports

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

# Compression tool for man pages
GZIP        ?= gzip
GZIP_FLAGS  ?= -9

.PHONY: install uninstall help

help:
	@echo "Targets:  install, uninstall, help"
	@echo ""
	@echo "Variables (override on the command line):"
	@printf "  %-20s script                             [%s]\n" "BINDIR"          "$(BINDIR)"
	@printf "  %-20s sample config and allowlist_hosts  [%s]\n" "SYSCONFDIR"      "$(SYSCONFDIR)"
	@printf "  %-20s yahoo_static_hosts.txt             [%s]\n" "DATADIR"         "$(DATADIR)"
	@printf "  %-20s man pages                          [%s]\n" "MANDIR"          "$(MANDIR)"
	@printf "  %-20s documentation                      [%s]\n" "DOCDIR"          "$(DOCDIR)"
	@printf "  %-20s systemd unit files (Linux)         [%s]\n" "SYSTEMD_UNITDIR" "$(SYSTEMD_UNITDIR)"
	@printf "  %-20s rc.d script (FreeBSD)              [%s]\n" "RCDIR_FREEBSD"   "$(RCDIR_FREEBSD)"
	@printf "  %-20s rc.d script (OpenBSD)              [%s]\n" "RCDIR_OPENBSD"   "$(RCDIR_OPENBSD)"
	@printf "  %-20s rc.d script (NetBSD)               [%s]\n" "RCDIR_NETBSD"    "$(RCDIR_NETBSD)"
	@printf "  %-20s staged install root (packagers)    [%s]\n" "DESTDIR"         "$(DESTDIR)"
	@echo ""
	@echo "Init service units are installed automatically based on the detected"
	@echo "platform (uname -s). The service is NOT enabled automatically;"
	@echo "that is left to the administrator or package post-install hook."

install:
	# script
	install -d -m 755 $(DESTDIR)$(BINDIR)
	install -m 755 postallow $(DESTDIR)$(BINDIR)/postallow

	# static data
	install -d -m 755 $(DESTDIR)$(DATADIR)
	install -m 644 yahoo_static_hosts.txt $(DESTDIR)$(DATADIR)/yahoo_static_hosts.txt

	# sample config (do not overwrite an existing live config)
	install -d -m 755 $(DESTDIR)$(SYSCONFDIR)/postallow
	if [ ! -f $(DESTDIR)$(SYSCONFDIR)/postallow/postallow.conf ]; then \
		install -m 644 conf/postallow.conf \
			$(DESTDIR)$(SYSCONFDIR)/postallow/postallow.conf; \
	fi
	if [ ! -f $(DESTDIR)$(SYSCONFDIR)/postallow/allowlist_hosts ]; then \
		install -m 644 conf/allowlist_hosts \
			$(DESTDIR)$(SYSCONFDIR)/postallow/allowlist_hosts; \
	fi

	# man pages
	install -d -m 755 $(DESTDIR)$(MANDIR)/man1
	$(GZIP) $(GZIP_FLAGS) < man/man1/postallow.1 \
		> $(DESTDIR)$(MANDIR)/man1/postallow.1.gz
	install -d -m 755 $(DESTDIR)$(MANDIR)/man5
	$(GZIP) $(GZIP_FLAGS) < man/man5/postallow.conf.5 \
		> $(DESTDIR)$(MANDIR)/man5/postallow.conf.5.gz

	# documentation
	install -d -m 755 $(DESTDIR)$(DOCDIR)
	install -m 644 README.md  $(DESTDIR)$(DOCDIR)/README.md
	install -m 644 LICENSE.md $(DESTDIR)$(DOCDIR)/LICENSE.md

	# init service units – platform detected at install time
	@case "$$(uname -s)" in \
	Linux) \
		echo "# init (systemd)"; \
		install -d -m 755 $(DESTDIR)$(SYSTEMD_UNITDIR); \
		install -m 644 contrib/systemd/postallow.service \
			$(DESTDIR)$(SYSTEMD_UNITDIR)/postallow.service; \
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
	rm -f  $(DESTDIR)$(DATADIR)/yahoo_static_hosts.txt
	rm -df $(DESTDIR)$(DATADIR)
	rm -f  $(DESTDIR)$(MANDIR)/man1/postallow.1.gz
	rm -f  $(DESTDIR)$(MANDIR)/man5/postallow.conf.5.gz
	rm -f  $(DESTDIR)$(DOCDIR)/README.md
	rm -f  $(DESTDIR)$(DOCDIR)/LICENSE.md
	rm -df $(DESTDIR)$(DOCDIR)
	rm -f  $(DESTDIR)$(SYSTEMD_UNITDIR)/postallow.service
	rm -f  $(DESTDIR)$(SYSTEMD_UNITDIR)/postallow.timer
	rm -f  $(DESTDIR)$(RCDIR_FREEBSD)/postallow
	rm -f  $(DESTDIR)$(RCDIR_OPENBSD)/postallow
	rm -f  $(DESTDIR)$(RCDIR_NETBSD)/postallow
	@echo "Note: $(SYSCONFDIR)/postallow/ was not removed (may contain live config)."
	@echo "Note: disable and stop the service before uninstalling if it was enabled."

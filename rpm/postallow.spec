%{!?pkg_version: %global pkg_version 4.3.0}

Name:           postallow
Version:        %{pkg_version}
Release:        1%{?dist}
Summary:        Postfix Postscreen allowlist and blocklist generator from SPF records
License:        MIT
URL:            https://github.com/edmundlod/postallow
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  make
BuildRequires:  systemd-rpm-macros

%{?systemd_requires}
Requires:       postfix
Requires:       spf-tools
Requires:       route-summarization
Requires(pre):  %{?suse_version:shadow}%{!?suse_version:shadow-utils}

%description
Postallow generates CIDR allowlists (and optionally blocklists) for Postfix's
Postscreen by expanding the SPF records of large, trusted mail senders such as
Google, Microsoft, and Yahoo. This allows legitimate mail from these providers
to bypass Postscreen's connection-level checks, reducing false positives.

Postallow runs as an unprivileged system user and is driven by a systemd
timer. Postfix is reloaded automatically after each successful run.

%prep
%autosetup

%build
# nothing to build — pure shell script

%install
%make_install \
    PREFIX=%{_prefix} \
    SYSCONFDIR=%{_sysconfdir} \
    COMPRESS_MAN=yes
# AppArmor is Debian/Ubuntu-specific; remove the profile on RPM-based systems
rm -rf %{buildroot}/etc/apparmor.d

%pre
getent group postallow > /dev/null || groupadd -r postallow
getent passwd postallow > /dev/null || \
    useradd -r -g postallow -d /var/lib/postallow \
            -s /sbin/nologin -c "Postallow allowlist generator" postallow
exit 0

%post
%systemd_post postallow.timer
install -d -o postallow -g postallow -m 755 /var/lib/postallow

%preun
%systemd_preun postallow.timer

%postun
%systemd_postun_with_restart postallow.timer
if [ $1 -eq 0 ]; then
    userdel postallow 2>/dev/null || true
    groupdel postallow 2>/dev/null || true
    rm -rf /var/lib/postallow
fi

%files
%{_bindir}/postallow
%{_bindir}/scrape_yahoo
%dir %{_datadir}/postallow
%{_datadir}/postallow/yahoo_static_hosts.txt
%{_datadir}/postallow/allowlist_hosts
%dir %{_sysconfdir}/postallow
%config(noreplace) %{_sysconfdir}/postallow/postallow.conf
%config(noreplace) %{_sysconfdir}/postallow/custom_hosts
%{_mandir}/man1/postallow.1.gz
%{_mandir}/man5/postallow.conf.5.gz
%{_unitdir}/postallow.service
%{_unitdir}/postallow.timer
%dir %{_docdir}/%{name}
%doc %{_docdir}/%{name}/README.md
%doc %{_docdir}/%{name}/query_mailer_ovh.example
%license %{_docdir}/%{name}/LICENSE.md

%changelog
* Sat Apr 11 2026 Edmund Lodewijks <edmund@proteamail.com> - 4.3.0-1
- Split allowlist_hosts: package-managed copy moves to /usr/share/postallow/
- User additions now live in /etc/postallow/custom_hosts (preserved on upgrade)
- Rename postfixpath to output_dir; stamp platform default via make install
- Remove allowlist, blocklist, yahoo_static_hosts from conf (hardcoded defaults)
- Change include_yahoo default to no

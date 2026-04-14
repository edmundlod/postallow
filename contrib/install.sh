#!/bin/sh
#
# Postallow install helper
# https://github.com/edmundlod/postallow
#
# Creates the postallow system user and output directory for common platforms.
# It then pulls the dependencies `spf-tools` and `route-summarization` from
# github.com and installs them with correct permissions in `/usr/local/bin`.
#
# This is a convenience script - OS packagers should handle this in their own
# package lifecycle hooks instead.
#
# Run as root.

set -e

POSTALLOW_USER="postallow"
OS="$(uname -s)"

case "${OS}" in
    Linux)
        DATADIR="/var/lib/postallow"
        if id "${POSTALLOW_USER}" >/dev/null 2>&1; then
            echo "User ${POSTALLOW_USER} already exists, skipping."
        else
            useradd --system --no-create-home --shell /usr/sbin/nologin \
                --comment "Postallow allowlist generator" "${POSTALLOW_USER}"
            echo "Created user ${POSTALLOW_USER}."
        fi
        ;;
    FreeBSD)
        DATADIR="/var/db/postallow"
        if id "${POSTALLOW_USER}" >/dev/null 2>&1; then
            echo "User ${POSTALLOW_USER} already exists, skipping."
        else
            pw useradd -n "${POSTALLOW_USER}" -d /nonexistent \
                -s /usr/sbin/nologin -w no -c "Postallow allowlist generator"
            echo "Created user ${POSTALLOW_USER}."
        fi
        ;;
    OpenBSD)
        DATADIR="/var/postallow"
        if id "${POSTALLOW_USER}" >/dev/null 2>&1; then
            echo "User ${POSTALLOW_USER} already exists, skipping."
        else
            useradd -r 1..999 -d /nonexistent -s /sbin/nologin \
                -c "Postallow allowlist generator" "${POSTALLOW_USER}"
            echo "Created user ${POSTALLOW_USER}."
        fi
        ;;
    NetBSD)
        DATADIR="/var/db/postallow"
        if id "${POSTALLOW_USER}" >/dev/null 2>&1; then
            echo "User ${POSTALLOW_USER} already exists, skipping."
        else
            useradd -r -d /nonexistent -s /sbin/nologin \
                -c "Postallow allowlist generator" "${POSTALLOW_USER}"
            echo "Created user ${POSTALLOW_USER}."
        fi
        ;;
    *)
        echo "Unsupported OS: ${OS}"
        echo "Please create a '${POSTALLOW_USER}' system user manually,"
        echo "then create a directory for the output files and set its owner."
        echo "Next, you will want to install the dependencies. See the README.md"
        echo "for further instructions."
        exit 1
        ;;
esac

if [ -d "${DATADIR}" ]; then
    echo "Directory ${DATADIR} already exists, skipping."
else
    install -d -o "${POSTALLOW_USER}" -m 755 "${DATADIR}"
    echo "Created ${DATADIR} owned by ${POSTALLOW_USER}."
fi

# Install the dependencies, `spf-tools` and `route-summarization`
# to `/usr/local/bin`

TMPDIR=$(mktemp -d)
curl -sL https://github.com/spf-tools/spf-tools/archive/refs/tags/v2.3.tar.gz \
  | tar -xz --strip-components=1 -C "$TMPDIR" --wildcards 'spf-tools-2.3/*.sh'
sudo install -m 755 "$TMPDIR"/*.sh /usr/local/bin/
rm -rf "$TMPDIR"

TMPDIR=$(mktemp -d)
curl -sL https://raw.githubusercontent.com/nabbi/route-summarization/master/aggregateCIDR.pl \
  -o "$TMPDIR/aggregateCIDR.pl"
sudo install -m 755 "$TMPDIR/aggregateCIDR.pl" /usr/local/bin/
rm -rf "$TMPDIR"

echo ""
echo "Done. Next steps:"
echo "  1. Set postfixpath=${DATADIR} in postallow.conf"
echo "  2. Update Postfix main.cf postscreen_access_list to reference ${DATADIR}"
echo "  3. Install the appropriate init service from contrib/"

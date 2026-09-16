#!/bin/sh
#
# Postallow install helper
# https://github.com/edmundlod/postallow
#
# Creates the postallow system user and output directory. Both former
# external dependencies (spf-tools, aggregateCIDR.pl) are now built into
# postallow itself or vendored and installed by 'make install'.
#
# This is a convenience script for manual installs on common platforms.
# OS packagers should handle all of this in their own package lifecycle hooks.
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

echo ""
echo "Done. Next steps:"
echo "  1. Run: make install"
echo "  2. Set output_dir=${DATADIR} in postallow.conf"
echo "  3. Update Postfix main.cf postscreen_access_list to reference ${DATADIR}"
echo "  4. Enable the appropriate init service from contrib/"

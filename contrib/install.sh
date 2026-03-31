#!/bin/sh
#
# Postallow install helper
# https://github.com/lquidfire/postallow
#
# Creates the postallow system user and output directory for common platforms.
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
echo "  1. Set postfixpath=${DATADIR} in postallow.conf"
echo "  2. Update Postfix main.cf postscreen_access_list to reference ${DATADIR}"
echo "  3. Install the appropriate init service from contrib/"

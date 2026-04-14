#!/bin/sh
#
# Postallow install helper
# https://github.com/edmundlod/postallow
#
# Creates the postallow system user and output directory, and installs the two
# required dependencies (spf-tools scripts and aggregateCIDR.pl) into /usr/local/bin/.
#
# This is a convenience script for manual installs on common platforms.
# OS packagers should handle all of this in their own package lifecycle hooks.
#
# Requires: git
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


# --- Install spf-tools ---

_install_spf=true
if command -v despf.sh >/dev/null 2>&1; then
    if [ -t 0 ]; then
        printf 'spf-tools is already installed. Reinstall to update? [y/N] '
        read -r _ans
        case "${_ans}" in
            [Yy]*) _install_spf=true ;;
            *) _install_spf=false; echo "Leaving spf-tools as-is." ;;
        esac
    else
        echo "spf-tools already installed (non-interactive run, leaving as-is)."
        _install_spf=false
    fi
fi

if [ "${_install_spf}" = true ]; then
    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git is required to install spf-tools. Please install git first." >&2
        exit 1
    fi
    _tmpdir=$(mktemp -d)
    git clone --depth=1 https://github.com/spf-tools/spf-tools "${_tmpdir}/spf-tools"
    for _f in "${_tmpdir}/spf-tools"/*.sh; do
        install -m 755 "${_f}" /usr/local/bin/
    done
    rm -rf "${_tmpdir}"
    echo "Installed spf-tools scripts to /usr/local/bin/."
fi

# --- Install aggregateCIDR.pl ---

AGGREGATE_BIN="/usr/local/bin/aggregateCIDR.pl"

_install_agg=true
if [ -f "${AGGREGATE_BIN}" ]; then
    if [ -t 0 ]; then
        printf 'aggregateCIDR.pl is already installed. Reinstall to update? [y/N] '
        read -r _ans
        case "${_ans}" in
            [Yy]*) _install_agg=true ;;
            *) _install_agg=false; echo "Leaving aggregateCIDR.pl as-is." ;;
        esac
    else
        echo "aggregateCIDR.pl already installed (non-interactive run, leaving as-is)."
        _install_agg=false
    fi
fi

if [ "${_install_agg}" = true ]; then
    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git is required to install route-summarization. Please install git first." >&2
        exit 1
    fi
    _tmpdir=$(mktemp -d)
    git clone --depth=1 \
        https://github.com/edmundlod/route-summarization "${_tmpdir}/route-summarization"
    install -m 755 "${_tmpdir}/route-summarization/aggregateCIDR.pl" "${AGGREGATE_BIN}"
    rm -rf "${_tmpdir}"
    echo "Installed aggregateCIDR.pl to ${AGGREGATE_BIN}."
fi

echo ""
echo "Done. Next steps:"
echo "  1. Run: make install"
echo "  2. Set output_dir=${DATADIR} in postallow.conf"
echo "  3. Update Postfix main.cf postscreen_access_list to reference ${DATADIR}"
echo "  4. Enable the appropriate init service from contrib/"

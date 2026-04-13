#!/bin/sh
#
# tools/set-version.sh
#
# Stamp the version from the VERSION file into all files that embed it.
# Run this from the repository root before tagging a release.
#
# Usage:
#   tools/set-version.sh [version]
#
# With no argument the version is read from VERSION.
# With an argument that version is written to VERSION first.
#
# Files updated:
#   VERSION                   (when a version argument is given)
#   postallow                 (version= and lastupdated=)
#   man/man1/postallow.1      (.TH date and version)
#   man/man5/postallow.conf.5 (.TH date and version)
#   rpm/postallow.spec        (pkg_version default)

set -e

cd "$(dirname "$0")/.."

if [ -n "$1" ]; then
    printf '%s\n' "$1" > VERSION
fi

VERSION="$(cat VERSION)"
TODAY="$(date +%Y-%m-%d)"

# postallow script
sed \
    -e "s/^version=.*/version=\"${VERSION}\"/" \
    -e "s/^lastupdated=.*/lastupdated=\"${TODAY}\"/" \
    postallow > postallow.tmp && mv postallow.tmp postallow

# man pages: replace the date and version in the .TH line
# .TH POSTALLOW 1 "date" "Postallow version" "section"
for page in man/man1/postallow.1 man/man5/postallow.conf.5; do
    sed \
        -e "s/^\(\.TH [A-Z.]* [0-9] \)\"[^\"]*\" \"Postallow [^\"]*\"/\1\"${TODAY}\" \"Postallow ${VERSION}\"/" \
        "${page}" > "${page}.tmp" && mv "${page}.tmp" "${page}"
done

# rpm spec: update pkg_version default
sed \
    -e "s/^%{!?pkg_version: %global pkg_version .*}/%{!?pkg_version: %global pkg_version ${VERSION}}/" \
    rpm/postallow.spec > rpm/postallow.spec.tmp && mv rpm/postallow.spec.tmp rpm/postallow.spec

printf 'Version set to %s (date %s)\n' "${VERSION}" "${TODAY}"
printf 'Files updated: postallow, man/man1/postallow.1, man/man5/postallow.conf.5, rpm/postallow.spec\n'

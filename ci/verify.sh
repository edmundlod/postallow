#!/bin/sh
#
# ci/verify.sh - Verify a postallow CIDR output file
#
# Usage: sh ci/verify.sh /path/to/postscreen_spf_allowlist.cidr
#
# Checks:
#   1. File exists and has at least one data line (not counting header comments)
#   2. No duplicate entries in the first column (the IP/CIDR field)
#   3. Every non-comment data line has valid IP or CIDR notation in column 1
#
# Exits 0 on success, non-zero on the first failed check.
 
set -e
 
CIDR_FILE="${1?Usage: $0 /path/to/file.cidr}"
 
printf 'Verifying: %s\n' "$CIDR_FILE"
 
# ---- 1. File exists and has data -----------------------------------------
 
if [ ! -f "$CIDR_FILE" ]; then
    printf 'FAIL: file not found: %s\n' "$CIDR_FILE" >&2
    exit 1
fi
 
# Count non-comment, non-blank lines
data_lines=$(grep -cv '^\(#\|[[:space:]]*$\)' "$CIDR_FILE" || true)
 
if [ "$data_lines" -eq 0 ]; then
    printf 'FAIL: file contains no data lines (only comments/blanks)\n' >&2
    exit 1
fi
 
printf 'PASS: file exists with %d data lines\n' "$data_lines"
 
# ---- 2. No duplicate IP/CIDR entries in column 1 -------------------------
 
dupes=$(grep -v '^\(#\|[[:space:]]*$\)' "$CIDR_FILE" \
    | awk 'NF > 0 { print $1 }' \
    | sort | uniq -d)
 
if [ -n "$dupes" ]; then
    printf 'FAIL: duplicate entries found:\n' >&2
    printf '%s\n' "$dupes" >&2
    exit 1
fi
 
printf 'PASS: no duplicate entries\n'
 
# ---- 3. Valid IP / CIDR notation in every data line ----------------------
#
# The postallow output format for each data line is:
#   IP_OR_CIDR<TAB>permit
#
# Accepted forms for column 1:
#   IPv4 host:  1.2.3.4              (no /32 — script strips those)
#   IPv4 CIDR:  1.2.3.0/8 .. /32
#   IPv6 CIDR:  2607:f8b0::/32  (any hex:colon form with /prefix)
#
# We use Perl for the regex because POSIX ERE has no hex character class
# and IPv6 patterns are complex.
 
invalid=$(grep -v '^\(#\|[[:space:]]*$\)' "$CIDR_FILE" \
    | awk 'NF > 0 { print $1 }' \
    | perl -ne '
        chomp;
        unless (
            # bare IPv4 host (no prefix — postallow strips /32)
            m{^(\d{1,3}\.){3}\d{1,3}$} ||
            # IPv4 CIDR  0.0.0.0/0 .. 255.255.255.255/32
            m{^(\d{1,3}\.){3}\d{1,3}/([0-9]|[12]\d|3[012])$} ||
            # IPv6 with mandatory prefix length
            m{^[0-9a-fA-F:]+:[0-9a-fA-F]*/\d{1,3}$} ||
            # IPv6 ::/0 style (starts with ::)
            m{^::/\d{1,3}$}
        ) { print "$_\n" }
    ')
 
if [ -n "$invalid" ]; then
    printf 'FAIL: invalid IP/CIDR entries:\n' >&2
    printf '%s\n' "$invalid" >&2
    exit 1
fi
 
printf 'PASS: all %d entries are valid IP/CIDR notation\n' "$data_lines"
 
printf 'All checks passed.\n'


# Incorporate spf-tools into postallow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove postallow's runtime dependency on the external spf-tools project by porting `despf.sh`'s SPF-parsing/recursion/DNS-querying logic and `normalize.sh`'s CIDR-normalisation logic directly into the `postallow` script itself.

**Architecture:** `postallow` is a single POSIX `/bin/sh` script. The ported code becomes a new block of shell functions inserted directly into that file (no new files, no sourced lib — matches the project's existing single-script convention). All four current external-script call sites get rewired to call the new local functions. `spftoolspath` and everything that provisions/references it (config, Makefile, man page, installer, AppArmor profile, docs) is removed.

**Tech Stack:** POSIX `/bin/sh`, `make`/`sed` for install-time templating, `gzip`-compressed man pages.

**Spec:** `docs/superpowers/specs/2026-09-15-incorporate-spf-tools.md`

## Global Constraints

- Every ported function body must be a **straight copy** of the upstream spf-tools source (Apache-2.0), not a rewrite — behavior parity is the whole point of "port, not reimplement." Only namespacing/integration glue is original code.
- `postallow`'s pre-existing `cleanup()` must be renamed to `cleanup_tmpfiles()` **before** the ported block (which defines its own `cleanup()`) is added — never let both exist under the same name at once, even transiently across commits.
- `query_yahoo_host()`'s `DNS_SERVER=ns1.yahoo.com` override must be scoped to that one call only (subshell), never leaking into the other three call sites.
- No behavior change to anything not explicitly listed above — this is a dependency removal, not a feature change.
- `sh -n postallow` must pass after every task that touches the file.

---

### Task 1: Apache-2.0 attribution artifacts

**Files:**
- Create: `LICENSES/Apache-2.0.txt`
- Modify: `LICENSE.md`

**Interfaces:** None — this task only adds files/text, no code.

- [ ] **Step 1: Add the full Apache-2.0 license text**

Create `LICENSES/Apache-2.0.txt` with the standard Apache License, Version 2.0 text (fetch the canonical text from `https://www.apache.org/licenses/LICENSE-2.0.txt` — it is long and must be reproduced verbatim, not summarized).

- [ ] **Step 2: Add a "Third-party code" section to `LICENSE.md`**

Append to the end of `LICENSE.md`:

```markdown

---

## Third-party code

Portions of `postallow` (SPF parsing/recursion, DNS querying, and CIDR
normalisation, clearly delimited in the source) are adapted from
spf-tools, Copyright 2015 spf-tools team (see AUTHORS at
https://github.com/spf-tools/spf-tools), licensed under the Apache
License, Version 2.0. See `LICENSES/Apache-2.0.txt` for the full text.
```

- [ ] **Step 3: Commit**

```bash
git add LICENSES/Apache-2.0.txt LICENSE.md
git commit -m "docs: add Apache-2.0 attribution for incorporated spf-tools code"
```

---

### Task 2: Rename postallow's own `cleanup()` to `cleanup_tmpfiles()`

**Files:**
- Modify: `postallow:242` (function definition), `postallow:270` (call site inside temp-file creation error path), `postallow:410` (call site at end of run)

**Interfaces:**
- Produces: `cleanup_tmpfiles()` — same behavior as the old `cleanup()`, new name. Used by Task 5 (no other task references it).

- [ ] **Step 1: Rename the function definition**

In `postallow`, change:

```sh
# Remove temp files
cleanup() {
	test -e "${tmp1}" && rm "${tmp1}"
```

to:

```sh
# Remove temp files
cleanup_tmpfiles() {
	test -e "${tmp1}" && rm "${tmp1}"
```

(leave the rest of the function body at lines 243–255 unchanged).

- [ ] **Step 2: Update both call sites**

At `postallow:270` (inside the temp-file-creation loop's error path):

```sh
			cleanup
```
→
```sh
			cleanup_tmpfiles
```

At `postallow:410` (end of script):

```sh
cleanup
```
→
```sh
cleanup_tmpfiles
```

- [ ] **Step 3: Verify**

```bash
sh -n postallow && echo OK
grep -n '\bcleanup\b' postallow   # should show ONLY the two renamed call sites are gone;
                                  # no bare "cleanup" left anywhere yet (the ported
                                  # despf cleanup() doesn't exist until Task 3)
```
Expected: `sh -n` prints nothing but "OK"; the `grep` finds no matches at all (both call sites now say `cleanup_tmpfiles`, and the function itself is defined as `cleanup_tmpfiles`).

- [ ] **Step 4: Commit**

```bash
git add postallow
git commit -m "refactor: rename postallow's cleanup() to cleanup_tmpfiles()

Frees up the name cleanup() for despf.inc.sh's loop-detection-tempfile
cleanup function, which is about to be ported in verbatim. Two
functions sharing one name would mean POSIX sh keeps only the
textually-last definition — silently breaking whichever one loses,
including a mid-run scenario where tmp1 (which accumulates SPF results
across every query_host() call) gets deleted mid-loop."
```

---

### Task 3: Port despf.inc.sh + global.inc.sh into postallow

**Files:**
- Modify: `postallow` (insert new block after the `_norm_flag` case statement, i.e. after line 135, before the `--quick-add` block that starts at line 137 — the functions must be defined before any code that can call them runs)

**Interfaces:**
- Consumes: nothing new (uses only POSIX sh builtins and `host`, `awk`, `sed`, `cut`, `grep`, `tr`, `mktemp`, `rm`, already-required tools).
- Produces:
  - `despf <domain>` — recursively resolves one domain's SPF record, prints `ip4:`/`ip6:`/`exists:`/`ptr:` lines to stdout. Requires a loop-detection file to already exist at the path in the (global) `$2`/`$myloop` argument — see `despf_run` below.
  - `despfit <hosts> <loopfile>` — same as `despf` but accepts multiple space-separated hosts and sorts/dedupes the combined output.
  - `cleanup <loopfile>` — removes the loop-detection tempfile(s) matching `<loopfile>*`. (This is the function that used to collide with postallow's own `cleanup()` — Task 2 already renamed the other one.)
  - `despf_run <domain>` — **new integration glue, not part of upstream spf-tools.** Wraps the loopfile-provisioning steps that `despf.sh`'s own wrapper script (not ported — only `despf.inc.sh`/`global.inc.sh` are) used to do before calling `despfit`. Consumed by Task 5's call-site rewiring.
  - All of `despf.inc.sh`'s other functions (`myhost`, `get_txt`, `get_mx`, `get_addr`, `get_ns`, `findns`, `printip`, `dea`, `demx`, `parsepf`, `in_list`, `has_macro`, `getem`, `getamx`, `checkval4`, `numlesseq`, `checkval6`, `expand6`) and `global.inc.sh`'s `SPFTRC` default — internal helpers, not called directly outside this block.

- [ ] **Step 1: Insert the ported block**

In `postallow`, immediately after line 135 (`esac` closing the `_norm_flag` case statement) and before line 137 (the `# ---...` comment opening the `--quick-add` block), insert:

```sh

# ---------------------------------------------------------------------------
# The following SPF-parsing/recursion and DNS-query functions (through the
# "end of ported spf-tools code" marker below) are adapted verbatim from
# spf-tools, Copyright 2015 spf-tools team (see AUTHORS at
# https://github.com/spf-tools/spf-tools), licensed under the Apache
# License, Version 2.0 (see LICENSES/Apache-2.0.txt). Changes made: none to
# the function bodies themselves; despf_run() below is new integration glue
# (not part of upstream spf-tools) replacing the loopfile-provisioning that
# despf.sh's own wrapper script used to do.
# ---------------------------------------------------------------------------

SPFTRC=${SPFTRC:-"$HOME/.spf-toolsrc"}
test -r "$SPFTRC" && . "$SPFTRC"

DNS_TIMEOUT=${DNS_TIMEOUT:-"2"}

myhost() {
  host -W "$DNS_TIMEOUT" "$@" || { host -W "$DNS_TIMEOUT" "$@" 1>&2; exit 1; }
}

get_txt() {
  myhost -t TXT "$@" | cut -d\" -f2- | sed -e 's/\" \"//g;s/\"$//'
}

get_mx() {
  myhost -t MX "$@" | awk '/mail is handled/ {print $NF}'
}

get_addr() {
  myhost -t "$@" | awk '/alias/ {print $NF} /address/ {print $NF}'
}

get_ns() {
  myhost -t NS "$@" | awk '/name server/ {print $NF}'
}

# findns <domain>
# Find an authoritative NS server for domain
findns() {
  dd="$1"; ns="";
  while test -z "$ns"
  do
    if
      ns=$(get_ns "$dd" | grep .)
    then
      break
    else
      echo "$dd" | grep -q '\.' && { dd="${dd#*.}"; unset ns; } || break
    fi
  done
  echo "$ns" | grep '^[^;]'
}

# printip <<EOF
# 1.2.3.4
# fec0::1
# EOF
# ip4:1.2.3.4
# ip6:fec0::1
printip() {
  while read line
  do
    # Dont take the + . It's default
    qualifier=$(echo $line | grep -Eio "^[~?-]")
    line=$(echo $line | sed -e 's/[\~\?\+\-]//')
    prefix=/${1:-"${line##*/}"}
    test -n "$1" || echo $line | grep -q '/' || prefix=""
    line=$(echo $line | cut -d/ -f1)
    if echo $line | grep -q ':'; then ver=6
      checkval6 $line $prefix || continue
    elif echo $line | grep -q '\.'; then ver=4
      checkval4 $line $prefix || continue
    else
      continue
    fi
    echo "${qualifier}ip${ver}:${line}${prefix}"
  done
}

# dea <hostname> <cidr> <qualifier>
# dea both.spf-tools.eu.org
# 1.2.3.4
# fec0::1
dea() {
  for TYPE in A AAAA; do
	  get_addr $TYPE $1 | while read ip ; do 
	  	addr="${3}${ip}"
	  	echo $addr | printip $2;
  	  done
  done
  true
}

# demx <domain> <cidr> <qualifier>
# Get MX record for a domain
demx() {
  mymx=$(get_mx $1)
  for name in $mymx; do dea $name "$2" $3; done
}

# parsepf <host>
parsepf() {
  host=$1
  if
    test -n "$USE_UPSTREAM"
  then
    myns=$(findns $host 2>/dev/null)
  else
    if
      test $DNS_SERVER
    then
      myns=$DNS_SERVER
    else
      #myns=$(sed -E -n 's/^nameserver[[:space:]]+([.:[:xdigit:]]]+)/\1/p' /etc/resolv.conf)
      # [ SP TAB ]
      myns=$(sed -n 's/^nameserver[ 	]//p' /etc/resolv.conf)
    fi
  fi
  for ns in $myns
  do
    get_txt $host $ns 2>/dev/null \
      | grep -Eio 'v=spf1 [^"]+' && break
  done
}

# in_list item list
# e.g _spf.google.com  salesforce.com:google.com:outlook.com
in_list() {
  test $# -eq 2 && echo $2 | grep -wq $1
}

# has_macro item
# e.g %{i}.domain.com
has_macro() {
  echo $1 | grep '%{' > /dev/null
}

# getem <includes>
# e.g. includes="include:gnu.org include:google.com"
getem() {
  myloop=$1
  shift
  echo $* | tr " " "\n" | sed '/^$/d' | cut -b 9- | while read included
  do
    if
      in_list "$included" "$DESPF_SKIP_DOMAINS"
    then
      echo "Skipping $included" 1>&2;
      echo "include:$included"
    elif
      has_macro "$included"
    then
      echo "Skipping (has macros) $included" 1>&2;
      echo "include:$included"
    else
      echo Getting $included 1>&2;
      despf $included $myloop
    fi
  done
}

# getamx host mech [mech [...]]
# e.g. host="spf-tools.eu.org"
# e.g. mech="a a:gnu.org a:google.com/24 mx:gnu.org mx:spf-tools.eu.org/24"
getamx() {
  local cidr ahost
  host=$1
  shift
  for record in $* ; do 
    cidr=$(echo $record | cut -s -d\/ -f2-)
    ahost=$(echo $record | cut -s -d: -f2-)
    if [ "x" = "x$ahost" ] ; then
      lookuphost="$host";
      mech=$(echo $record | cut -d/ -f1)
    else
      # try to catch "a/24", "a",  "a:host.tld/24" and "a:host.tld"
      mech=$(echo $record | cut -d: -f1 | cut -d/ -f1)
      if [ "x" = "x$cidr" ] ; then
        lookuphost=$ahost
      else
        lookuphost=$(echo $ahost | cut -d\/ -f1)
      fi
    fi
    qualifier=$(echo $mech | grep -Eio "^[~?+-]")
    mech=$(echo $mech | sed -e 's/[\~\?\+\-]//'| tr '[A-Z]' '[a-z]')
    if [ "$mech" = "a" ]; then
      dea $lookuphost "$cidr" $qualifier
    elif [ "$mech" = "mx" ]; then
      demx $lookuphost "$cidr" $qualifier
    fi
  done
}

# despf <domain>
despf() {
  host=$1
  myloop=$2

  # Detect loop
  echo $host | grep -qxFf $myloop && {
    #echo "Loop detected with $host!" 1>&2
    return
  }

  echo "$host" >> "${myloop}"
  myspf=$(parsepf $host | sed 's/redirect=/include:/')

  set +e
  dogetem=$(echo $myspf | grep -Eio 'include:[^[:blank:]]+') \
    && getem $myloop $dogetem
  dogetamx=$(echo $myspf | grep -Eio -w '[?~+-]?(mx|a)((/|:)[^[:blank:]]+)?')  \
    && getamx $host $dogetamx
  echo $myspf | grep -Eio '[?~+-]?ip[46]:[^[:blank:]]+' | sed -e 's/ip[46]\://' | printip
  echo $myspf | grep -Eio '([?~+-]?exists|ptr):[^[:blank:]]+'
  set -e
}

cleanup() {
  myloop=$1
  test -n "$myloop" && rm ${myloop}*
}

despfit() {
  hosts="$1"
  myloop=$2

  # Make sort(1) behave
  export LC_ALL=C
  export LANG=C
 
  outputfile=$(mktemp /tmp/despf-sort-XXXXXXX)
  for host in $hosts
  do
    despf $host $myloop
  done  > $outputfile
  if grep -E '^[?~-]' $outputfile  ; then
	  cat $outputfile
  else
	  sort -u $outputfile
  fi
  rm $outputfile
}

checkval4() {
  ip=$1
  cidr=${2#/}
  test -n "$cidr" && { numlesseq $cidr 32 || return 1; }

  D=$(echo $ip | grep -Eo '\.' | wc -l)
  test $D -eq 3 || return 1
  for i in $(echo $ip | tr '.' ' ')
  do
    numlesseq $i 255 || return 1
  done
}

numlesseq() {
  num=${1:-1}
  less=${2:-255}
  echo "$num" | tr -d '[0-9]' | grep -q '^$' || return 1
  test $num -le $less || return 1
}

checkval6() {
  myip=$(expand6 $1) || return 1
  cidr=${2#/}
  test -n "$cidr" && { numlesseq $cidr 128 || return 1; }

  for i in $(echo $myip | tr ':' ' ')
  do
    C=$(echo $i | wc -c)
    # echo prints a newline --> 5 including \n
    test $C -le 5 || return 1
    echo "$i" | tr -d '[0-9a-fA-F]' | grep -q '^$' || return 1
  done
}

expand6() {
  D=$(echo $1 | grep -Eo ':' | wc -l)
  if
    test $D -eq 7
  then
    echo $1
  elif
    test $D -le 7 && echo $1 | grep -q '::'
  then
    C=$(echo $1 | grep -Eo '::' | wc -l)
    test $C -gt 1 && return 1
    add=""
    for a in $(awk -v MYEND=$((8-$D)) 'BEGIN { for(i=1;i<=MYEND;i++) print i }')
    do
      add=${add}:0000
    done
    out=$(echo $1 | sed "s/::/${add}:/;s/^:/0000:/;s/:$/:0000/")
    out=$(echo $out | sed -E 's/:([0-9]{1})$/:000\1/')
    out=$(echo $out | sed -E 's/:([0-9]{2})$/:00\1/')
    out=$(echo $out | sed -E 's/:([0-9]{3})$/:0\1/')
    echo $out
  else
    return 1
  fi
}

# despf_run <domain> — new integration glue, not part of upstream spf-tools.
# despf.sh's own wrapper script (not ported here) used to create the
# loop-detection tempfile, seed it, call despfit, then clean up. despfit()
# requires that tempfile as an argument but doesn't create it itself, so
# something has to — this replaces despf.sh's wrapper for that one job.
despf_run() {
  _dr_loopfile="$(mktemp -q /tmp/despf-loop-XXXXXXX)" || return 1
  echo random-non-match-tdaoeinthaonetuhanotehu > "${_dr_loopfile}"
  despfit "$1" "${_dr_loopfile}"
  cleanup "${_dr_loopfile}"
}

# end of ported spf-tools code
```

- [ ] **Step 2: Verify syntax**

```bash
sh -n postallow && echo OK
```
Expected: `OK`, no errors.

- [ ] **Step 3: Verify the functions actually work in isolation**

```bash
sh -c '. ./postallow --check-syntax-only 2>/dev/null; despf_run google.com | head -5' 2>&1 || true
```

This will likely fail as written because sourcing `postallow` directly also
runs its whole config-loading/argument-parsing prologue. Instead, verify
by extracting just the new block and testing it standalone:

```bash
sed -n '/^SPFTRC=/,/^# end of ported spf-tools code/p' postallow > /tmp/despf-test.sh
sh -c '. /tmp/despf-test.sh; despf_run google.com | head -5'
```

Expected: a handful of `ip4:`/`ip6:` lines from google.com's SPF record
(exact IPs will vary — the point is real output, not an error).

- [ ] **Step 4: Commit**

```bash
git add postallow
git commit -m "feat: port spf-tools' despf.sh/despf.inc.sh into postallow

Adapted verbatim from spf-tools (Apache-2.0, see LICENSES/Apache-2.0.txt).
Adds despf_run() as new integration glue replacing despf.sh's own
loopfile-provisioning wrapper. Not yet wired to any call site — that's
the next task."
```

---

### Task 4: Port normalize.sh into postallow

**Files:**
- Modify: `postallow` (insert immediately after Task 3's inserted block, i.e. right after the `# end of ported spf-tools code` line)

**Interfaces:**
- Consumes: nothing new.
- Produces: `normalize_cidrs [-i]` — a shell function usable as a pipeline stage exactly like `normalize.sh` was (`... | normalize_cidrs -i | ...` or `... | normalize_cidrs | ...`). Consumed by Task 5's call-site rewiring.

- [ ] **Step 1: Insert the ported block**

Immediately after the `# end of ported spf-tools code` line from Task 3, insert:

```sh

# ---------------------------------------------------------------------------
# normalize_cidrs() below is adapted verbatim (as a function instead of a
# standalone script) from spf-tools' normalize.sh, Copyright 2015 spf-tools
# team (see AUTHORS at https://github.com/spf-tools/spf-tools), licensed
# under the Apache License, Version 2.0 (see LICENSES/Apache-2.0.txt).
# Changes made: wrapped in a function taking the same "-i" flag as $1
# instead of being a standalone script; no logic changes.
# ---------------------------------------------------------------------------

normalize_cidrs() {
  test "$1" = "-i" && ignore=1

  ip2int() {
    local a b c d
    echo $1 | while IFS="." read a b c d ; do
      echo $(((((((a << 8) | b) << 8) | c) << 8) | d))
    done
  }

  int2ip() {
    local ui32=$1; shift
    local ip n
    for n in 1 2 3 4; do
      ip=$((ui32 & 0xff))${ip:+.}$ip
      ui32=$((ui32 >> 8))
    done
    echo $ip
  }

  network() {
    local ia netmask
    echo $1 | while  IFS="/" read ia netmask; do
      local addr=$(ip2int $ia);
      local mask=$((0xffffffff << (32 -$netmask)));
      echo $(int2ip $((addr & mask)))/$netmask
    done
  }

  while
    read i
  do
    cidr=$(echo $i | cut -d: -f2-)
    ipver=$(echo $i | cut -d: -f1)
    if [ "x$ipver" = "xip4" ] ; then
      # check if is a CIDR
      nm=$(echo $i | cut -s -d/ -f2)
      if [ "x$nm" = "x32" ] ; then
        echo $i
      elif [ "x$nm" = "x" ] ; then
        echo $i
      else
        result="ip4:$(network $cidr)"
        test -n "$ignore" || { echo $result; continue; }
        test "$result" = "$i" && echo $i || true
      fi
    else
      echo $i
    fi
  done
}
```

- [ ] **Step 2: Verify syntax**

```bash
sh -n postallow && echo OK
```

- [ ] **Step 3: Verify the function works standalone**

```bash
printf 'ip4:192.168.1.5/24\nip4:10.0.0.1/32\nip6:2001:db8::/48\n' | \
  sh -c 'ip2int() { :; }; '"$(sed -n '/^normalize_cidrs()/,/^}/p' postallow)"'; normalize_cidrs'
```

Expected output:
```
ip4:192.168.1.0/24
ip4:10.0.0.1/32
ip6:2001:db8::/48
```
(the `/24` entry's host bits get zeroed; the `/32` and `ip6:` entries pass through unchanged, matching `invalid_cidr=fix` behavior — no `-i` flag was passed).

- [ ] **Step 4: Commit**

```bash
git add postallow
git commit -m "feat: port spf-tools' normalize.sh into postallow as normalize_cidrs()

Adapted verbatim (Apache-2.0). Not yet wired to any call site."
```

---

### Task 5: Wire up all call sites, remove external subprocess calls

**Files:**
- Modify: `postallow:158,169` (`--quick-add` block), `postallow:280,284,289` (`query_host`/`query_block_host`/`query_yahoo_host`), `postallow:362,366` (main aggregation pipeline)

**Interfaces:**
- Consumes: `despf_run` and `normalize_cidrs` from Tasks 3–4.
- Produces: nothing new — this task only rewires existing call sites.

- [ ] **Step 1: `--quick-add` block**

At `postallow:158`:
```sh
    "${spftoolspath}"/despf.sh "${quick_add_domain}" | (grep -Ei '^ip' || true) > "${qa_t1}"
```
→
```sh
    despf_run "${quick_add_domain}" | (grep -Ei '^ip' || true) > "${qa_t1}"
```

At `postallow:168-170`:
```sh
    sed '/\./s/\/32//g' "${qa_t1}" | \
        "${spftoolspath}"/normalize.sh ${_norm_flag} | \
        sort -u | ${aggregateCIDR} --quiet --spf > "${qa_t2}"
```
→
```sh
    sed '/\./s/\/32//g' "${qa_t1}" | \
        normalize_cidrs ${_norm_flag} | \
        sort -u | ${aggregateCIDR} --quiet --spf > "${qa_t2}"
```

- [ ] **Step 2: `query_host()` / `query_block_host()` / `query_yahoo_host()`**

At `postallow:279-290`, replace:
```sh
# Create host query function
query_host() {
	"${spftoolspath}"/despf.sh "$1" | (grep -Ei ^ip || true ) >> "${tmp1}"
}

query_block_host() {
	"${spftoolspath}"/despf.sh "$1" | (grep -Ei ^ip || true ) >> "${blocktmp1}"
}

# Create Yahoo query function that pulls their SPF records from their own Nameservers
query_yahoo_host() {
	"${spftoolspath}"/despf.sh -d ns1.yahoo.com "$1" | (grep -Ei ^ip || true ) >> "${tmp1}"
}
```
with:
```sh
# Create host query function
query_host() {
	despf_run "$1" | (grep -Ei ^ip || true ) >> "${tmp1}"
}

query_block_host() {
	despf_run "$1" | (grep -Ei ^ip || true ) >> "${blocktmp1}"
}

# Create Yahoo query function that pulls their SPF records from their own Nameservers.
# DNS_SERVER is scoped to this one subshell so it never affects the other
# three call sites (despf.inc.sh's parsepf() reads it directly).
query_yahoo_host() {
	( DNS_SERVER="ns1.yahoo.com"; despf_run "$1" ) | (grep -Ei ^ip || true ) >> "${tmp1}"
}
```

- [ ] **Step 3: Main aggregation pipeline**

At `postallow:359-362`, replace:
```sh
printf "\nCIDR and Host summarization...\n"
# normalize.sh fixes invalid IPv4 CIDRs (non-null host bits) before aggregation;
# aggregateCIDR.pl is from nabbi/route-summarization, packaged at edmundlod/route-summarization
sed '/\./s/\/32//g' "${tmp1}" | "${spftoolspath}"/normalize.sh ${_norm_flag} | sort -u | ${aggregateCIDR} --quiet --spf > "${tmp2}" &
```
with:
```sh
printf "\nCIDR and Host summarization...\n"
# normalize_cidrs fixes invalid IPv4 CIDRs (non-null host bits) before aggregation;
# aggregateCIDR.pl is from nabbi/route-summarization, packaged at edmundlod/route-summarization
sed '/\./s/\/32//g' "${tmp1}" | normalize_cidrs ${_norm_flag} | sort -u | ${aggregateCIDR} --quiet --spf > "${tmp2}" &
```

At `postallow:365-368`, replace:
```sh
if [ x"$enable_blocklist" = x"yes" ] ; then
        cat "${blocktmp1}" | "${spftoolspath}"/normalize.sh ${_norm_flag} | sort -u | ${aggregateCIDR} --quiet --spf > "${blocktmp2}" &
        show_dots "$!"
fi
```
with:
```sh
if [ x"$enable_blocklist" = x"yes" ] ; then
        cat "${blocktmp1}" | normalize_cidrs ${_norm_flag} | sort -u | ${aggregateCIDR} --quiet --spf > "${blocktmp2}" &
        show_dots "$!"
fi
```

- [ ] **Step 4: Confirm no external spf-tools references remain in the script**

```bash
sh -n postallow && echo OK
grep -n 'spftoolspath\|despf\.sh\|normalize\.sh' postallow
```
Expected: `OK`, then the `grep` matches **only** comment lines referencing `normalize.sh`/`despf.sh` by name for attribution purposes (e.g. the `# normalize_cidrs fixes invalid IPv4 CIDRs...` comment) — no `"${spftoolspath}"` left anywhere, no external `despf.sh`/`normalize.sh` invocations left.

- [ ] **Step 5: End-to-end smoke test**

```bash
DOMAIN=google.com
sh -c '. ./postallow' 2>&1 | head -5 || true   # this will fail (needs a real config) — see below instead:
```

Since `postallow` requires a config file to run fully, test the wired-up
functions directly instead:

```bash
sed -n '/^SPFTRC=/,/^normalize_cidrs()/p' postallow | head -n -1 > /tmp/spf-test.sh
echo 'normalize_cidrs() {' >> /tmp/spf-test.sh
sed -n '/^normalize_cidrs()/,/^}/p' postallow | tail -n +2 >> /tmp/spf-test.sh
sh -c '. /tmp/spf-test.sh
despf_run google.com | grep -Ei ^ip | sed "s|\.|.|g" | (sed "s|/32||g") | normalize_cidrs | sort -u | head -10'
```
Expected: a sorted, deduped list of `ip4:`/`ip6:` CIDR lines — real SPF
data for google.com. (`aggregateCIDR.pl` isn't invoked here since that's
untouched by this spec; this just proves the ported despf → normalize
hand-off produces sane output.)

- [ ] **Step 6: Commit**

```bash
git add postallow
git commit -m "refactor: wire up all four call sites to the ported spf-tools functions

query_host/query_block_host/query_yahoo_host, the --quick-add block, and
the main allowlist/blocklist aggregation pipeline now call despf_run/
normalize_cidrs directly instead of shelling out to \${spftoolspath}/despf.sh
and \${spftoolspath}/normalize.sh. No behavior change intended — same
functions, same logic, now in-process."
```

---

### Task 6: Remove `spftoolspath` from config, man page, and Makefile

**Files:**
- Modify: `conf/postallow.conf.in:12-13`
- Modify: `man/man5/postallow.conf.5` (two locations)
- Modify: `Makefile:39-41,85,115`

**Interfaces:** None — pure removal, no new interfaces.

- [ ] **Step 1: `conf/postallow.conf.in`**

Remove lines 12-13:
```

# Location of spf-tools
spftoolspath=@SPFTOOLSPATH@
```
(delete the two content lines and the blank line separating them from
`allowlist_hosts`/`custom_hosts_file` above — leave exactly one blank line
before the `output_dir` section that follows, matching the file's existing
spacing convention).

- [ ] **Step 2: `man/man5/postallow.conf.5`**

Remove this block (appears once, in the option-list section):
```troff
.TP
.BI spftoolspath= path
Directory containing
.BR despf.sh (1)
from the
.B spf-tools
package.
```

Remove this line from the `.SH EXAMPLE` block:
```troff
spftoolspath=/usr/bin/spf-tools
```

- [ ] **Step 3: `Makefile`**

Remove lines 39-41:
```makefile
# Override on the command line: make install SPFTOOLSPATH=/opt/spf-tools/bin
_SPFTOOLSPATH_PROBE := $(shell command -v despf.sh 2>/dev/null)
SPFTOOLSPATH ?= $(if $(_SPFTOOLSPATH_PROBE),$(shell dirname $(_SPFTOOLSPATH_PROBE)),/usr/local/bin)
```

Remove line 85 (the `help` target's line for it):
```makefile
	@printf "  %-20s spf-tools directory                 [%s]\n" "SPFTOOLSPATH"    "$(SPFTOOLSPATH)"
```

Remove `-e 's|@SPFTOOLSPATH@|$(SPFTOOLSPATH)|g' \` from the `sed` invocation at line 115 (part of the multi-line `sed -e ... conf/postallow.conf.in > ...` command that templates the installed config file).

- [ ] **Step 4: Verify**

```bash
make -n install PREFIX=/tmp/x SYSCONFDIR=/tmp/x/etc 2>&1 | grep -i spftools
```
Expected: no output (nothing left referencing SPFTOOLSPATH).

```bash
grep -rn "spftoolspath\|SPFTOOLSPATH" conf/ man/ Makefile
```
Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add conf/postallow.conf.in man/man5/postallow.conf.5 Makefile
git commit -m "build: remove spftoolspath — spf-tools is now built into postallow"
```

---

### Task 7: Remove spf-tools from the installer and AppArmor profile

**Files:**
- Modify: `contrib/install.sh:6-7,79-109`
- Modify: `contrib/apparmor/usr.bin.postallow:57-60,84,86`

**Interfaces:** None — pure removal.

- [ ] **Step 1: `contrib/install.sh` header comment**

Change:
```sh
# Creates the postallow system user and output directory, and installs the two
# required dependencies (spf-tools scripts and aggregateCIDR.pl) into /usr/local/bin/.
```
to:
```sh
# Creates the postallow system user and output directory, and installs the
# remaining external dependency (aggregateCIDR.pl) into /usr/local/bin/.
```

- [ ] **Step 2: Remove the spf-tools install block**

Delete lines 79-109 in full (the `# --- Install spf-tools ---` section, from
that comment through the blank line right before `# --- Install
aggregateCIDR.pl ---`):

```sh
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

```

- [ ] **Step 3: `contrib/apparmor/usr.bin.postallow`**

Remove lines 57-60:
```
  # --- spf-tools (despf.sh and its sourced includes) ---
  /usr/bin/spf-tools/              r,
  /usr/bin/spf-tools/**            r,
  /usr/bin/spf-tools/despf.sh     ix,

```

Update the comment at line 84 (in the "temp files" section) from:
```
  # postallow uses mktemp /tmp/postallow.XXXXXX (5 files)
  # despf.sh uses mktemp /tmp/despf-loop-XXXXXXX
```
to:
```
  # postallow uses mktemp /tmp/postallow.XXXXXX (5 files)
  # despf_run() (ported from despf.sh) uses mktemp /tmp/despf-loop-XXXXXXX
```

Leave line 86 (`/tmp/despf-loop-*                rw,`) as-is — still needed,
the same tempfile pattern is now created by postallow's own in-process
`despf_run()` instead of a separate `despf.sh` process.

Leave line 50 (`/usr/bin/host   ix,`) as-is — already grants the `host`
command access that `myhost()` needs, regardless of who calls it.

- [ ] **Step 4: Verify**

```bash
sh -n contrib/install.sh && echo OK
grep -n "spf-tools" contrib/install.sh contrib/apparmor/usr.bin.postallow
```
Expected: `OK`, then no matches from the `grep`.

- [ ] **Step 5: Commit**

```bash
git add contrib/install.sh contrib/apparmor/usr.bin.postallow
git commit -m "build: remove spf-tools from install.sh and the AppArmor profile"
```

---

### Task 8: Update user-facing docs

**Files:**
- Modify: `README.md` (Requirements, Credits, manual-install, options sections, COPR includepkgs example)
- Modify: `man/man1/postallow.1`
- Modify: `MIGRATING.md`

**Interfaces:** None — docs only.

- [ ] **Step 1: `README.md` Requirements section (~line 56-67)**

Replace:
```markdown
Postallow runs as a shell script (```/bin/sh```) and relies on scripts from the <a target="_blank"
href="https://github.com/spf-tools/spf-tools">SPF-Tools</a> project (**despf.sh**, **normalize.sh**) to help recursively query and normalise SPF records. Unless you install via `apt` or `yum`/`dnf` (see below), use `contrib/install.sh` or the manual steps in the [Manual installation](#manual-installation) section to install them, then confirm the `spftoolspath` value in `postallow.conf`.

In order to run `postallow` you will need:

* A shell
* Perl 5+
* [spf-tools](https://github.com/spf-tools/spf-tools)
* [route-summarization](https://github.com/edmundlod/route-summarization)

**Please update SPF-Tools whenever you update Postallow, as both are under continuous development, and sometimes new features of Postallow depend upon an updated version of SPF-Tools.**
```
with:
```markdown
Postallow runs as a shell script (```/bin/sh```). SPF-record parsing and DNS
querying (originally from the <a target="_blank"
href="https://github.com/spf-tools/spf-tools">spf-tools</a> project) are
built directly into `postallow` as of v4.6.0 — no external install needed.

In order to run `postallow` you will need:

* A shell
* Perl 5+
* [route-summarization](https://github.com/edmundlod/route-summarization) (for CIDR aggregation)
```

- [ ] **Step 2: `README.md` Credits section (~line 313)**

Replace:
```markdown
* Thanks to Jan Sarenik (author of <a target="_blank" href="https://github.com/jsarenik/spf-tools">SPF-Tools</a>).
```
with:
```markdown
* Thanks to Jan Sarenik and the spf-tools team (<a target="_blank" href="https://github.com/spf-tools/spf-tools">spf-tools</a>), whose SPF-parsing and DNS-query code is incorporated directly into Postallow as of v4.6.0.
```

- [ ] **Step 3: `README.md` manual-install section (~line 127,136,159-163,189)**

Remove the `git` bullet's spf-tools mention — change:
```markdown
* `git` — to fetch spf-tools and route-summarization
```
to:
```markdown
* `git` — to fetch route-summarization
```

Change the `contrib/install.sh` description:
```markdown
This creates the `postallow` system user and the output directory with correct ownership, and installs [spf-tools](https://github.com/spf-tools/spf-tools) and [aggregateCIDR.pl](https://github.com/edmundlod/route-summarization) into `/usr/local/bin/`. OS packagers should handle all of this in their own package lifecycle hooks instead.
```
to:
```markdown
This creates the `postallow` system user and the output directory with correct ownership, and installs [aggregateCIDR.pl](https://github.com/edmundlod/route-summarization) into `/usr/local/bin/`. OS packagers should handle all of this in their own package lifecycle hooks instead.
```

Remove this block entirely (the manual "Install spf-tools" instructions):
```markdown
**Install spf-tools:**

    git clone --depth=1 https://github.com/spf-tools/spf-tools /tmp/spf-tools
    for f in /tmp/spf-tools/*.sh; do install -m 755 "$f" /usr/local/bin/; done
    rm -rf /tmp/spf-tools
```

This is a numbered list (`README.md:188-190`) — removing the middle item
requires renumbering the item after it. Change:
```markdown
1. Set `output_dir` to the output directory created above
2. Verify `spftoolspath` points to your SPF-Tools installation
3. Add any custom domains to your `custom_hosts` file (e.g. `/etc/postallow/custom_hosts`)
```
to:
```markdown
1. Set `output_dir` to the output directory created above
2. Add any custom domains to your `custom_hosts` file (e.g. `/etc/postallow/custom_hosts`)
```

- [ ] **Step 4: `README.md` options section (~line 303,307)**

Change:
```markdown
Some mailers publish SPF records containing invalid CIDR ranges — network addresses with non-null host bits (e.g. `192.168.1.5/24` instead of `192.168.1.0/24`). Postallow corrects these before aggregation using `normalize.sh` from spf-tools.
```
to:
```markdown
Some mailers publish SPF records containing invalid CIDR ranges — network addresses with non-null host bits (e.g. `192.168.1.5/24` instead of `192.168.1.0/24`). Postallow corrects these before aggregation (logic originally from spf-tools' `normalize.sh`, built in as of v4.6.0).
```

Change:
```markdown
Other options in ```postallow.conf``` include changing the filenames for your allowlist & blocklist, Postfix path, and SPF-Tools path.
```
to:
```markdown
Other options in ```postallow.conf``` include changing the filenames for your allowlist & blocklist and Postfix path.
```

- [ ] **Step 5: `README.md` COPR includepkgs example (~line 107)**

Change:
```markdown
echo "includepkgs=postallow spf-tools route-summarization" \
```
to:
```markdown
echo "includepkgs=postallow route-summarization" \
```

- [ ] **Step 6: `man/man1/postallow.1`**

Remove or rework the block around lines 113-118 that documents spf-tools as
an external dependency (`.B spf-tools`, `.BR despf.sh (1)`, the
`https://github.com/spf-tools/spf-tools` reference) — read the surrounding
`.SH` section first to match its existing structure, then either delete the
spf-tools bullet/paragraph entirely or replace it with a one-line credit
matching the README's Credits wording from Step 2, whichever reads more
naturally in that section's existing style.

- [ ] **Step 7: `MIGRATING.md`**

Add a new entry (matching the file's existing per-version-range section
style) noting: `spftoolspath` is gone as of v4.6.0; spf-tools is no longer
an external dependency; anyone with a manually-installed `despf.sh`/
`normalize.sh` in `spftoolspath` can remove them (no other package
depends on them once route-summarization is incorporated separately).

- [ ] **Step 8: Verify**

```bash
grep -rn "spftoolspath\|spf-tools" README.md man/man1/postallow.1 MIGRATING.md
```
Expected: only the Credits-style attribution mentions added in Steps 2/6
remain — no instructions treating it as something to install.

- [ ] **Step 9: Commit**

```bash
git add README.md man/man1/postallow.1 MIGRATING.md
git commit -m "docs: remove spf-tools as an external dependency"
```

---

### Task 9: Final verification pass

**Files:** None modified — verification only.

- [ ] **Step 1: Full syntax check**

```bash
sh -n postallow && sh -n contrib/install.sh && echo "ALL OK"
```

- [ ] **Step 2: Repo-wide grep for stragglers**

```bash
grep -rn "spftoolspath" . --include="*" 2>/dev/null | grep -v '^\./\.git'
grep -rln "spf-tools" . --include="*" 2>/dev/null | grep -v '^\./\.git'
```
Expected: first command has zero matches. Second command's remaining hits
should only be attribution/credit text (`LICENSE.md`, `README.md`'s
Credits section, `man/man1/postallow.1`'s credit line, and the comment
headers inside `postallow` itself) — nothing operational.

- [ ] **Step 3: `make install` dry run**

```bash
make -n install PREFIX=/tmp/postallow-test SYSCONFDIR=/tmp/postallow-test/etc 2>&1 | grep -i spf
```
Expected: no output.

- [ ] **Step 4: End-to-end domain test against a real config**

Build a minimal test config and host list, then run `postallow` for real
against a domain known to have an SPF record (e.g. `google.com`):

```bash
mkdir -p /tmp/pa-test
cat > /tmp/pa-test/postallow.conf <<'EOF'
allowlist_hosts=/tmp/pa-test/allowlist_hosts
output_dir=/tmp/pa-test
include_yahoo=no
EOF
cat > /tmp/pa-test/allowlist_hosts <<'EOF'
email_hosts="google.com"
EOF
sh ./postallow /tmp/pa-test/postallow.conf
cat /tmp/pa-test/postscreen_spf_allowlist.cidr
```
Expected: the script runs to completion ("Done!"), and the output file
contains `permit` lines with real CIDR ranges for google.com's outbound
mail servers.

Then compare against the pre-Task-1 behavior using a worktree, since by
this point Tasks 1-8 are all committed (nothing left to `git stash`):

```bash
git worktree add /tmp/pa-before 568b9bf   # commit before Task 1
mkdir -p /tmp/pa-test-before
cat > /tmp/pa-test-before/postallow.conf <<'EOF'
allowlist_hosts=/tmp/pa-test-before/allowlist_hosts
output_dir=/tmp/pa-test-before
include_yahoo=no
spftoolspath=/usr/local/bin
EOF
cat > /tmp/pa-test-before/allowlist_hosts <<'EOF'
email_hosts="google.com"
EOF
sh /tmp/pa-before/postallow /tmp/pa-test-before/postallow.conf
diff /tmp/pa-test-before/postscreen_spf_allowlist.cidr /tmp/pa-test/postscreen_spf_allowlist.cidr
git worktree remove /tmp/pa-before
```
Expected: `diff` produces no output (aside from the generated header
comment's timestamp/version line, which always differs run-to-run) — the
actual CIDR rules should be identical. The "before" run requires spf-tools
already installed at `spftoolspath` on this machine (it did before this
plan's changes); if it isn't, install it first via that commit's own
`contrib/install.sh`, or skip the "before" run and just sanity-check the
"after" output's CIDR ranges by hand against known Google SPF ranges.

- [ ] **Step 5: `--quick-add` and Yahoo path**

```bash
sudo sh ./postallow --quick-add example.com 2>&1 | tail -20   # exercises despf_run + normalize_cidrs via the quick-add path
```
(Requires the config from Step 4 to already exist at a discoverable path,
and `postfix` installed for the reload step — the reload failing gracefully
with a manual-command hint is acceptable if postfix isn't present.)

Also manually verify the Yahoo DNS override still works by comparing
`query_yahoo_host`'s output before/after this plan's changes for the same
Yahoo-related domain in `allowlist_hosts`, if one is configured.

- [ ] **Step 6: Final commit (if any verification step required a fix)**

If any of the above surfaced a bug, fix it, re-run the relevant
verification step, then:

```bash
git add -A
git commit -m "fix: <describe what verification caught>"
```

If everything passed cleanly, this task requires no commit — it's purely
verification of Tasks 1-8's work.

---

## Self-Review

- **Spec coverage:** Task 1 covers the spec's "Attribution artifacts" bullet. Task 2 covers the "Name collision — must fix" requirement. Tasks 3-4 cover the "Port... verbatim" requirement. Task 5 covers "Replace all four call sites" and the "Yahoo DNS override — must preserve" requirement. Task 6 covers the "Removals" config/man/Makefile bullet. Task 7 covers the install.sh/AppArmor removal bullet. Task 8 covers the "Docs" bullet. Task 9 covers "Testing / Verification." The spec's Non-Goals (route-summarization, `--check`, version bump, Debian/RPM branch move) are correctly untouched by every task above.
- **Placeholder scan:** no TBD/TODO markers; every step has literal before/after code or an exact shell command.
- **Type consistency:** `despf_run`, `cleanup_tmpfiles`, and `normalize_cidrs` are named consistently across every task that references them (Tasks 3/4 define them, Task 5 calls them, Task 9 verifies them by name).

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-16-incorporate-spf-tools.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

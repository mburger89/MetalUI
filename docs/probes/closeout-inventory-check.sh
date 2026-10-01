#!/bin/zsh
# The "no public behaviour is unclassified" check of plan task 15 (ruling CX-A).
#
# Joins a LIVE run of docs/probes/closeout-public-api.sh (the census of every
# public/open declaration) with docs/probes/closeout-inventory-map.tsv and
# prints one line per problem. It prints NOTHING when the inventory is
# complete. Problems it reports:
#
#   UNMAPPED  a census row no M rule claims
#   NOFAMILY  an M rule naming a family no F row defines
#   CLASS     a family whose class is not A, D, M or X
#   UNUSED    a family no census row maps to
#   PROBE     a class-A family whose probe file is missing from docs/probes/
#   ARM       a class-A family whose arm id does not occur in its probe file
#   TEST      a class-A family whose test name has no `func <name>(` in Tests/
#   DLABEL    a class-D family with no divergence label
#   LIVE      a divergence label a family carries that docs/divergences.md does
#             not list as live (a row `| <label> |` in its "Live" table)
#   RULING    a family with no ruling, or a ruling id that occurs nowhere in
#             docs/superpowers/
#   NOTDEPR   a class-X member whose declaration carries no
#             @available(*, deprecated …) attribute
#   DEPR      a deprecated declaration mapped to a family that is not class X
#
# USAGE: docs/probes/closeout-inventory-check.sh [repo-root]
set -e
ROOT=${1:-${0:A:h:h:h}}
cd $ROOT
MAP=docs/probes/closeout-inventory-map.tsv
DIV=docs/divergences.md
CENSUS=$(mktemp)
trap 'rm -f $CENSUS' EXIT
zsh docs/probes/closeout-public-api.sh $ROOT > $CENSUS

# Live divergence labels: the rows of the first table under "## Live".
LIVE=$(awk '/^## /{inlive = ($0 ~ /^## Live/)} inlive && /^\| *[0-9]+ *\|/ {split($0, c, "|"); gsub(/ /, "", c[2]); print c[2]}' $DIV 2>/dev/null | sort -un | tr '\n' ' ')

awk -F'\t' -v live=" $LIVE " -v census=$CENSUS '
  function anch(re) { return "^(" re ")$" }
  BEGIN { nrules = 0 }
  FNR == 1 && FILENAME == census { phase = 2 }
  # ---- the map
  FILENAME != census {
    if ($0 ~ /^#/ || $0 ~ /^[ \t]*$/) next
    if ($1 == "F") {
      fam[$2] = 1; cls[$2] = $3; probe[$2] = $4; arm[$2] = $5; test[$2] = $6
      divs[$2] = $7; rul[$2] = $8; forder[++nf] = $2
    } else if ($1 == "M") {
      ++nrules; rt[nrules] = $2; rf[nrules] = $3; ro[nrules] = $4; rn[nrules] = $5; rd[nrules] = $6; rfam[nrules] = $7
    }
    next
  }
  # ---- the census
  {
    t = $1; split($2, fl, ":"); path = fl[1]; line = fl[2]; owner = $3; name = $5
    rel = path; sub("^Sources/" t "/", "", rel)
    if (!(path in loaded)) {
      n = 0; while ((getline l < path) > 0) src[path, ++n] = l; close(path); loaded[path] = n
    }
    # the declaration: its first line and following lines up to the one that
    # opens its body (a multi-line signature is matched as one string)
    decl = src[path, line]
    for (k = line + 1; k <= line + 6 && decl !~ /[{]/ && (path, k) in src; k++) decl = decl " " src[path, k]
    hit = ""
    for (i = 1; i <= nrules; i++) {
      if (t !~ anch(rt[i]) || rel !~ anch(rf[i]) || owner !~ anch(ro[i]) || name !~ anch(rn[i])) continue
      if (rd[i] != ".*" && decl !~ rd[i]) continue
      hit = rfam[i]; break
    }
    if (hit == "") { print "UNMAPPED\t" $2 "\t" owner "." name; next }
    if (!(hit in fam)) { print "NOFAMILY\t" hit "\t" $2; next }
    used[hit] = 1
    # the attribute block above the declaration
    blk = src[path, line]
    for (k = line - 1; k > 0; k--) {
      l = src[path, k]
      if (l ~ /^[ \t]*$/ || l ~ /[{}][ \t]*$/ || l ~ /^[ \t]*(public|open|internal|package|private|fileprivate|func|var|let|case|init)[ (]/) break
      blk = l " " blk
    }
    dep = (blk ~ /@available\(\*,[ ]*deprecated/)
    if (cls[hit] == "X" && !dep) print "NOTDEPR\t" hit "\t" $2 "\t" owner "." name
    if (cls[hit] != "X" && dep) print "DEPR\t" hit "\t" $2 "\t" owner "." name
  }
  END {
    for (j = 1; j <= nf; j++) {
      f = forder[j]
      if (cls[f] !~ /^(A|D|M|X)$/) print "CLASS\t" f "\t" cls[f]
      if (!(f in used)) print "UNUSED\t" f
      if (cls[f] == "A") print "CHECKA\t" f "\t" probe[f] "\t" arm[f] "\t" test[f]
      if (cls[f] == "D" && (divs[f] == "-" || divs[f] == "")) print "DLABEL\t" f
      if (divs[f] != "-" && divs[f] != "") {
        n = split(divs[f], d, " ")
        for (m = 1; m <= n; m++) if (index(live, " " d[m] " ") == 0) print "LIVE\t" f "\t" d[m]
      }
      if (rul[f] == "-" || rul[f] == "") print "RULING\t" f "\t(none)"
      else print "CHECKR\t" f "\t" rul[f]
    }
  }
' $MAP $CENSUS | while IFS=$'\t' read -r kind a b c d; do
  case $kind in
    CHECKA)
      if [[ ! -f docs/probes/$b ]]; then print -r -- "PROBE	$a	$b"
      elif ! grep -qE "(^|[^A-Za-z0-9])$c([^A-Za-z0-9]|\$)" docs/probes/$b; then print -r -- "ARM	$a	$b	$c"; fi
      if ! grep -rqE "func $d\(" Tests --include='*.swift' --exclude-dir=.build; then print -r -- "TEST	$a	$d"; fi ;;
    CHECKR)
      for r in ${=b}; do
        if [[ $r =~ '^[A-Z]{1,2}-[A-Z0-9]{1,3}$' ]] && ! grep -rqF -- "$r" docs/superpowers; then print -r -- "RULING	$a	$r"; fi
      done ;;
    *) print -r -- "$kind	$a	$b	$c	$d" | sed -E 's/[[:space:]]+$//' ;;
  esac
done

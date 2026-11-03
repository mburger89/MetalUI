#!/bin/zsh
# RUN WITH zsh OR EXECUTE DIRECTLY, never `bash script`: it uses zsh path
# modifiers and process substitution, fails under bash with a syntax error, and
# the empty print would look like a pass.
# The consistency check of record §05, the declared-but-inert list (ruling
# RD-E, record 196).
#
# Joins the two tables of docs/record/05-declared-but-inert.md (between the
# `<!-- record-05:public:begin/end -->` and `<!-- record-05:internal:begin/end -->`
# markers) with a LIVE run of docs/probes/closeout-public-api.sh (the census),
# docs/probes/closeout-inventory-map.tsv, docs/divergences.md, Tests/ and
# docs/superpowers/, and prints one line per problem. It prints NOTHING when the
# list is consistent. Problems it reports:
#
#   MARKER    a begin or end marker of either table is missing (or the end comes first)
#   NODECL    a public row whose target, owner and name match no census line
#   DUP       two public rows share a (target, owner, name) key
#   FAMILY    a public row whose family is not one the map's first-matching M rule
#             gives any census line of that key (an overload set may span families)
#   NOFAMILY  a public row naming a family no F row of the map defines
#   UNLINKED  a family that has a row whose behaviour column (the map's $9) does
#             not contain `record §05`
#   ORPHAN    a family whose behaviour column contains `record §05` and which has
#             no public row (a family shared by live and inert members carries the
#             token if ANY member has a row, RD-E)
#   PIN       a pin that is not `unpinned` and has no `func <pin>(` in Tests/
#   LIVE      a divergence label not in docs/divergences.md's "Live" table
#   RULING    a ruling id (^[A-Z]{1,2}-[A-Z0-9]{1,3}$) found nowhere in docs/superpowers/
#   INTERNAL  an internal row whose file is missing or whose ERE matches no line of it
#   CELLS     a row with the wrong number of cells (a `|` inside a cell breaks it)
#
# Protocol requirements are not census lines (the census lists `public`/`open`
# declarations only); they go in the internal table with the file and an ERE.
# No temp file: the census is captured in a variable and fed in by process
# substitution.
#
# USAGE: docs/probes/record-05-check.sh [repo-root]
set -e
ROOT=${1:-${0:A:h:h:h}}
cd $ROOT
MAP=docs/probes/closeout-inventory-map.tsv
DIV=docs/divergences.md
REC=docs/record/05-declared-but-inert.md
CENSUS=$(zsh docs/probes/closeout-public-api.sh $ROOT)

# Live divergence labels: the rows of the first table under "## Live".
LIVE=$(awk '/^## /{inlive = ($0 ~ /^## Live/)} inlive && /^\| *[0-9]+ *\|/ {split($0, c, "|"); gsub(/ /, "", c[2]); print c[2]}' $DIV 2>/dev/null | sort -un | tr '\n' ' ')

awk -F'\t' -v live=" $LIVE " '
  function anch(re) { return "^(" re ")$" }
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/`/, "", s); return s }
  BEGIN { nrules = 0; fileno = 0 }
  FNR == 1 { fileno++ }
  # ---- 1: the map
  fileno == 1 {
    if ($0 ~ /^#/ || $0 ~ /^[ \t]*$/) next
    if ($1 == "F") { fam[$2] = 1; behav[$2] = $9 }
    else if ($1 == "M") { ++nrules; rt[nrules] = $2; rf[nrules] = $3; ro[nrules] = $4; rn[nrules] = $5; rd[nrules] = $6; rfam[nrules] = $7 }
    next
  }
  # ---- 2: the record: the two tables between their markers
  fileno == 2 {
    if ($0 ~ /<!-- record-05:public:begin -->/) { mode = "pub"; pb = NR; hdr = 0; next }
    if ($0 ~ /<!-- record-05:public:end -->/) { if (mode == "pub") pe = NR; mode = ""; next }
    if ($0 ~ /<!-- record-05:internal:begin -->/) { mode = "int"; ib = NR; hdr = 0; next }
    if ($0 ~ /<!-- record-05:internal:end -->/) { if (mode == "int") ie = NR; mode = ""; next }
    if (mode == "" || $0 !~ /^\|/) next
    if (hdr < 2) { hdr++; next }   # the header line and the |---| line
    n = split($0, c, "|")
    if (mode == "pub") {
      if (n != 13) { print "CELLS\tpublic\t" trim(c[2]) "." trim(c[4]) "\t" (n - 2) " cells"; next }
      npub++
      pt[npub] = trim(c[2]); po[npub] = trim(c[3]); pn[npub] = trim(c[4]); pfam[npub] = trim(c[6])
      pdiv[npub] = trim(c[10]); ppin[npub] = trim(c[11]); prul[npub] = trim(c[12])
    } else {
      if (n != 8) { print "CELLS\tinternal\t" trim(c[2]) "\t" (n - 2) " cells"; next }
      nint++
      ifile[nint] = trim(c[2]); iere[nint] = c[3]; sub(/^[ \t]*`/, "", iere[nint]); sub(/`[ \t]*$/, "", iere[nint])
      ipin[nint] = trim(c[6]); irul[nint] = trim(c[7])
    }
    next
  }
  # ---- 3: the census
  {
    t = $1; split($2, fl, ":"); path = fl[1]; line = fl[2]; owner = $3; name = $5
    rel = path; sub("^Sources/" t "/", "", rel)
    if (!(path in loaded)) {
      n = 0; while ((getline l < path) > 0) src[path, ++n] = l; close(path); loaded[path] = n
    }
    decl = src[path, line]
    for (k = line + 1; k <= line + 6 && decl !~ /[{]/ && (path, k) in src; k++) decl = decl " " src[path, k]
    hit = ""
    for (i = 1; i <= nrules; i++) {
      if (t !~ anch(rt[i]) || rel !~ anch(rf[i]) || owner !~ anch(ro[i]) || name !~ anch(rn[i])) continue
      if (rd[i] != ".*" && decl !~ rd[i]) continue
      hit = rfam[i]; break
    }
    key = t SUBSEP owner SUBSEP name
    declared[key] = 1
    if (hit != "" && index(" " fams[key] " ", " " hit " ") == 0) fams[key] = fams[key] " " hit
  }
  END {
    if (!pb || !pe || pe < pb) print "MARKER\tpublic"
    if (!ib || !ie || ie < ib) print "MARKER\tinternal"
    for (i = 1; i <= npub; i++) {
      key = pt[i] SUBSEP po[i] SUBSEP pn[i]; label = pt[i] "." po[i] "." pn[i]
      if (!(key in declared)) { print "NODECL\t" label; continue }
      if (key in seen) print "DUP\t" label
      seen[key] = 1
      if (!(pfam[i] in fam)) print "NOFAMILY\t" label "\t" pfam[i]
      else if (index(" " fams[key] " ", " " pfam[i] " ") == 0) print "FAMILY\t" label "\t" pfam[i] "\tmap says:" fams[key]
      withrow[pfam[i]] = 1
      m = split(pdiv[i], d, " ")
      for (j = 1; j <= m; j++) if (d[j] != "none" && index(live, " " d[j] " ") == 0) print "LIVE\t" label "\t" d[j]
      print "CHECKP\t" label "\t" ppin[i]
      print "CHECKR\t" label "\t" prul[i]
    }
    for (f in fam) {
      has = (behav[f] ~ /record §05/)
      if ((f in withrow) && !has) print "UNLINKED\t" f
      if (has && !(f in withrow)) print "ORPHAN\t" f
    }
    for (i = 1; i <= nint; i++) {
      print "CHECKI\t" ifile[i] "\t" iere[i]
      print "CHECKP\t" ifile[i] "\t" ipin[i]
      print "CHECKR\t" ifile[i] "\t" irul[i]
    }
  }
' $MAP $REC <(print -r -- "$CENSUS") | while IFS=$'\t' read -r kind a b c d; do
  case $kind in
    CHECKP)
      for p in ${=b}; do
        [[ $p == unpinned ]] && continue
        grep -rqE "func $p\(" Tests --include='*.swift' --exclude-dir=.build || print -r -- "PIN	$a	$p"
      done ;;
    CHECKR)
      for r in ${=b}; do
        if [[ $r =~ '^[A-Z]{1,2}-[A-Z0-9]{1,3}$' ]] && ! grep -rqF -- "$r" docs/superpowers; then print -r -- "RULING	$a	$r"; fi
      done ;;
    CHECKI)
      if [[ ! -f $a ]]; then print -r -- "INTERNAL	$a	(no such file)"
      elif ! grep -qE -- "$b" $a; then print -r -- "INTERNAL	$a	$b"; fi ;;
    *) print -r -- "$kind	$a	$b	$c	$d" | sed -E 's/[[:space:]]+$//' ;;
  esac
done

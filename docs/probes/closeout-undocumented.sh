#!/bin/zsh
# Public declarations with no doc comment, for plan task 15 (ruling CX-K).
#
# Re-runs docs/probes/closeout-public-api.sh, then prints, as
# `target <TAB> file:line <TAB> owner <TAB> kind <TAB> name`, every census row
# whose line is not directly preceded (attribute lines skipped) by a `///`
# line or the end of a `/** */` block — EXCEPT protocol-requirement witnesses,
# which inherit their requirement's documentation (the name list below; see
# CX-K). The closeout's exit criterion: this prints nothing.
#
# Recorded at 1b093b8 (design session, 2026-09-30): 888 rows without the
# exemption, 592 with it.
#
# USAGE: docs/probes/closeout-undocumented.sh [repo-root]
set -e
ROOT=${1:-${0:A:h:h:h}}
cd $ROOT
EXEMPT='^(requestLayout|prepaint|paint|requestGroupLayout|prepaintGroup|paintGroup|requestProposalLayout|requestProposalGroupLayout|sizeThatFits|placeSubviews|geometry|Layout|GroupLayout|Prepaint|PrepaintState|LayoutState|GroupPrepaint|style|decoration|elementID|handlers|description|hash|rawValue|body|_recognizers|==)$'
zsh docs/probes/closeout-public-api.sh $ROOT | while IFS=$'\t' read t fl o k n; do
  [[ $n =~ $EXEMPT ]] && continue
  f=${fl%:*}; l=${fl##*:}
  if awk -v L=$l 'NR<L{a[NR]=$0} NR==L{ i=L-1; while (i>0 && a[i] ~ /^[ ]*@/) i--; exit (a[i] ~ /^[ ]*(\/\/\/|\*\/|\*)/) ? 1 : 0 }' $f; then
    print -r -- "$t	$fl	$o	$k	$n"
  fi
done

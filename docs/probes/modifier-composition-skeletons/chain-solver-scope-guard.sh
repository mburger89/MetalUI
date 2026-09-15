#!/bin/zsh
# SOLVER-WORK PROBE (not a SwiftUI probe) for ruling MC-A's lane-2 regression
# check, as revised by the lane-1 critic round (MC-P finding 3) in
# docs/superpowers/2026-09-15-modifier-composition-decisions.md.
#
# THE QUESTION. Can "the single-overload design regressed to the first design's
# overload shape" be made a DETERMINISTIC, work-counted red rather than a
# compiler time-out whose cut-off varies by run (18.6 s error vs 44.9 s success
# at 16 `Pixels`, MC-A)? `-Xfrontend -solver-scope-threshold=N` bounds the
# constraint solver's scope count per expression, and past it swiftc emits the
# same "unable to type-check this expression in reasonable time" error. A scope
# count is work, not time.
#
# WHAT IT RUNS, from chain-typecheck-timing.py's model (the real module's
# competing overloads, no MetalUI import):
#   part 1  the minimum threshold at which each whole-file model typechecks
#           (binary search), 8/16/24 integer-literal modifiers, three designs;
#   part 2  the guard's own shape, TWO modules: `Kit` = the single-overload
#           (assoc) design compiled as a module; `client-pos.swift` = a
#           24-modifier integer-literal chain on `Text` ending
#           `.background(flag ? .accent : .surface)`; `client-neg.swift` = the
#           same plus a CLIENT-SIDE `extension ModifiedElement` redeclaring
#           `padding(_: Pixels)`, `padding(_: Edges<Length>)` and `frame` returning
#           `ModifiedElement<Content>` (the first design's concrete overloads),
#           i.e. the guard's in-test negative fixture.
#
# HOW TO RUN: zsh docs/probes/modifier-composition-skeletons/chain-solver-scope-guard.sh <scratch-dir>
#
# RECORDED 2026-09-15, macOS 26.6.2, `/usr/bin/xcrun swiftc` = Apple Swift 6.4
# (swiftlang-6.4.0.33.1) and PATH `swiftc` = Apple Swift 6.3.3
# (swift-6.3.3-RELEASE). Both flags are listed by `-frontend -help-hidden` on
# both toolchains. Output, IDENTICAL under both toolchains:
#
#   part 1, minimum passing -solver-scope-threshold (whole-file model):
#     modifiers | nested (today) | assoc (chosen) | flat (first design)
#         8     |      60        |      60        |    1321
#        16     |     116        |     116        |  338601
#        24     |     172        |     172        |  (fails at the default threshold: MC-A)
#   part 2, the guard's two-module shape:
#     client-pos minimum passing threshold: 190 (both toolchains)
#     client-pos at 1000: rc=0, ~0.1 s
#     client-neg at 1000: rc=1, "client-neg.swift:3:3: error: the compiler is
#       unable to type-check this expression in reasonable time; try breaking up
#       the expression into distinct sub-expressions", ~0.1 s
#     client-neg with no minimum up to 1 000 000 (it fails at every threshold
#       searched); at 4 194 304 it errors after 12.8 s (6.4) / 16.2 s (6.3.3)
#
# WHAT IT SHOWS.
#   - The chosen design's solver work is LINEAR in chain length (7n + 4 scopes
#     for n modifiers in the model) and equal to today's nested design's; the
#     first design's is exponential (1321 at 8, 338 601 at 16).
#   - A 24-modifier guard at a threshold of 1000 separates them by more than
#     5x on the positive side (190) and by orders of magnitude on the negative,
#     deterministically, in about 0.1 s per fixture, identically on both
#     toolchains.
#   - The first design's overloads declared in a CLIENT file (the negative
#     fixture) reproduce the blow-up against a module that has only the chosen
#     design. So the guard can carry its own in-test negative (practices shape
#     15) without mutating Sources/.
#   - NOT shown: the real MetalUI module's threshold, which has more competing
#     overloads than the model. Lane 2 measures the positive fixture's minimum
#     against the real module and sets the guard's threshold from it (spec,
#     lane 2 test 6).
set -u
S=${1:?scratch dir}
HERE=${0:A:h}
mkdir -p "$S" && cd "$S"
P="$HERE/chain-typecheck-timing.py"

minpass() { # compiler file hi [includeDir]
  local lo=1 hi=$3 inc=()
  [ $# -ge 4 ] && inc=(-I $4)
  if ! ${=1} -swift-version 6 -typecheck $inc -Xfrontend -solver-scope-threshold=$hi $2 >/dev/null 2>&1; then echo ">$hi"; return; fi
  while [ $((hi-lo)) -gt 1 ]; do local mid=$(((lo+hi)/2))
    if ${=1} -swift-version 6 -typecheck $inc -Xfrontend -solver-scope-threshold=$mid $2 >/dev/null 2>&1; then hi=$mid; else lo=$mid; fi
  done; echo $hi; }

for n in 8 16 24; do for v in nested assoc flat; do python3 "$P" $v $n int > $v-$n.swift; done; done

python3 - "$P" <<'EOF'
import sys
src = open(sys.argv[1]).read()
ns = {}
exec(src.split("def chain(")[0].replace("variant, n, lit = sys.argv[1], int(sys.argv[2]), sys.argv[3]", ""), ns)
open("Kit.swift", "w").write(ns["ASSOC"] + ns["HEADER_COMMON"])
chain = 'Text("d")' + ''.join(f'.padding({i}).frame(width: {i})' for i in range(1, 13))
pos = f'import Kit\n@MainActor func probeBody(flag: Bool) -> some Element {{\n  {chain}.background(flag ? .accent : .surface)\n}}\n'
neg = pos + '''
extension ModifiedElement {
  public func padding(_ p: Pixels) -> ModifiedElement<Content> { fatalError() }
  public func padding(_ e: Edges<Length>) -> ModifiedElement<Content> { fatalError() }
  public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<Content> { fatalError() }
}
'''
open("client-pos.swift", "w").write(pos)
open("client-neg.swift", "w").write(neg)
EOF

for c in "/usr/bin/xcrun swiftc" "swiftc"; do
  echo "== $c: $(${=c} --version 2>&1 | grep -o 'Apple Swift version [^ ]*' | head -1)"
  echo "part 1"
  for n in 8 16; do for v in nested assoc flat; do echo "  n=$n $v minpass=$(minpass "$c" $v-$n.swift 1048576)"; done; done
  for v in nested assoc; do echo "  n=24 $v minpass=$(minpass "$c" $v-24.swift 1048576)"; done
  echo "part 2"
  d=kit-${${c// /-}//\//}; mkdir -p $d
  ${=c} -swift-version 6 -parse-as-library -emit-module -module-name Kit -emit-module-path $d/Kit.swiftmodule Kit.swift >/dev/null 2>&1
  echo "  client-pos minpass=$(minpass "$c" client-pos.swift 100000 $d)"
  for f in client-pos client-neg; do
    ${=c} -swift-version 6 -typecheck -I $d -Xfrontend -solver-scope-threshold=1000 $f.swift > $f.out 2>&1
    echo "  $f at 1000: rc=$? $(grep -o 'error: .*' $f.out | head -1)"
  done
done

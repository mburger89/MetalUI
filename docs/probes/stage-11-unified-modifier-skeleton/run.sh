#!/bin/zsh
# TYPE-SYSTEM PROBE (not a SwiftUI probe) for plan task 7 stage 11, ruling LR-FV
# in docs/superpowers/2026-09-17-engine-replacement-decisions.md, spec
# docs/superpowers/specs/2026-09-25-engine-stage-11-design.md §3.
#
# THE QUESTION. Can ONE generic struct, `ModifiedContent<Content, Modifier>`,
# hold both modifier vocabularies FLAT — legacy `ModifierLayer`s and proposal
# `LayoutModifier`s — with (a) the legacy chain StyledElement and never
# ProposalElement, (b) the proposal chain ProposalElement and never
# StyledElement, so `.background(token)` is unambiguous on each, (c) a legacy
# wrapper on a proposal chain absorbing the proposal layers as its innermost
# prefix, (d) the id path of every chain equal to today's (nested
# `ModifiedContent` per proposal modifier; `ModifiedElement<ModifiedContent<X>>`
# for proposal-then-legacy), and (e) the overlay a separate two-subtree type
# that works over legacy content and still enters an `HStack` over proposal
# content? Kit.swift models MetalUI's real protocol shapes (ElementGroup with
# LayerBase/_wrap, ProposalElementGroup, ProposalElement, StyledElement) with no
# MetalUI import; main.swift prints each chain's inferred type and the id each
# layer and the content is registered under.
#
# POSITIVE CONTROL. The negatives below must be REJECTED — a legacy chain in an
# HStack, a legacy base through `ModifiedContent(content:modifier:)`, a nested
# annotation of a flat proposal chain — so "compiles" is not an instrument that
# accepts everything; and the ids differ between chains of different depth.
#
# HOW TO RUN: zsh docs/probes/stage-11-unified-modifier-skeleton/run.sh <scratch-dir>
#
# RECORDED 2026-09-24, macOS 27.0 (26A428), `xcrun swiftc` = Apple Swift 6.4
# (swiftlang-6.4.0.33.1), `-swift-version 6`, Kit compiled as its own module
# (so every access is cross-module). Kit and main compile with no error; the
# only diagnostic is one `warning: constant 's' inferred to have type 'Void'`
# inside Kit's OverlayModifier (the skeleton's, not a design question).
# Output (md5 2fa710b9152c7a33633cd67eb1ff1900):
#
#   legacy chain ModifiedContent<Box, ModifierLayer>
#       Box [7, 0, 0]
#       legacy layer [7, 0] over 1
#       legacy layer [7] over 1
#   proposal chain ModifiedContent<Rect, LayoutModifier>
#       Rect [7, 0, 0, 0]
#       layout layer [7, 0, 0]
#       layout layer [7, 0]
#       layout layer [7]
#   proposal then legacy ModifiedContent<Rect, ModifierLayer>
#       Rect [7, 0, 0]
#       layout layer [7, 0]
#       legacy layer [7] over 1
#   legacy on proposal ModifiedContent<Rect, ModifierLayer>
#       Rect [7, 0, 0]
#       legacy layer [7, 0] over 1
#       legacy layer [7] over 1
#   overlay legacy OverlayModifier<Box, Box>
#       Box [7, 0]
#       Box [7, -1, 0]
#       overlay [7]
#   overlay proposal in HStack HStack<OverlayModifier<ModifiedContent<Rect, LayoutModifier>, Rect>>
#       Rect [7, 0, 0, 0]
#       layout layer [7, 0, 0]
#       Rect [7, 0, -1, 0]
#       overlay [7, 0]
#   proposal after overlay ModifiedContent<OverlayModifier<Rect, Rect>, LayoutModifier>
#       Rect [7, 0, 0]
#       Rect [7, 0, -1, 0]
#       overlay [7, 0]
#       layout layer [7]
#   stored ModifiedContent<Box, ModifierLayer>            (annotated `ModifiedElement<Box>`)
#   storedP ModifiedContent<Rect, LayoutModifier>         (annotated flat)
#   init ModifiedContent<Rect, LayoutModifier>            (`ModifiedContent(content:modifier:)`)
#   generic ModifiedContent<Box, ModifierLayer>           (`<T: StyledElement> -> ModifiedElement<T.LayerBase>`)
#   (the last four's id lines omitted here; they repeat the shapes above)
#
#   negatives (each a one-line client, `-typecheck`):
#   REJECTED: _ = HStack { Rect().padding(Pixels(1)) } :: generic struct 'HStack' requires the types 'ModifierLayer' and 'LayoutModifier' be equivalent
#   REJECTED: _ = ModifiedContent(content: Box(), modifier: .padding(1)) :: referencing initializer 'init(content:modifier:)' on 'ModifiedContent' requires that 'Box' conform to 'ProposalElementGroup'
#   COMPILES: _ = Rect().padding(Pixels(8)).opacity(0.5).id(2)       (a legacy chain over proposal content keeps StyledElement's vocabulary)
#   REJECTED: _ = Rect().padding(1).id(2) :: cannot convert value of type 'Int' to expected argument type 'Pixels'   (no StyledElement `.id` on a proposal chain; the Pixels overload is the only candidate)
#   REJECTED: _ = HStack { Box().overlay { Rect() } } :: generic struct 'HStack' requires that 'Box' conform to 'ProposalElementGroup'
#   REJECTED: let _: ModifiedContent<ModifiedContent<Rect, LayoutModifier>, LayoutModifier> = Rect().padding(1).padding(2) :: cannot assign value of type 'ModifiedContent<ModifiedContent<Rect, LayoutModifier>.ProposalBase, LayoutModifier>' (aka 'ModifiedContent<Rect, LayoutModifier>') ...
#   COMPILES: extension ModifiedElement { public func padding(_ p: Pixels) -> ModifiedElement<Content> { fatalError() } }   (a client may still extend the generic typealias)
#
# WHAT IT SHOWS. (a)-(e) hold. The id of every layer is `.child(of: outer, at: 0)`
# and the content numbers from 0 under the innermost, whatever the vocabulary;
# "proposal chain" reads exactly the ids nested `ModifiedContent`s produce, and
# "proposal then legacy" exactly `ModifiedElement<ModifiedContent<Rect>>`'s.
# One diagnostic moves: a legacy chain rejected by a proposal container now
# says "requires the types 'ModifierLayer' and 'LayoutModifier' be equivalent"
# rather than naming `ProposalElementGroup` (spec §3.6). What it does NOT show:
# solver work at MetalUI's real overload set (the module's own budget guard,
# `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget`, is the
# instrument), and anything about phases after layout.
#
# THE REJECTED DESIGNS (why this shape): SwiftUI's nesting cannot express a
# run-time layer count in one type, which `growableChain(_:adding:)` and
# `labelledChain(adding:)` rely on; a one-parameter flat type would be both
# StyledElement and (conditionally) ProposalElement, and `.background(token)`
# would be ambiguous on every proposal chain; an overlay cannot be a vocabulary
# of the flat type, because `LayerBase` has one witness and a legacy wrapper
# after an overlay would have to drop the overlay's subtree.
set -e
out=${1:?scratch dir}
here=${0:A:h}
cd $out
cp $here/Kit.swift $here/main.swift .
xcrun swiftc -swift-version 6 -module-name Kit -emit-module -emit-library Kit.swift -o libKit.dylib
xcrun swiftc -swift-version 6 -I . -L . -lKit main.swift -o main -Xlinker -rpath -Xlinker .
./main | tee out.txt
md5 -q out.txt
for snip in '_ = HStack { Rect().padding(Pixels(1)) }' \
            '_ = ModifiedContent(content: Box(), modifier: .padding(1))' \
            '_ = Rect().padding(Pixels(8)).opacity(0.5).id(2)' \
            '_ = Rect().padding(1).id(2)' \
            '_ = HStack { Box().overlay { Rect() } }' \
            'let _: ModifiedContent<ModifiedContent<Rect, LayoutModifier>, LayoutModifier> = Rect().padding(1).padding(2)'; do
  printf 'import Kit\n@MainActor func f() { %s }\n' "$snip" > neg.swift
  if xcrun swiftc -swift-version 6 -typecheck -I . neg.swift >/dev/null 2>neg.err; then echo "COMPILES: $snip"
  else echo "REJECTED: $snip :: $(grep error: neg.err | head -1 | sed 's/.*error: //')"; fi
done
printf 'import Kit\nextension ModifiedElement {\n  public func padding(_ p: Pixels) -> ModifiedElement<Content> { fatalError() }\n}\n' > ext.swift
xcrun swiftc -swift-version 6 -typecheck -I . ext.swift && echo "COMPILES: extension ModifiedElement"

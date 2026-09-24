// Stage 8 instrument (plan task 7, stage 8; ruling LR-EY item 6; record §50 §7):
// the demo's hit testing, accessibility and hover, which the fourteen-image
// comparison (docs/probes/demo-pixels/compare.sh) cannot see — it renders no
// pointer and reads no hitbox or accessibility record.
//
// HOW TO RUN. Copy this file to Tests/MetalUITests/ZZScratchStage8Dump.swift,
// then at each revision to compare:
//
//   swift build --build-system native --build-tests
//   STAGE8_DUMP=<out>.txt swift test --build-system native --skip-build \
//       --filter zzScratchStage8Dump
//
// and `diff` the two outputs. Delete the copy afterwards (it is not a suite
// test and must not change the count). It dumps, modal off and on: every
// hitbox (bounds, layer, opacity, in order); the AccessibilityTree the window
// would publish, walked from its roots (role, label, value, selected, enabled,
// focusable, actions, row count, frame, visible frame, child order — NOT ids,
// which R7's extra frame layer moves by design); and the finalized scene with
// the pointer at five positions (both counter buttons, the readout, the modal
// card, a list row).
//
// RECORDED 2026-09-24 by the stage-8 design critic round: at 85217e3 and at
// 85217e3 + docs/probes/stage-8-demo-recipe.patch the two outputs are
// IDENTICAL (91 882 241 bytes each, `diff` empty). The instrument separates:
// the scene hovered over the minus button (270, 299) and over the readout
// (370, 299, no hitbox) differ (md5 c37a1f61… vs 9b3db702…); `hovered` reads
// true at both buttons and the list row with the modal off, false at the
// readout and the stack cluster.

import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

@Test @MainActor func zzScratchStage8Dump() throws {
    var out = ""
    for modal in [false, true] {
        demoModel.showModal = modal
        var element = demoContent()
        let frame = Frame(contentSize: Size(width: Pixels(920), height: Pixels(560)), scaleFactor: 1,
                          stateTable: StateTable(), theme: Theme.forAppearance(.light),
                          collectsAccessibility: true)
        frame.render(&element)
        out += "== modal \(modal)\n"
        for h in frame.hitboxes {
            out += "hit \(h.bounds) layer \(h.layer) opaque \(h.opaque)\n"
        }
        let tree = AccessibilityTreeBuilder.build(emissions: frame.axEmissions, focused: frame.focusedElement,
                                                  hitboxes: frame.hitboxes, focusRegistry: frame.focusRegistry)
        func walk(_ id: AccessibilityNodeID, _ depth: Int) {
            guard let n = tree.nodes[id] else { out += "missing\n"; return }
            let g = tree.geometry[id]
            out += String(repeating: " ", count: depth) + "\(n.role) \(n.label ?? "-") \(n.value ?? "-") sel \(n.isSelected) en \(n.isEnabled) foc \(n.isFocusable) act \(n.actions) rows \(String(describing: n.rowCount)) f \(String(describing: g?.frame)) v \(String(describing: g?.visibleFrame))\n"
            for c in n.children { walk(c, depth + 1) }
        }
        for r in tree.roots { walk(r, 0) }
        out += "nodes \(tree.nodes.count)\n"
    }
    for modal in [false, true] {
        demoModel.showModal = modal
        for pt in [(270, 299), (470, 299), (370, 299), (400, 280), (300, 480)] {
            var element = demoContent()
            let frame = Frame(contentSize: Size(width: Pixels(920), height: Pixels(560)), scaleFactor: 1,
                              stateTable: StateTable(), theme: Theme.forAppearance(.light),
                              mousePosition: Point(x: Pixels(Float(pt.0)), y: Pixels(Float(pt.1))))
            frame.render(&element)
            out += "hover modal \(modal) \(pt) hovered \(frame.hoveredElement != nil)\n"
            out += String(describing: frame.finalizedScene()) + "\n"
        }
    }
    demoModel.showModal = false
    try out.write(toFile: ProcessInfo.processInfo.environment["STAGE8_DUMP"]!, atomically: true, encoding: .utf8)
}

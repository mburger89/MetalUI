import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
#if canImport(Darwin)
import MetalUITestSupport
#endif
import Testing

@Test(arguments: [false, true], [false, true]) @MainActor func fgProbe(focused: Bool, glide: Bool) throws {
    let fg = try fgPair(focused: focused)
    if glide { fgStartGlide(fg) }
    var lines: [String] = []
    var out = "focused=\(focused) glide=\(glide) focusedElement=\(fg.pair.on.window.focusedElement != nil)\n"
    for step in 0..<12 {
        RetainedTrace.sink = { lines.append($0) }
        fgStep(fg, step, glide: glide)
        RetainedTrace.sink = nil
        let f = fg.pair.on.frameWork.reduce(FrameWork(), +)
        out += "step \(step) frames \(fg.pair.on.frameWork.count) req \(f.elementRequests) skipped \(f.retainedSkippedRequests) grafts \(f.retainedGrafts) hits \(f.retainedHits) misses \(f.retainedMisses) redos \(f.retainedRedos) caps \(f.retainedGraftCaptures)/\(f.retainedGraftCapturesSkipped) refusals \(fg.pair.on.window.testingGraftRefusals)\n"
    }
    out += "backoff lines \(lines.filter { $0.contains("focusBackoff") }.count); paint ineligible \(Set(lines.filter { $0.contains("paint ineligible") }.map { String($0.suffix(60)) }).count)\n"
    for l in lines.filter({ $0.contains("ineligible") }).prefix(6) { out += "  \(l)\n" }
    try fg.pair.compare("probe")
    try out.write(toFile: "/private/tmp/claude-501/-Users-maxburger-Developer-MetalUI/6204b926-398d-4909-80ba-c86fcdf2e673/scratchpad/focus-graft-agent/probe-\(focused)-\(glide).txt", atomically: true, encoding: .utf8)
}

#if canImport(Darwin)
@Test(arguments: [false, true], [false, true]) @MainActor func fgAllocProbe(focused: Bool, glide: Bool) throws {
    let fg = try fgPair(focused: focused)
    if glide { fgStartGlide(fg) }
    for step in 0..<6 { fgStep(fg, step, glide: glide, retainingOnly: true) }
    var counts: [Int] = []
    for step in 6..<14 { counts.append(try #require(countAllocations { fgStep(fg, step, glide: glide, retainingOnly: true) })) }
    var out = "alloc focused=\(focused) glide=\(glide): \(counts)\n"
    if !glide {
        let drawn = fg.pair.on.framesDrawn
        let idle = try #require(countAllocations { fg.pair.on.advance(by: 5) })
        out += "idle allocations \(idle) frames \(fg.pair.on.framesDrawn - drawn)\n"
    }
    try out.write(toFile: "/private/tmp/claude-501/-Users-maxburger-Developer-MetalUI/6204b926-398d-4909-80ba-c86fcdf2e673/scratchpad/focus-graft-agent/alloc-\(focused)-\(glide).txt", atomically: true, encoding: .utf8)
}

@Test(arguments: [false, true]) @MainActor func atAllocProbe(wheel: Bool) async throws {
    let pair = try atPair(focused: false, graft: true)
    func step(_ i: Int) async {
        if wheel { pair.on.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: i.isMultiple(of: 2) ? 24 : -16) }
        else { pair.onSide.inputs.offset += 1; await rsSettle(); pair.on.window.setNeedsRedraw(); pair.on.tick() }
    }
    for i in 0..<6 { await step(i) }
    var counts: [Int] = [], works: [String] = []
    for i in 6..<14 {
        pair.on.resetFrameWork()
        var c: Int?
        if wheel { c = countAllocations { pair.on.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: i.isMultiple(of: 2) ? 24 : -16) } }
        else { pair.onSide.inputs.offset += 1; await rsSettle(); c = countAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() } }
        counts.append(try #require(c))
        let f = pair.on.frameWork.reduce(FrameWork(), +)
        works.append("req \(f.elementRequests)/skip \(f.retainedSkippedRequests)/grafts \(f.retainedGrafts)/misses \(f.retainedMisses)")
    }
    try "at wheel=\(wheel): \(counts)\n\(works)\n".write(toFile: "/private/tmp/claude-501/-Users-maxburger-Developer-MetalUI/6204b926-398d-4909-80ba-c86fcdf2e673/scratchpad/focus-graft-agent/at-\(wheel).txt", atomically: true, encoding: .utf8)
}
#endif

private struct FGHidden: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup {
        let side = self.side
        TextField("quiet", text: Binding(get: { side.inputs.text }, set: { side.inputs.text = $0 }))
            .frame(width: Pixels(200), height: Pixels(24)).allowsHitTesting(false)
    }
    static func == (l: FGHidden, r: FGHidden) -> Bool { l.side === r.side }
}

@Test(arguments: [false, true]) @MainActor func fgMoveProbe(graft: Bool) throws {
    let pair = try RPPair(size: sz(260, 140), accessibility: false, graft: graft) { side in
        VStack(spacing: 0) {
            Box().frame(width: Pixels(100), height: Pixels(20 + side.inputs.offset))
            FGHidden(side: side).equatable()
        }
    }
    for w in [pair.on, pair.off] { w.typeKey(.tab) }
    for _ in 0..<3 { pair.redraw() }
    pair.on.resetFrameWork()
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    pair.onSide.inputs.offset = 4; pair.offSide.inputs.offset = 4
    pair.redraw()
    RetainedTrace.sink = nil
    var out = "graft=\(graft) frames \(pair.on.frameWork.count)\n"
    for f in pair.on.frameWork { out += "req \(f.elementRequests) grafts \(f.retainedGrafts) hits \(f.retainedHits) misses \(f.retainedMisses) redos \(f.retainedRedos) prepaintHits \(f.retainedPrepaintHits) refused \(f.retainedTranslationRefusedReasons)\n" }
    for l in lines.prefix(12) { out += "  \(l.prefix(200))\n" }
    try out.write(toFile: "/private/tmp/claude-501/-Users-maxburger-Developer-MetalUI/6204b926-398d-4909-80ba-c86fcdf2e673/scratchpad/focus-graft-agent/move-\(graft).txt", atomically: true, encoding: .utf8)
}

import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Record 425 (`RK-AO`): the refusal trace of a paint record that cannot follow a fractional move names the gate's number, the field, its
// value and who is fractional (the entry offset, the layout origin, or a leaf's own origin). The refusal counters keep their names.

/// The trace lines of `body`, restoring the sink after.
@MainActor private func fmLines(_ body: () async throws -> Void) async rethrows -> [String] {
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    try await body()
    return lines.filter { $0.contains("paint translation refused") }
}

/// A 24-card scroller at scale 2 scrolled by the given point deltas (wheel, one frame each): 0.3 pt is 0.6 device pixels.
@MainActor private func fmScroll(_ deltas: [Float]) async throws -> (lines: [String], reasons: [String: Int]) {
    let pair = try RPPair(size: sz(320, 400), scale: 2, warm: 4, accessibility: false, graft: true) { side in
        VStack(spacing: 0) { FSShiftSideRoot(side: side, kind: .scroll) }
    }
    var reasons: [String: Int] = [:]
    let lines = await fmLines {
        for d in deltas {
            pair.on.resetFrameWork()
            for w in [pair.on, pair.off] { w.scroll(at: pt(160, 200), byDeltaX: 0, deltaY: -d) }
            await rsSettle(); pair.redraw()
            reasons.merge(pair.stepWork.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        }
    }
    return (lines, reasons)
}

/// A wheel step of 0.3 pt moves the rows by 0.6 device pixels (`fractionalTranslation`), and the step after, which moves a whole pixel from
/// a position already fractional, cannot represent the new origin (`inexactTranslation`): each line names the field and says the **entry
/// offset** is the fractional one (the layout origin did not move), and the counter keeps its name. Mutation: `describeFractionalMove`
/// returning the empty string (both this test and the next red), or the `who` choice always answering `layoutOrigin` (this one red).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the refusal counts are not its to read"))
@MainActor
func aFractionalScrollIsRefusedWithItsFieldAndWhoIsFractional() async throws {
    let (lines, reasons) = try await fmScroll([0.3, 0.5])
    let fractional = lines.filter { $0.contains("fractionalTranslation [") }
    let inexact = lines.filter { $0.contains("inexactTranslation [entry") }
    try #require(!fractional.isEmpty && !inexact.isEmpty, "both refusals occur: \(reasons)")
    for line in fractional {
        #expect(line.contains("[entry field=dy value=-0.") && line.contains("fractional=entryOffset layoutDeltaPx=(0,0) offsetDeltaPx=(0,-0.6"), "\(line)")
    }
    for line in inexact {
        #expect(line.contains("[entry field=newY value=") && line.contains("fractional=entryOffset entryOffsetPx=(0,-1.6)"), "\(line)")
    }
    #expect(reasons["fractionalTranslation", default: 0] > 0 && reasons["inexactTranslation", default: 0] > 0, "the counters keep their names: \(reasons)")
}

/// At scale 1.2 a 10 pt move of the layout origin is 12 pixels, whole, but `rect * 1.2` is no multiple of 1/16 in `Float`: the line says the
/// **layout origin** is the fractional one, not the scroll offset (there is none). Mutation: the `who` choice always answering `entryOffset`.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the refusal counts are not its to read"))
@MainActor
func anInexactLayoutOriginIsNamedAsTheLayoutOrigin() async throws {
    let pair = try RPPair(size: sz(320, 400), scale: 1.2, warm: 4, accessibility: false, graft: false) { side in
        VStack(spacing: 0) { FSShiftSideRoot(side: side, kind: .header) }
    }
    let lines = await fmLines {
        for _ in 0..<2 {
            for side in [pair.onSide, pair.offSide] { side.inputs.offset += 10 }
            await rsSettle(); pair.redraw()
        }
    }
    let inexact = lines.filter { $0.contains("inexactTranslation [entry") }
    try #require(!inexact.isEmpty, "refused as inexact")
    #expect(inexact.allSatisfy { $0.contains("fractional=layoutOrigin") }, "\(inexact.first ?? "")")
}

/// A leaf whose own origin is the fractional number is named by its kind, field, axis and value (`leaf=rect field=bounds.origin.y value=...
/// fractional=leaf`); a mask inside a group says `groupMask.`; a leaf that is exact on both ends is skipped (`nil`). Mutation: the axis loop
/// checking only `x`, or the content mask not looked at.
@Test @MainActor
func aLeafWithAFractionalOriginIsNamedByKindAndField() {
    func rect(origin: MUIPoint, mask: MUIPoint) -> CapturedPrimitive {
        let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
        let white = MUIHsla(h: 0, s: 0, l: 1, a: 1)
        let size = MUISize(width: 10, height: 10)
        let r = MUIRect(bounds: MUIBounds(origin: origin, size: size), contentMask: MUIBounds(origin: mask, size: size),
                        maskCornerRadii: square, background: white, borderColor: white, cornerRadii: square,
                        borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0)
        return CapturedPrimitive.rect(r, layer: 0, innerMask: false)
    }
    let exact = rect(origin: MUIPoint(x: 4, y: 8.5), mask: MUIPoint(x: 0, y: 0))
    #expect(Frame.firstInexact(in: exact, dx: 2, dy: 4, role: "") == nil)
    let y = Frame.firstInexact(in: rect(origin: MUIPoint(x: 4, y: 10.3), mask: MUIPoint(x: 0, y: 0)), dx: 2, dy: 4, role: "")
    #expect(y?.hasPrefix("leaf=rect field=bounds.origin.y value=10.3") == true && y?.hasSuffix("fractional=leaf") == true, "\(y ?? "nil")")
    let mask = Frame.firstInexact(in: rect(origin: MUIPoint(x: 4, y: 8), mask: MUIPoint(x: 0.3, y: 0)), dx: 2, dy: 4, role: "groupMask.")
    #expect(mask?.hasPrefix("leaf=groupMask.rect field=contentMask.origin.x value=0.3") == true, "\(mask ?? "nil")")
}

/// Off costs nothing: with nothing listening a fractional scroll builds no refusal detail, no line and no path, though the records are refused
/// (the counters move); with a sink the same steps build one detail per refusal. Mutation: the call hoisted out of `emit`'s autoclosure into a
/// local before it.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the refusal counts are not its to read"))
@MainActor
func theRefusalDetailIsBuiltOnlyWhileSomethingListens() async throws {
    let pair = try RPPair(size: sz(320, 400), scale: 2, warm: 4, accessibility: false, graft: true) { side in
        VStack(spacing: 0) { FSShiftSideRoot(side: side, kind: .scroll) }
    }
    func steps(_ deltas: [Float]) async -> Int {
        var refused = 0
        for d in deltas {
            pair.on.resetFrameWork()
            for w in [pair.on, pair.off] { w.scroll(at: pt(160, 200), byDeltaX: 0, deltaY: -d) }
            await rsSettle(); pair.redraw()
            refused += pair.stepWork.retainedTranslationRefusedReasons.values.reduce(0, +)
        }
        return refused
    }
    RetainedTrace.detailsBuilt = 0; RetainedTrace.linesBuilt = 0; RetainedTrace.pathsBuilt = 0
    let quiet = await steps([0.3, 0.5, 0.3])
    #expect(quiet > 0, "the records are refused")
    #expect(RetainedTrace.detailsBuilt == 0 && RetainedTrace.linesBuilt == 0 && RetainedTrace.pathsBuilt == 0,
            "nothing listens: \(RetainedTrace.detailsBuilt) details, \(RetainedTrace.linesBuilt) lines, \(RetainedTrace.pathsBuilt) paths")
    var listened = 0
    RetainedTrace.sink = { _ in listened += 1 }
    defer { RetainedTrace.sink = nil }
    let loud = await steps([0.5, 0.3])
    #expect(loud > 0 && RetainedTrace.detailsBuilt > 0 && RetainedTrace.detailsBuilt <= listened, "one detail per line: \(RetainedTrace.detailsBuilt), \(listened)")
}

/// The transcript fixture of record 416 (`ChromeTranscriptFixture`) streams one word a frame under a bottom anchor: its rows move by whole device
/// pixels from whole-point offsets (layout rounds to whole points, divergence 77, a fractional bottom margin included), so **none of its refusals
/// is a fractional one**: over 12 steps they are `maskStraddlesEntryClip` and `innerScope` only (record 425). A fractional offset reaches a
/// retained record only from a wheel or trackpad delta or a fractional scale, never from the stream itself. Mutation: a fractional margin
/// leaking into the offset (a `contentMargins` of 40.3 not rounded) would put `inexactTranslation` here.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the refusal counts are not its to read"))
@MainActor
func theTranscriptFixtureRefusesNoFractionalMoveWhileItStreams() async throws {
    let pair = try ctPair()
    var reasons: [String: Int] = [:]
    for _ in 0..<12 {
        for f in await ctStep(pair) { reasons.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +) }
    }
    try #require(!reasons.isEmpty, "the fixture refuses something, or the test reads nothing")
    #expect(reasons["inexactTranslation", default: 0] == 0 && reasons["fractionalTranslation", default: 0] == 0, "streaming: \(reasons)")
}

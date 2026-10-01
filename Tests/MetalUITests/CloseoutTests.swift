import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIRender
import MetalUIText
import MetalUIDemoContent
@testable import MetalUI

// Plan task 15, the closeout — lane 1 (spec
// `docs/superpowers/specs/2026-09-30-closeout-design.md` §4, rulings `CX-F`,
// `CX-B`, `CX-I`, `CX-P` in `docs/superpowers/2026-09-30-closeout-decisions.md`;
// record §66 §4). SwiftUI's answers come from `docs/probes/swiftui-closeout.swift`
// (groups O and SW) and `docs/probes/swiftui-border-clip-paint.swift` (C3, D1).

// MARK: - 1.1 / 1.2: an optional @State with a non-nil initial value (CX-F)

/// What `OptionalStateProbe` read, frame by frame.
@MainActor
private final class OptionalReads {
    var layout: [Int?] = []
    var binding: [Int?] = []
}

/// One 20×20 clickable leaf holding `@State var x: Int? = 2`. `requestLayout`
/// records what `x` and its `$x` binding read; a click writes `nil` through the
/// captured wrapper (the only way a handler can write its element's state).
private struct OptionalStateProbe: Element {
    @State var x: Int? = 2
    let reads: OptionalReads
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        MainActor.assumeIsolated {
            reads.layout.append(x)
            reads.binding.append($x.wrappedValue)
        }
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        let x = _x
        var handlers = Handlers()
        handlers.onClick = { x.wrappedValue = nil }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor
private func optionalStateWindow(_ reads: OptionalReads) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    return try makeFakeWindow(device: device, size: 100) { Column { OptionalStateProbe(reads: reads) } }
}

/// **1.1 (probe O1).** `@State var x: Int? = 2`, rendered through a real
/// `Window`, reads **2** before its first write — in `requestLayout` and through
/// its `$x` binding — on the first frame and on a second, unwritten one. SwiftUI
/// reads 2 (O1; O0's non-optional `Int = 2` the positive control). Red at
/// `1b093b8`: `StateTable.peek` cast the absent entry to `Int?` as `.some(nil)`,
/// so `?? initialValue` never ran and both read `nil` (divergence 85).
///
/// Mutation **M1a**: restore `peek`'s `storage[id]?.value as? S` → this test alone.
@Test @MainActor func anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite() throws {
    let reads = OptionalReads()
    let (window, _) = try optionalStateWindow(reads)
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(reads.layout.count == 2, "two frames, two layout reads: \(reads.layout)")
    #expect(reads.layout == [2, 2], "the initial value before any write (O1): \(reads.layout)")
    #expect(reads.binding == [2, 2], "and through $x: \(reads.binding)")
}

/// **1.2 (probe O2, the separating arm).** The same element after a click
/// writes `nil`: the next frame reads `nil`, not the initial value — a stored
/// `nil` is a value, not an absence. SwiftUI reads nil (O2). Green before and
/// after `CX-F`.
///
/// Mutation **M1b**: `peek` treats a stored `nil` as absent → this test alone.
@Test @MainActor func aNilWrittenToAnOptionalStateReadsNilNotItsInitialValue() throws {
    let reads = OptionalReads()
    let (window, platform) = try optionalStateWindow(reads)
    window.drawFrameIfNeeded()
    let hit = try #require(window.lastHitboxes.last { $0.handlers.onClick != nil }, "the probe's hitbox")
    let point = Point(x: hit.bounds.origin.x + Pixels(10), y: hit.bounds.origin.y + Pixels(10))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
    try #require(window.needsRedraw, "the click's write dirtied the window")
    window.drawFrameIfNeeded()
    try #require(reads.layout.count == 2, "\(reads.layout)")
    #expect(reads.layout.last == .some(nil), "a written nil reads nil (O2): \(reads.layout)")
    #expect(reads.binding.last == .some(nil), "and through $x: \(reads.binding)")
}

// MARK: - 1.3 / 1.4 / 1.3L / 1.4L: order-sensitive chains after a corner radius (CX-B, CX-P item 2)

@MainActor private func colour(_ token: ColorToken) -> Hsla { Theme.light[token] }

/// **1.3 (probe C3).** On the proposal path a background written **after**
/// `.cornerRadius(12)` is square: `Rectangle(40×40).cornerRadius(12)
/// .background(.accent)` paints the accent fill unrounded and unmasked (its
/// corner pixel is filled), while the rectangle inside the clip keeps the
/// 12-point mask. SwiftUI: C3's corner(1,1) reads the background's red.
///
/// Mutation **M1c**: the background layer paints inside the clip's rounded mask
/// → this test.
@Test @MainActor func aBackgroundWrittenAfterCornerRadiusIsSquare() throws {
    let rects = paintedShapes(40, 40, Rectangle(width: Pixels(40), height: Pixels(40), color: .surface)
        .cornerRadius(Pixels(12)).background(.accent))
    try #require(rects.count == 2, "the background and the rectangle: \(rects)")
    let background = try #require(rects.first { $0.background == colour(.accent) }, "\(rects)")
    let content = try #require(rects.first { $0.background == colour(.surface) }, "\(rects)")
    #expect(background.rect == [0, 0, 40, 40] && background.radii == [0, 0, 0, 0]
                && background.maskRadii == [0, 0, 0, 0],
            "C3: the background outside the clip is square, its corner filled: \(background)")
    #expect(content.maskRadii == [12, 12, 12, 12], "the control: the content inside the clip is rounded: \(content)")
}

/// **1.4 (probe D1).** `.cornerRadius(12).border(.accent, width: 4)` on the
/// proposal path draws a **square** 4-point border band over a rounded fill:
/// the band's own radii and mask radii are 0, the fill's mask is 12. SwiftUI:
/// D1's corner(1,1) and in(3,3) read the border's blue, arc(5,5) the fill.
///
/// Mutation **M1d**: the border layer inherits the clip's corner radius → this test.
@Test @MainActor func aBorderWrittenAfterCornerRadiusIsSquareOverARoundedFill() throws {
    let rects = paintedShapes(40, 40, Rectangle(width: Pixels(40), height: Pixels(40), color: .surface)
        .cornerRadius(Pixels(12)).border(.accent, width: Pixels(4)))
    try #require(rects.count == 2, "the fill and the border: \(rects)")
    let border = try #require(rects.first { $0.border == [4, 4, 4, 4] }, "\(rects)")
    let fill = try #require(rects.first { $0.background == colour(.surface) }, "\(rects)")
    #expect(border.rect == [0, 0, 40, 40] && border.radii == [0, 0, 0, 0] && border.maskRadii == [0, 0, 0, 0],
            "D1: the band is square: \(border)")
    #expect(fill.maskRadii == [12, 12, 12, 12], "D1: the fill is rounded: \(fill)")
}

/// **1.3L — the legacy answer, wrong on purpose against C3** (divergence 47,
/// amended by the closeout's Record phase). A legacy `Box`'s `cornerRadius` and
/// `background` are two fields of ONE order-insensitive `Decoration`, and the
/// legacy corner radius is paint-only: `.cornerRadius(12).background(.accent)`
/// paints one accent rect with radii 12, where SwiftUI's background written
/// after the radius is square.
///
/// Mutation **M1cL**: square the legacy background's own radii → this test.
@Test @MainActor func aLegacyBackgroundWrittenAfterCornerRadiusIsRoundedOnOneDecoration() throws {
    let rects = paintedShapes(40, 40, Box().cssWidth(Pixels(40)).cssHeight(Pixels(40))
        .cornerRadius(Pixels(12)).background(.accent))
    try #require(rects.count == 1, "one Decoration, one rect: \(rects)")
    #expect(rects[0].background == colour(.accent) && rects[0].rect == [0, 0, 40, 40], "\(rects[0])")
    #expect(rects[0].radii == [12, 12, 12, 12], "the legacy fill is rounded whatever the order: \(rects[0])")
    let reversed = paintedShapes(40, 40, Box().cssWidth(Pixels(40)).cssHeight(Pixels(40))
        .background(.accent).cornerRadius(Pixels(12)))
    #expect(reversed == rects, "order-insensitive: the other order paints the same: \(reversed)")
}

/// **1.4L — the legacy answer, wrong on purpose against D1** (divergence 49's
/// answer). `.cornerRadius(12).border(.accent, width: 4)` on a legacy `Box`
/// paints its border band — a second emission after the content (`OM-V`) —
/// with the box's radii 12, following the arc, where SwiftUI's is square.
///
/// Mutation **M1dL**: square the legacy border band → this test.
@Test @MainActor func aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc() throws {
    let rects = paintedShapes(40, 40, Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(.surface)
        .cornerRadius(Pixels(12)).border(.accent, width: Pixels(4)))
    try #require(rects.count == 2, "the fill, then the border: \(rects)")
    let border = try #require(rects.first { $0.border == [4, 4, 4, 4] }, "\(rects)")
    let fill = try #require(rects.first { $0.background == colour(.surface) }, "\(rects)")
    #expect(border.rect == [0, 0, 40, 40] && border.radii == [12, 12, 12, 12],
            "the legacy band follows the arc: \(border)")
    #expect(fill.radii == [12, 12, 12, 12], "and the fill is rounded: \(fill)")
}

// MARK: - 1.5: a `switch` branch transitions as an `if`/`else` branch does (CX-I item 2)

private enum Pane { case first, second, third }

/// Every rect painted in `token`'s light colour.
@MainActor private func painted(_ token: ColorToken, _ frame: Frame) -> [MUIRect] {
    let c = Theme.light[token]
    return frame.scene.rects.filter {
        abs($0.background.h - c.h) < 0.001 && abs($0.background.s - c.s) < 0.001 && abs($0.background.l - c.l) < 0.001
    }
}

/// The removed pane is accent, the inserted one surface; both 50×30 with
/// `.move(edge: .leading)`, in a 200×100 stage.
@MainActor private func pane(_ token: ColorToken) -> some Element {
    Box().frame(width: Pixels(50), height: Pixels(30)).background(token)
}

@MainActor private func ifElseStage(_ first: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if first { pane(.accent).transition(.move(edge: .leading)) }
            else { pane(.surface).transition(.move(edge: .leading)) }
        }
    }
}

@MainActor private func switchStage(_ which: Pane) -> some Element {
    Column {
        Stack {
            Box().frame(width: Pixels(200), height: Pixels(100))
            switch which {
            case .first: pane(.accent).transition(.move(edge: .leading))
            case .second: pane(.surface).transition(.move(edge: .leading))
            case .third: pane(.separator).transition(.move(edge: .leading))
            }
        }
    }
}

/// One branch change at 0 under `animation`: the removed (accent) pane's rest
/// origin, then at 0.5 the accent ghost's and the inserted (surface) pane's
/// x-offsets from that rest, and the accent count when landed (1.0).
@MainActor private func branchChange<E: Element>(_ before: E, _ after: E, _ animation: Animation?)
    -> (ghost: [Float], inserted: [Float], landed: Int) {
    let h = TransitionHarness()
    let rest = painted(.accent, h.frame(0, nil, before))
    guard rest.count == 1 else { return ([], [], -1) }
    let x0 = rest[0].bounds.origin.x
    h.frame(0, animation, after)
    let mid = h.frame(0.5, nil, after)
    let ghost = painted(.accent, mid).map { $0.bounds.origin.x - x0 }
    let inserted = painted(.surface, mid).map { $0.bounds.origin.x - x0 }
    let landed = painted(.accent, h.frame(1.0, nil, after)).count
    return (ghost, inserted, landed)
}

/// **1.5 (probe SW0/SW1/SW1n).** A three-case `switch` whose case content
/// carries `.transition(.move(edge: .leading))` transitions exactly as the
/// `if`/`else` arm does: a case change under `linear(1)` draws the removed
/// case's ghost 25 left half-way (−50 over the whole move) and the inserted
/// case 25 left of its place, gone when landed. Both arms in one body, required
/// to agree, and both required to differ from the no-transaction control
/// (nothing in flight). SwiftUI: SW1 records the same two offsets as SW0
/// (+50 in, −50 out); SW1n nothing.
///
/// Mutation **M1e**: the transition claim ignores the `switch`'s nested
/// `buildEither(second:)` path → this test.
@Test @MainActor func aSwitchBranchTransitionsAsAnIfElseBranchDoes() throws {
    let linear = Animation.linear(duration: 1)
    let ifElse = branchChange(ifElseStage(true), ifElseStage(false), linear)
    let switched = branchChange(switchStage(.first), switchStage(.second), linear)
    let control = branchChange(switchStage(.first), switchStage(.second), nil)
    try #require(ifElse.landed >= 0 && switched.landed >= 0 && control.landed >= 0, "each rest frame paints one accent pane")
    #expect(ifElse.ghost == [-25] && ifElse.inserted == [-25] && ifElse.landed == 0,
            "the if/else arm (SW0): ghost \(ifElse.ghost), inserted \(ifElse.inserted), landed \(ifElse.landed)")
    #expect(switched.ghost == ifElse.ghost && switched.inserted == ifElse.inserted && switched.landed == ifElse.landed,
            "the switch arm (SW1) agrees with the if/else arm: ghost \(switched.ghost), inserted \(switched.inserted)")
    #expect(control.ghost.isEmpty && control.inserted == [0],
            "the control (SW1n): no ghost, the inserted pane at its place: \(control.ghost), \(control.inserted)")
    #expect(control.ghost != switched.ghost, "the arms differ from the control")
}

// MARK: - 1.6: the settled-frame store-entry allocation figure (CX-I item 1, AN-AJ)

private typealias CloseoutMallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
private let closeoutMallocLogTypeAllocate: UInt32 = 2
nonisolated(unsafe) private var closeoutAllocations = 0
nonisolated(unsafe) private var closeoutBytes = 0
nonisolated(unsafe) private var closeoutThread: pthread_t?
nonisolated(unsafe) private var closeoutChained: CloseoutMallocLogger?
nonisolated(unsafe) private let closeoutLogger: CloseoutMallocLogger = { type, a1, a2, a3, result, skip in
    if type & closeoutMallocLogTypeAllocate != 0,
       let thread = closeoutThread, pthread_equal(thread, pthread_self()) != 0 {
        closeoutAllocations += 1
        closeoutBytes += Int(a2)
    }
    closeoutChained?(type, a1, a2, a3, result, skip)
}

/// Allocations and requested bytes `body` makes on the calling thread.
private func countCloseoutAllocations(_ body: () -> Void) throws -> (count: Int, bytes: Int) {
    let symbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger"),
                              "libmalloc no longer exports malloc_logger")
    let slot = symbol.assumingMemoryBound(to: CloseoutMallocLogger?.self)
    _ = closeoutLogger
    closeoutChained = slot.pointee
    closeoutAllocations = 0; closeoutBytes = 0
    closeoutThread = pthread_self()
    slot.pointee = closeoutLogger
    body()
    slot.pointee = closeoutChained
    closeoutThread = nil
    return (closeoutAllocations, closeoutBytes)
}

/// Three settled frames of `tree` at 920×560, after three warm-up frames, over
/// one `StateTable` and `AnimationStore`: allocations, bytes and store entries.
@MainActor private func settledFrames<E: Element>(_ tree: @escaping @MainActor () -> E) throws
    -> (count: Int, bytes: Int, storeEntries: Int) {
    let table = StateTable(), store = AnimationStore(), cache = ShapingCache()
    let atlas = GlyphAtlas(width: Window.atlasExtent, height: Window.atlasExtent)
    var t = 0.0
    func one() {
        var root = tree()
        let frame = Frame(contentSize: Size(width: Pixels(920), height: Pixels(560)), scaleFactor: 1,
                          stateTable: table, shapingCache: cache, glyphAtlas: atlas,
                          timestamp: t, transaction: nil, animationStore: store)
        frame.render(&root)
        t += 1.0 / 60
    }
    for _ in 0..<3 { one() }
    let counted = try countCloseoutAllocations { for _ in 0..<3 { one() } }
    return (counted.count, counted.bytes, store.count)
}

/// A proposal row of `n` 4×4 rectangles, each under one `.frame` layer (one
/// store entry each) when `framed`, bare otherwise.
@MainActor private func row(_ n: Int, framed: Bool) -> some Element {
    HStack(spacing: Pixels(0)) {
        ForEach(0..<n, id: \.self) { _ in
            if framed { Rectangle(width: Pixels(4), height: Pixels(4)).frame(width: Pixels(4), height: Pixels(4)) }
            else { Rectangle(width: Pixels(4), height: Pixels(4)) }
        }
    }
}

/// **1.6 — a figure, not a gate** (`CX-I` item 1, record §64 §11's re-owned
/// allocation count). Gated by `METALUI_STORE_ALLOC_MEASURE=1`, run only with
/// `--no-parallel`: it installs a SECOND libmalloc `malloc_logger` hook beside
/// `ModifiedElementTests`' own, and two installers racing under a parallel run
/// is the hazard CLAUDE.md records as moot only while there is one (`CX-P`
/// item 8). Prints three settled frames' allocations and requested bytes for
/// the proposal preview (task 13 measured 12 store entries there), the legacy
/// demo (0 entries) and a differential: a row of 40 vs 80 framed rectangles
/// against the same rows bare, so the slope difference is what one settled
/// `.frame` layer — its store entry included — costs per frame. The output is
/// recorded in record §66 §4.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_STORE_ALLOC_MEASURE"] == "1"))
@MainActor func measureSettledStoreEntryAllocations() throws {
    let preview = try settledFrames { nativeLayoutPreviewContent() }
    let demo = try settledFrames { demoContent() }
    let framed40 = try settledFrames { row(40, framed: true) }
    let framed80 = try settledFrames { row(80, framed: true) }
    let bare40 = try settledFrames { row(40, framed: false) }
    let bare80 = try settledFrames { row(80, framed: false) }
    func line(_ name: String, _ r: (count: Int, bytes: Int, storeEntries: Int)) -> String {
        "\(name): \(r.count) allocations, \(r.bytes) bytes over 3 settled frames; store entries \(r.storeEntries)"
    }
    print("STORE-ALLOC " + line("proposal preview", preview))
    print("STORE-ALLOC " + line("legacy demo", demo))
    print("STORE-ALLOC " + line("40 framed", framed40))
    print("STORE-ALLOC " + line("80 framed", framed80))
    print("STORE-ALLOC " + line("40 bare", bare40))
    print("STORE-ALLOC " + line("80 bare", bare80))
    let perFramed = Double(framed80.count - framed40.count) / 40 / 3
    let perBare = Double(bare80.count - bare40.count) / 40 / 3
    let bytesFramed = Double(framed80.bytes - framed40.bytes) / 40 / 3
    let bytesBare = Double(bare80.bytes - bare40.bytes) / 40 / 3
    print(String(format: "STORE-ALLOC per element per settled frame: framed %.2f allocations / %.1f bytes, bare %.2f / %.1f; one settled .frame layer with its store entry: %.2f allocations / %.1f bytes",
                 perFramed, bytesFramed, perBare, bytesBare, perFramed - perBare, bytesFramed - bytesBare))
    #expect(framed80.storeEntries > framed40.storeEntries, "the instrument: framed rows hold store entries")
}

// MARK: - Lane-1 fix round: the public Box(decoration:) initialisers (CX-D, CX-P item 5)

/// **F1.1.** `Box(decoration:content:)` and its builder form paint exactly what
/// the `package` `Box(style: Style(), decoration:, content:)` they forward to
/// paints — the accent fill with its 12-point radii — with no content (the
/// plain form over `EmptyGroup`) and with content (the builder form over a
/// sized child). Nothing else in the suite asserted what either public
/// initialiser paints, so dropping its `decoration` argument stayed green.
///
/// Mutations **V-BOXDEC** (the plain form forwards `Decoration()`) and
/// **V-BOXDECB** (the builder form forwards `Decoration()`) → this test.
@Test @MainActor func thePublicBoxDecorationInitialisersPaintWhatTheStyleInitialiserPaints() throws {
    let decoration = Decoration(background: .accent, cornerRadius: Pixels(12))
    let plain = paintedShapes(40, 40, Box(decoration: decoration, content: EmptyGroup())
        .cssWidth(Pixels(40)).cssHeight(Pixels(40)))
    let plainReference = paintedShapes(40, 40, Box(style: Style(), decoration: decoration, content: EmptyGroup())
        .cssWidth(Pixels(40)).cssHeight(Pixels(40)))
    try #require(plain.count == 1, "the plain form paints one rect: \(plain)")
    #expect(plain[0].background == colour(.accent) && plain[0].radii == [12, 12, 12, 12]
                && plain[0].rect == [0, 0, 40, 40],
            "the plain form paints its decoration: \(plain[0])")
    #expect(plain == plainReference, "the plain form equals Box(style: Style(), …): \(plain) vs \(plainReference)")

    let built = paintedShapes(40, 40, Box(decoration: decoration) {
        Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(.surface)
    })
    let builtReference = paintedShapes(40, 40, Box(style: Style(), decoration: decoration) {
        Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(.surface)
    })
    try #require(built.count == 2, "the builder form's fill, then its child's: \(built)")
    let fill = try #require(built.first { $0.background == colour(.accent) }, "the builder form's own fill: \(built)")
    #expect(fill.radii == [12, 12, 12, 12] && fill.rect == [0, 0, 40, 40], "\(fill)")
    #expect(built == builtReference, "the builder form equals Box(style: Style(), …) { … }: \(built) vs \(builtReference)")
}

// MARK: - Lane-1 fix round: the public withState over an optional state (CX-F, CX-P)

/// A leaf that reads its state through the public `LayoutPass.withState` with
/// an optional `S` whose initial value is not `nil`, recording what the body saw.
private struct OptionalWithStateProbe: Element {
    let reads: OptionalReads
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        pass.withState(id, initial: Optional<Int>.some(5)) { (value: inout Int?) in
            MainActor.assumeIsolated { reads.layout.append(value) }
        }
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// **F1.2.** `pass.withState(id, initial: Optional(5))` on an absent entry hands
/// its body **5**, not `nil` — divergence 85's cast (`storage[id]?.value as? S`
/// succeeding as `.some(nil)` for an optional `S`) reached the public
/// `LayoutPass`/`PrepaintPass`/`PaintPass.withState` too, where the closeout's
/// first lane fixed only `peek`. The second frame reads the stored 5. Red before
/// the fix: `[nil, nil]`.
///
/// Mutation **V-WITHSTATE**: restore `withState`'s `(storage[id]?.value as? S)
/// ?? initial()` → this test.
@Test @MainActor func thePublicWithStateHandsAnOptionalStateItsInitialValueOnFirstAccess() throws {
    let reads = OptionalReads()
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device, size: 100) { Column { OptionalWithStateProbe(reads: reads) } }
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(reads.layout.count == 2, "two frames, two reads: \(reads.layout)")
    #expect(reads.layout == [5, 5], "the initial value on first access, then the stored one: \(reads.layout)")
}

// MARK: - Lane-1 fix round: the looks demo (CX-M item 1)

/// **F1.3.** `looksDemoContent()` — the runnable surface for human checks H1,
/// I1, J1 and K1–K3 — renders through a real `Window` without a trap and
/// draws what those checks look at: two ellipse primitives (the fill and the
/// stroke band, `MUIRect.shape == 1`), four images (fit, fill, nearest,
/// bilinear — two of each filter), and a native depth inside `maxDepth`. One
/// press of the first transition button inserts its tile, so K1 has something
/// to watch.
@Test @MainActor func theLooksDemoDrawsEverySurfaceItsHumanChecksName() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 1200) { looksDemoContent() }
    window.drawFrameIfNeeded()
    let scene = window.lastScene
    let ellipses = scene.rects.filter { $0.shape == 1 }
    #expect(ellipses.count == 2, "the ellipse fill and band: \(ellipses.count)")
    #expect(scene.images.count == 4, "fit, fill, nearest, bilinear: \(scene.images.count)")
    let deepest = window.lastNativeLayoutDeepestLevel
    print("LOOKS DEMO deepest native level: \(deepest)")
    #expect(deepest > 0 && deepest <= 72, "\(deepest)")

    let accent = colour(.accent)
    func accentCount(_ scene: Scene) -> Int {
        scene.rects.map(PaintedShape.init).filter {
            $0.background.h == accent.h && $0.background.s == accent.s && $0.background.l == accent.l
        }.count
    }
    let accentBefore = accentCount(scene)
    let buttons = window.lastHitboxes.filter { $0.handlers.onClick != nil }
    try #require(buttons.count == 9, "the nine transition buttons: \(buttons.count)")
    let first = try #require(buttons.min { $0.bounds.origin.y < $1.bounds.origin.y })
    let point = Point(x: first.bounds.origin.x + Pixels(4), y: first.bounds.origin.y + Pixels(4))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
    try #require(window.needsRedraw, "the press toggled the tile")
    window.drawFrameIfNeeded()
    let accentAfter = accentCount(window.lastScene)
    #expect(accentAfter == accentBefore + 1, "the opacity tile was inserted: \(accentBefore) → \(accentAfter)")
}

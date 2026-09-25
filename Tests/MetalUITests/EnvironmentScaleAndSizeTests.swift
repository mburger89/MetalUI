import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI
@testable import MetalUIText

// Plan task 9's closing half, lane 1: the values
// (`docs/superpowers/specs/2026-09-25-environment-control-state-design.md`
// §6, tests T1.1–T1.8; rulings `EV-AA`…`EV-AD`). SwiftUI's answers come from
// `docs/probes/swiftui-environment-control-state.swift` (arms V, S, C, Z) and
// the re-run of `swiftui-environment-pixel-length.swift` (V, X).
//
// **No `Metal` import**, so no `Dimension` ambiguity (`EnvironmentTests.swift`'s
// note). Every recorder is a reference type: element values do not survive a
// frame.
//
// The mutation each test is named for, and every test it reddened, are
// recorded under the ruling it cites and in
// `docs/record/56-environment-control-state.md`.

// MARK: - Fixtures

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// Whole `EnvironmentValues` snapshots per label per phase.
@MainActor
private final class ValueLog {
    var layout: [String: EnvironmentValues] = [:]
    var prepaint: [String: EnvironmentValues] = [:]
    var paint: [String: EnvironmentValues] = [:]

    /// One field of one label in layout, prepaint and paint.
    func read<V>(_ label: String, _ field: (EnvironmentValues) -> V) -> [V?] {
        [layout[label].map(field), prepaint[label].map(field), paint[label].map(field)]
    }
}

/// A native 10×10 leaf that records `pass.environment` in all three phases.
private struct ValueRecorder: Element {
    let label: String
    let log: ValueLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.layout[label] = pass.environment
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.prepaint[label] = pass.environment
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.paint[label] = pass.environment
    }
}

/// A leaf that fills a rect `pixelLength` points wide and `height` points
/// tall at its origin — the author's hairline, drawn through `PaintPass.fill`,
/// which takes points.
private struct Hairline: Element {
    let height: Float

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: Double(height))) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        let width = Float(pass.environment.pixelLength)
        pass.fill(Bounds(origin: bounds.origin, size: Size(width: px(width), height: px(height))),
                  color: Hsla(h: 0, s: 0, l: 0, a: 1))
    }
}

@MainActor
private func frame(_ width: Float = 200, _ height: Float = 50, scale: Float = 1,
                   recordsElementBounds: Bool = false) -> Frame {
    Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: scale,
          reportsUnlowerableFields: recordsElementBounds, recordsElementBounds: recordsElementBounds)
}

/// Renders `content` through the public headless entry point, `renderFrame`
/// (ruling DC-A) — the `ImageRenderer` analogue of probe arm S1.
@MainActor
private func headless<Root: Element>(scale: Float, _ content: () -> Root) {
    _ = renderFrame(content, size: Size(width: px(200), height: px(50)), scaleFactor: scale,
                    textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 256, height: 256))
}

// MARK: - T1.1–T1.4: displayScale (EV-AA)

/// **T1.1.** The root's `displayScale` is the frame's `scaleFactor` — the
/// drawable's, which is what `fill` multiplies by — and `pixelLength` follows,
/// in all three phases (probe S0: a hosted SwiftUI view reads the backing
/// scale factor; S1: an `ImageRenderer`'s content reads the renderer's scale).
/// A scale that is not finite and positive stamps 1 (the guard that used to
/// protect `pixelLength`), so no reader is handed an infinity.
///
/// Red-before: does not compile at `e732d98` (no `displayScale`); at runtime,
/// **M1.1** (the root stamps `displayScale = 1`).
@MainActor
@Test func theRootDisplayScaleIsTheFramesScaleFactorAndThePixelLengthFollows() throws {
    let cases: [(Float, Double)] = [(1, 1), (2, 0.5), (3, 1.0 / 3)]
    for (scale, expectedPixel) in cases {
        let log = ValueLog()
        var root = Row { ValueRecorder(label: "r", log: log) }
        frame(scale: scale).render(&root)
        #expect(log.read("r", \.displayScale) == [Double(scale), Double(scale), Double(scale)],
                "scale \(scale)")
        #expect(log.read("r", \.pixelLength) == [expectedPixel, expectedPixel, expectedPixel],
                "scale \(scale)")
    }

    for scale in [Float(0), .nan] {
        let log = ValueLog()
        var root = Row { ValueRecorder(label: "r", log: log) }
        frame(scale: scale).render(&root)
        #expect(log.read("r", \.displayScale) == [1, 1, 1], "scale \(scale)")
        #expect(log.read("r", \.pixelLength) == [1, 1, 1], "scale \(scale)")
    }

    let log = ValueLog()
    headless(scale: 3) { Row { ValueRecorder(label: "h", log: log) } }
    #expect(try #require(log.paint["h"]).displayScale == 3)
    #expect(try #require(log.paint["h"]).pixelLength == 1.0 / 3)
}

/// **T1.2.** A scope can write `displayScale` and `pixelLength` follows (probe
/// S2: `.environment(\.displayScale, 1 / 3)` reads 1/3; pixel-length probe
/// X1: 3 on a 2x display reads 1/3). An unscoped sibling keeps the frame's.
///
/// Red-before: does not compile at `e732d98`; at runtime, **M1.2**
/// (`scopedValues` re-stamps `displayScale` from the top after a transform —
/// the withdrawn `EV-U` shape).
@MainActor
@Test func aScopeCanWriteTheDisplayScaleAndThePixelLengthFollows() {
    let log = ValueLog()
    var root = Row {
        ValueRecorder(label: "three", log: log).environment(\.displayScale, 3)
        ValueRecorder(label: "one", log: log).environment(\.displayScale, 1)
        ValueRecorder(label: "sibling", log: log)
    }
    frame(scale: 2).render(&root)

    #expect(log.read("three", \.displayScale) == [3, 3, 3])
    let third: Double = 1.0 / 3
    #expect(log.read("three", \.pixelLength) == [third, third, third])
    #expect(log.read("one", \.displayScale) == [1, 1, 1])
    #expect(log.read("one", \.pixelLength) == [1, 1, 1])
    #expect(log.read("sibling", \.displayScale) == [2, 2, 2])
    #expect(log.read("sibling", \.pixelLength) == [0.5, 0.5, 0.5])
}

/// **T1.3.** `pixelLength` is SwiftUI's function of `displayScale`, verbatim
/// (probe V1): `1 / displayScale`, **except 0 → 1**; −1 → −1, NaN → NaN,
/// ∞ → 0; SwiftUI rejects no write, so neither does this (`SA-K`: nothing
/// internal reads `pixelLength`). A bare value reads 1 and 1 (V0).
///
/// Red-before: does not compile at `e732d98`; at runtime, **M1.3a** (no 0
/// case: 0 → ∞) and **M1.3b** (non-positive scales clamped to 1: −1 → 1).
@MainActor
@Test func aPixelLengthIsSwiftUIsFunctionOfTheDisplayScale() {
    let bare = EnvironmentValues()
    #expect(bare.displayScale == 1)
    #expect(bare.pixelLength == 1)

    func pixel(_ scale: Double) -> Double {
        var values = EnvironmentValues()
        values.displayScale = scale
        return values.pixelLength
    }
    #expect(pixel(1) == 1)
    #expect(pixel(4) == 0.25)
    #expect(pixel(0) == 1, "SwiftUI's 0 case (V1)")
    #expect(pixel(-1) == -1)
    #expect(pixel(.nan).isNaN)
    #expect(pixel(.infinity) == 0)
}

/// **T1.4.** A `displayScale` write changes the number, **not** the scale
/// drawing uses — SwiftUI's behaviour (probe S3: at renderer scale 2 a
/// `pixelLength`-wide hairline is 1 device pixel, and **2** under
/// `displayScale = 1`). `PaintPass.fill` takes points and scales by the
/// frame's factor, never the environment's.
///
/// **The two arms must disagree first** (shape 15): if both hairlines were one
/// pixel, "the write did not change the drawing" would pass for a write that
/// never landed.
///
/// Red-before: does not compile at `e732d98`; at runtime, **M1.4** (`fill`
/// scales by `environmentTop.displayScale`, so both arms read 1 px).
@MainActor
@Test func aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses() throws {
    let f = frame(scale: 2)
    var root = Row {
        Hairline(height: 10)
        Hairline(height: 12).environment(\.displayScale, 1)
    }
    f.render(&root)

    let rects = f.finalizedScene().rects
    let plain = try #require(rects.first { $0.bounds.size.height == 20 }, "the unscoped hairline")
    let written = try #require(rects.first { $0.bounds.size.height == 24 }, "the scoped hairline")
    try #require(plain.bounds.size.width != written.bounds.size.width,
                 "the two arms must disagree: \(plain.bounds.size.width) vs \(written.bounds.size.width)")
    #expect(plain.bounds.size.width == 1, "0.5 pt at the frame's 2x is one device pixel")
    #expect(written.bounds.size.width == 2, "1 pt at the frame's 2x is two device pixels (S3)")
}

// MARK: - T1.5: divergence 77 (EV-AD)

/// **T1.5. PINNED WRONG ON PURPOSE — divergence 77** (ruling EV-AD). SwiftUI
/// rounds each view's absolute position to the `displayScale` pixel grid and
/// follows a write (probe S4: 62.65 → 63 / 62.5 / 62.667 at 1 / 2 / 3). MetalUI's
/// `roundLayout` rounds every stored rect to whole points, whatever the scale.
///
/// The tree: a 100-wide leading frame (so the origin is integral: the frame
/// answers 100 in a 100-wide window and the root is centred at its own answer,
/// `CN-J`, at x 0), holding `HStack(spacing: 0)` of a 10.3-wide leader and a
/// 7-wide leaf, in a scale-2 frame. The leaf's unrounded x is 10.3; by S4's
/// rule SwiftUI would put it at 10 / 10.5 / 10.333 under writes of 1 / 2 / 3.
/// MetalUI puts it at **10** under every write and none — 20 device pixels. The
/// leaf is found by its width, 7 pt = 14 device pixels.
///
/// **Control**: a 10.6-wide leader puts the leaf at 11 (22 device pixels), so
/// the reading is rounding, not a leaf pinned at 10.
///
/// Its red is **M1.5** (`roundLayout` rounds to half points): 10.5, and the
/// control 10.5 too. Every other test that mutation reddens is listed in
/// record §56.
@MainActor
@Test func layoutRoundsToWholePointsWhateverTheDisplayScale() throws {
    func leafX(leader: Float, write: Double?) throws -> Float {
        let f = frame(100, 10, scale: 2)
        var root = ZStack {
            HStack(spacing: px(0)) {
                Rectangle(width: px(leader), height: px(10))
                Rectangle(width: px(7), height: px(10))
            }
            .transformEnvironment(\.displayScale) { if let write { $0 = write } }
            .frame(width: px(100), alignment: .leading)
        }
        f.render(&root)
        let leaf = try #require(f.finalizedScene().rects.first { $0.bounds.size.width == 14 },
                                "the 7-pt leaf at 2x")
        return leaf.bounds.origin.x
    }

    let control = try leafX(leader: 10.6, write: nil)
    try #require(control == 22, "the control leader rounds up: \(control)")
    for write in [nil, 1.0, 2.0, 3.0] as [Double?] {
        #expect(try leafX(leader: 10.3, write: write) == 20,
                "whole points at every displayScale (divergence 77), write \(String(describing: write))")
    }
}

// MARK: - T1.6, T1.7: controlSize (EV-AC)

/// **T1.6.** `controlSize` is `.regular` by default (probe V0) and scoped by
/// the nearest writer, through `.controlSize(_:)` and
/// `.environment(\.controlSize, _)` alike (Z1), in all three phases.
///
/// Red-before: does not compile at `e732d98`; at runtime, **M1.6**
/// (`.controlSize(_:)` writes `.regular` whatever its argument).
@MainActor
@Test func controlSizeIsScopedByTheNearestWriter() {
    #expect(EnvironmentValues().controlSize == .regular)

    let log = ValueLog()
    var root = Row {
        ValueRecorder(label: "default", log: log)
        ValueRecorder(label: "small", log: log).controlSize(.small)
        ValueRecorder(label: "large", log: log).controlSize(.large).controlSize(.small)
        ValueRecorder(label: "mini", log: log).environment(\.controlSize, .mini)
    }
    frame().render(&root)

    #expect(log.read("default", \.controlSize) == [.regular, .regular, .regular])
    #expect(log.read("small", \.controlSize) == [.small, .small, .small])
    #expect(log.read("large", \.controlSize) == [.large, .large, .large])
    #expect(log.read("mini", \.controlSize) == [.mini, .mini, .mini])
}

/// A `Text`'s measured size, read off `Frame.elementBounds`: `ideal` in a
/// 4000-wide frame (its one-line width) and `broken` in a 20-wide frame,
/// narrower than every word — `EnvironmentTests.swift`'s
/// `proposalTextMeasure`, restated here because that one is private. The
/// report is required empty.
@MainActor
private func textMeasure<C: ElementGroup>(_ content: (Text) -> C, _ text: Text)
    throws -> (ideal: Size<Pixels>, broken: Size<Pixels>) {
    let rowID = GlobalElementID.child(of: nil, at: 0, name: nil)
    let textID = GlobalElementID.child(of: rowID, at: 0, name: nil)
    func measured(width: Float) throws -> Size<Pixels> {
        let f = frame(width, 1000, recordsElementBounds: true)
        var root = Row { content(text) }
        f.render(&root)
        try #require(f.unlowerableFields.isEmpty,
                     "the text reported \(f.unlowerableFields.map(\.description))")
        return try #require(f.elementBounds[textID], "the text recorded no bounds").size
    }
    return (try measured(width: 4000), try measured(width: 20))
}

/// A `TextField`'s measured height, in a 200-wide frame, read the same way.
@MainActor
private func fieldHeight<C: ElementGroup>(_ content: (TextField) -> C, _ field: TextField) throws -> Float {
    let rowID = GlobalElementID.child(of: nil, at: 0, name: nil)
    let fieldID = GlobalElementID.child(of: rowID, at: 0, name: nil)
    let f = frame(200, 200, recordsElementBounds: true)
    var root = Row { content(field) }
    f.render(&root)
    try #require(f.unlowerableFields.isEmpty,
                 "the field reported \(f.unlowerableFields.map(\.description))")
    return try #require(f.elementBounds[fieldID], "the field recorded no bounds").size.height.value
}

/// **T1.7. PINNED WRONG ON PURPOSE — divergence 76** (ruling EV-AC).
/// SwiftUI's built-ins read `controlSize` on macOS: a `Text`'s **default**
/// font shrinks (probe Z2: 53×11 at `.mini`, 63×14 at `.small`, against 72×16
/// at `.regular` and above), and a `TextField` is 19 pt tall at `.mini`
/// against 24 at `.regular` (Z3). MetalUI's measure nothing differently: `Text`
/// stores `fontSize = 13` with no "default font" state. Owners: plan task 11
/// (`Text`), plan task 10 (`TextField`). This pin flips in those changes.
///
/// **Positive control**: a 26 pt font measures differently, `#require`d first,
/// for the `Text` and for the field.
///
/// Red-before: does not compile at `e732d98`; at runtime, **M1.7** (the lowered
/// `Text` measures at `fontSize * 0.7` under `.mini`).
@MainActor
@Test func controlSizeReachesNoBuiltInMeasurement() throws {
    let text = Text("Hello, control size")
    let bare = try textMeasure({ $0 }, text)
    let control = try textMeasure({ $0 }, text.font(size: 26))
    try #require(control.ideal != bare.ideal && control.broken != bare.broken,
                 "the control font must measure differently: \(control) vs \(bare)")
    for size in [ControlSize.mini, .small, .extraLarge] {
        let scoped = try textMeasure({ $0.controlSize(size) }, text)
        #expect(scoped.ideal == bare.ideal, "\(size)")
        #expect(scoped.broken == bare.broken, "\(size)")
    }

    let field = TextField("Name", text: "Hello") { _ in }
    let regular = try fieldHeight({ $0.controlSize(.regular) }, field)
    let big = try fieldHeight({ $0 }, field.font(size: 26))
    try #require(big != regular, "the control field must measure differently: \(big) vs \(regular)")
    #expect(try fieldHeight({ $0.controlSize(.mini) }, field) == regular)
}

// MARK: - T1.8: controlActiveState's value (EV-AB)

/// **T1.8.** `controlActiveState` is `.key` in a bare value (probe V0), so a
/// windowless `Frame` and `renderFrame` read `.key` — only a window stamps its
/// platform's state (lane 3). A scope can write it, and an unscoped sibling
/// keeps the root's (C4).
///
/// Red-before: does not compile at `e732d98`; at runtime, **M1.8** (the bare
/// default is `.inactive`).
@MainActor
@Test func controlActiveStateIsKeyInABareValueAndAWindowlessFrameAndAScopeCanWriteIt() throws {
    #expect(EnvironmentValues().controlActiveState == .key)

    let log = ValueLog()
    var root = Row {
        ValueRecorder(label: "root", log: log)
        ValueRecorder(label: "scoped", log: log).environment(\.controlActiveState, .inactive)
    }
    frame().render(&root)
    #expect(log.read("root", \.controlActiveState) == [.key, .key, .key])
    #expect(log.read("scoped", \.controlActiveState) == [.inactive, .inactive, .inactive])

    let headlessLog = ValueLog()
    headless(scale: 1) { Row { ValueRecorder(label: "h", log: headlessLog) } }
    #expect(try #require(headlessLog.paint["h"]).controlActiveState == .key)
}

import Testing
import Observation
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// Plan task 13, lane 2 — modifier wrappers participate in transactions at their
// correct phase (rulings `AN-AA`, `AN-AB`, `AN-AC`, as amended by `AN-AH` item
// 3). Spec `docs/superpowers/specs/2026-09-30-transactions-animation-design.md`
// §6.3, tests 2.1–2.12, 2.14–2.19 (2.13 is `DecorationPaintTests`'
// `thePaintOnlyDecorationFieldsAnimateAndClipSnaps`, 2.17's second half arm (c)
// of `AnimationTests`' `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`).
// SwiftUI's side is `docs/probes/swiftui-transactions-animation.swift`, arms
// W1–W11 and P1.
//
// **No test sleeps.** Most render headless `Frame`s over one shared `StateTable`
// and one shared `AnimationStore` at chosen timestamps, the transaction handed
// to the frame that starts the change (the frame's parked transaction, exactly
// what `Window.drawFrameIfNeeded` hands a build); 2.10 and 2.16 drive a real
// `Window` by `simulateTick(timestamp:)`. The shape of every arm: a resting
// frame at 0, the change at 0 under `linear(duration: 1)` (the frame that
// starts a transition reads its own `from`), 0.5 half-way, 1.0 landed.

// MARK: - Harness

/// One window's worth of retained state across headless frames.
@MainActor
final class WrapperHarness {
    let table = StateTable()
    let store = AnimationStore()
    var theme: Theme = .light
    var side: Float = 300

    /// Renders `element` at `t`, the transaction `animation` handed to this
    /// build only.
    @discardableResult
    func frame<E: Element>(_ t: Double, _ animation: Animation? = nil, _ element: E) -> Frame {
        var root = element
        let frame = Frame(contentSize: Size(width: Pixels(side), height: Pixels(side)), scaleFactor: 1,
                          stateTable: table, theme: theme, timestamp: t, transaction: animation,
                          animationStore: store, reportsUnlowerableFields: true, recordsElementBounds: true)
        frame.render(&root)
        #expect(frame.unlowerableFields.isEmpty, "t \(t): \(frame.unlowerableFields)")
        return frame
    }
}

private let linear1 = Animation.linear(duration: 1)

/// The first rect `frame` painted whose height is `height`.
@MainActor private func rect(_ frame: Frame, height: Float) -> MUIRect? {
    frame.scene.rects.first { $0.bounds.size.height == height }
}

/// The first rect that draws a border.
@MainActor private func borderRect(_ frame: Frame) -> MUIRect? {
    frame.scene.rects.first { $0.borderColor.a > 0 }
}

/// The widest rect `frame` painted.
@MainActor private func widest(_ frame: Frame) -> MUIRect? {
    frame.scene.rects.max { $0.bounds.size.width < $1.bounds.size.width }
}

private func hsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }

/// `from → to` at progress `t`, per RGB component — `animatedColor`'s own
/// arithmetic (never hue), resolved against `theme`.
@MainActor private func lerpColour(_ from: ColorToken, _ to: ColorToken, _ t: Float, in theme: Theme) -> Hsla {
    let a = theme[from].toRgba(), b = theme[to].toRgba()
    return Rgba(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t,
                b: a.b + (b.b - a.b) * t, a: a.a + (b.a - a.a) * t).toHsla()
}

private func close(_ a: Hsla, _ b: Hsla, _ tolerance: Float = 0.002) -> Bool {
    abs(a.h - b.h) <= tolerance && abs(a.s - b.s) <= tolerance
        && abs(a.l - b.l) <= tolerance && abs(a.a - b.a) <= tolerance
}

@MainActor private func isColour(_ c: MUIHsla, _ token: ColorToken, in theme: Theme) -> Bool {
    close(hsla(c), theme[token], 0.0005)
}

// MARK: - 2.1 (W1)

/// **2.1 (W1).** A proposal `.frame(width:)` 100 → 300 under `linear(1)`: 100 on
/// the frame that starts it, 200 half-way, 300 landed. Before lane 2 the layer
/// registered its declared case — "No `$anim`, no record" — and read 300 at once.
/// Mutation: skip the helper for `.frame`.
@Test @MainActor func aProposalFrameAnimatesItsWidthUnderATransaction() throws {
    let h = WrapperHarness()
    func tree(_ w: Float) -> some Element {
        Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(40))
            .background(.accent)
    }
    try #require(rect(h.frame(0, nil, tree(100)), height: 40)?.bounds.size.width == 100, "set up: 100 at rest")
    let start = rect(h.frame(0, linear1, tree(300)), height: 40)?.bounds.size.width
    let mid = rect(h.frame(0.5, nil, tree(300)), height: 40)?.bounds.size.width
    let end = rect(h.frame(1.0, nil, tree(300)), height: 40)?.bounds.size.width
    #expect(start == 100 && mid == 200 && end == 300,
            "W1: a proposal frame's width animates 100 → 200 → 300; got \(String(describing: start)), \(String(describing: mid)), \(String(describing: end)) (300, 300, 300 is a snap)")
}

// MARK: - 2.2 (W2)

/// **2.2 (W2).** A proposal `.padding` 10 → 30 around a 20 × 20 leaf: the
/// padded (background) box reads 40 → 60 → 80 and the leaf's origin moves with
/// it. Mutation: skip the helper for `.padding`.
@Test @MainActor func aProposalPaddingAnimatesItsInsets() throws {
    let h = WrapperHarness()
    func tree(_ p: Float) -> some Element {
        Rectangle(width: Pixels(20), height: Pixels(20)).padding(Edges(all: Pixels(p))).background(.accent)
    }
    try #require(widest(h.frame(0, nil, tree(10)))?.bounds.size.width == 40, "set up: 40 at rest")
    let start = widest(h.frame(0, linear1, tree(30)))?.bounds.size.width
    let midFrame = h.frame(0.5, nil, tree(30))
    let mid = widest(midFrame)
    let leaf = rect(midFrame, height: 20)
    let end = widest(h.frame(1.0, nil, tree(30)))?.bounds.size.width
    #expect(start == 40 && mid?.bounds.size.width == 60 && end == 80,
            "W2: the padded box animates 40 → 60 → 80; got \(String(describing: start)), \(String(describing: mid?.bounds.size.width)), \(String(describing: end))")
    if let mid, let leaf {
        #expect(leaf.bounds.origin.x - mid.bounds.origin.x == 20,
                "W2: half-way the leaf sits at the interpolated inset 20, got \(leaf.bounds.origin.x - mid.bounds.origin.x)")
    } else {
        Issue.record("the mid frame painted no padded box or no leaf")
    }
}

// MARK: - 2.3 (W7)

/// **2.3 (W7).** A `.flexibleFrame`'s FINITE bound animates (`minWidth` 100 →
/// 300 over a 10-wide leaf: 100 → 200 → 300); a bound that goes finite →
/// infinite SNAPS (`maxWidth` 200 → ∞: the start and mid frames already read
/// the landed width, measured, not assumed) — an interpolated infinity would be
/// a non-finite rect (`SA-K`). Mutation: interpolate across finite ↔ infinite
/// (the lane pins the snap).
@Test @MainActor func aProposalFlexibleFrameAnimatesAFiniteBoundAndSnapsAnInfiniteOne() throws {
    do {
        let h = WrapperHarness()
        func tree(_ m: Float) -> some Element {
            Rectangle(width: Pixels(10), height: Pixels(10))
                .frame(minWidth: Pixels(m), minHeight: Pixels(40), maxHeight: Pixels(40)).background(.accent)
        }
        try #require(rect(h.frame(0, nil, tree(100)), height: 40)?.bounds.size.width == 100, "set up: 100")
        let start = rect(h.frame(0, linear1, tree(300)), height: 40)?.bounds.size.width
        let mid = rect(h.frame(0.5, nil, tree(300)), height: 40)?.bounds.size.width
        #expect(start == 100 && mid == 200,
                "W7: a finite minWidth animates; got \(String(describing: start)) then \(String(describing: mid))")
    }
    do {
        let h = WrapperHarness()
        func tree(_ m: Float) -> some Element {
            Rectangle(width: Pixels(10), height: Pixels(10))
                .frame(minWidth: Pixels(50), maxWidth: Pixels(m), minHeight: Pixels(40), maxHeight: Pixels(40))
                .background(.accent)
        }
        let rest = rect(h.frame(0, nil, tree(200)), height: 40)?.bounds.size.width
        let start = rect(h.frame(0, linear1, tree(.infinity)), height: 40)?.bounds.size.width
        let mid = rect(h.frame(0.5, nil, tree(.infinity)), height: 40)?.bounds.size.width
        let landed = rect(h.frame(1.0, nil, tree(.infinity)), height: 40)?.bounds.size.width
        try #require(rest != nil && landed != nil && rest != landed,
                     "set up: the finite and infinite max must answer differently, got \(String(describing: rest)) and \(String(describing: landed))")
        #expect(start == landed && mid == landed,
                "finite → infinite snaps: start and mid read the landed \(String(describing: landed)); got \(String(describing: start)), \(String(describing: mid))")
    }
}

// MARK: - 2.4 (W3)

/// **2.4 (W3).** A proposal `.opacity` 1 → 0.2: the fill inside it reads alpha
/// 1 → 0.6 → 0.2 (a layout-phase number read by paint, `AN-AA`). Mutation: skip
/// the helper for `.opacity`.
@Test @MainActor func aProposalOpacityAnimates() throws {
    let h = WrapperHarness()
    func tree(_ o: Float) -> some Element {
        Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(50), height: Pixels(40))
            .background(.accent).opacity(o)
    }
    let rest = try #require(rect(h.frame(0, nil, tree(1)), height: 40)?.background.a, "set up: a fill")
    let start = rect(h.frame(0, linear1, tree(0.2)), height: 40)?.background.a
    let mid = rect(h.frame(0.5, nil, tree(0.2)), height: 40)?.background.a
    let end = rect(h.frame(1.0, nil, tree(0.2)), height: 40)?.background.a
    #expect(start == rest, "W3: the start frame reads its own from, alpha \(rest); got \(String(describing: start))")
    #expect(abs((mid ?? 0) - rest * 0.6) < 0.001,
            "W3: half-way the opacity is 0.6; alpha \(rest * 0.6) expected, got \(String(describing: mid))")
    #expect(abs((end ?? 0) - rest * 0.2) < 0.001, "W3: lands at 0.2, got \(String(describing: end))")
}

// MARK: - 2.5 (W4)

/// **2.5 (W4).** A proposal `.background` token `.background → .accent` fades
/// through the per-component midpoint, and a theme swap mid-flight moves BOTH
/// ends (a token track, `AN-H`); a theme swap on a settled layer starts no fade.
/// Mutation: store the resolved colour instead of the token (`AN-H`'s mutation
/// 25 shape).
@Test @MainActor func aProposalBackgroundFadesItsTokenAndReResolvesOnAThemeSwap() throws {
    func tree(_ token: ColorToken) -> some Element {
        Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(50), height: Pixels(40))
            .background(token)
    }
    // The fade, light theme throughout.
    do {
        let h = WrapperHarness()
        let theme = h.theme
        let rest = try #require(rect(h.frame(0, nil, tree(.background)), height: 40))
        try #require(isColour(rest.background, .background, in: theme), "set up: the resting token")
        let start = try #require(rect(h.frame(0, linear1, tree(.accent)), height: 40))
        #expect(isColour(start.background, .background, in: theme), "W4: the start frame reads its from")
        let mid = try #require(rect(h.frame(0.5, nil, tree(.accent)), height: 40))
        let want = lerpColour(.background, .accent, 0.5, in: theme)
        #expect(close(hsla(mid.background), want),
                "W4: half-way is the per-component midpoint \(want), got \(hsla(mid.background))")
        let end = try #require(rect(h.frame(1.0, nil, tree(.accent)), height: 40))
        #expect(isColour(end.background, .accent, in: theme), "W4: lands on the token")
    }
    // A theme swap mid-flight: both ends re-resolve.
    do {
        let h = WrapperHarness()
        h.frame(0, nil, tree(.background))
        h.frame(0, linear1, tree(.accent))
        h.theme = .dark
        let mid = try #require(rect(h.frame(0.5, nil, tree(.accent)), height: 40))
        let want = lerpColour(.background, .accent, 0.5, in: .dark)
        try #require(!close(want, lerpColour(.background, .accent, 0.5, in: .light)),
                     "set up: the two themes' midpoints must differ")
        #expect(close(hsla(mid.background), want),
                "a theme swap mid-flight re-resolves both ends: \(want) expected, got \(hsla(mid.background))")
    }
    // A theme swap on a settled layer, under a transaction: no fade.
    do {
        let h = WrapperHarness()
        h.frame(0, nil, tree(.accent))
        h.theme = .dark
        let swapped = h.frame(1, linear1, tree(.accent))
        let fill = try #require(rect(swapped, height: 40))
        #expect(isColour(fill.background, .accent, in: .dark) && !swapped.hasActiveAnimations,
                "a theme swap alone starts no fade: the new theme's token at once, nothing live")
    }
}

// MARK: - 2.6 (W5, W5c)

/// **2.6 (W5, W5c).** A proposal `.border` changing colour `.background →
/// .accent` and width 1 → 5 together: half-way the stroke is 3 wide and the
/// colour is the midpoint. Mutations: skip the width; skip the colour.
@Test @MainActor func aProposalBorderAnimatesItsColourAndWidth() throws {
    let h = WrapperHarness()
    let theme = h.theme
    func tree(_ token: ColorToken, _ w: Float) -> some Element {
        Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(50), height: Pixels(40))
            .border(token, width: Pixels(w))
    }
    let rest = try #require(borderRect(h.frame(0, nil, tree(.background, 1))), "set up: a border rect")
    try #require(rest.borderWidths.top == 1 && isColour(rest.borderColor, .background, in: theme), "set up")
    let start = try #require(borderRect(h.frame(0, linear1, tree(.accent, 5))))
    #expect(start.borderWidths.top == 1 && isColour(start.borderColor, .background, in: theme),
            "the start frame reads its from")
    let mid = try #require(borderRect(h.frame(0.5, nil, tree(.accent, 5))))
    #expect(mid.borderWidths.top == 3, "W5: the width is 3 half-way, got \(mid.borderWidths.top)")
    let want = lerpColour(.background, .accent, 0.5, in: theme)
    #expect(close(hsla(mid.borderColor), want),
            "W5c: the colour is the midpoint \(want), got \(hsla(mid.borderColor))")
}

// MARK: - 2.7 (W6)

/// A 50 × 40 leaf that fills itself and records the clip radius active during
/// its PREPAINT — the scope hit testing registers against.
@MainActor final class ClipLog { var prepaintRadius: Float? }

struct ClipProbe: ProposalElement {
    let log: ClipLog

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 50, height: 40)) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.prepaintRadius = pass.frame.activeClipRadii.topLeft.value
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        pass.fill(bounds, color: pass.theme[.accent], cornerRadii: Corners(all: Pixels(0)))
    }
}

/// **2.7 (W6).** A proposal `.clip(cornerRadius:)` 2 → 12: half-way the radius
/// is 7 in PAINT (the content's mask) and in PREPAINT (the scope hitboxes
/// register in) — one interpolated value, the layer's rewritten case. Mutation:
/// prepaint reads the declared radius.
@Test @MainActor func aProposalClipAnimatesItsCornerRadiusInPaintAndHitTesting() throws {
    let h = WrapperHarness()
    let log = ClipLog()
    func tree(_ r: Float) -> some Element { ClipProbe(log: log).clip(cornerRadius: Pixels(r)) }
    try #require(rect(h.frame(0, nil, tree(2)), height: 40)?.maskCornerRadii.topLeft == 2 && log.prepaintRadius == 2,
                 "set up: radius 2 in both phases")
    h.frame(0, linear1, tree(12))
    let mid = rect(h.frame(0.5, nil, tree(12)), height: 40)
    #expect(mid?.maskCornerRadii.topLeft == 7, "paint: radius 7 half-way, got \(String(describing: mid?.maskCornerRadii.topLeft))")
    #expect(log.prepaintRadius == 7, "prepaint (hit testing): radius 7 half-way, got \(String(describing: log.prepaintRadius))")
}

// MARK: - 2.8: every animatable case

/// **2.8.** One arm per animatable `LayoutModifier` case, each changing only
/// that case under one transaction and reading a half-way value strictly
/// between its endpoints. Mutation: remove `.padding`'s helper call — exactly
/// the padding arm.
@Test @MainActor func everyAnimatableProposalModifierAnimates() throws {
    func arm<E: Element>(_ name: String, _ make: (Bool) -> E, _ read: (Frame) -> Float?) {
        let h = WrapperHarness()
        let a = read(h.frame(0, nil, make(false)))
        h.frame(0, linear1, make(true))
        let mid = read(h.frame(0.5, nil, make(true)))
        let b = read(h.frame(1.0, nil, make(true)))
        guard let a, let b, let mid, a != b else {
            Issue.record("\(name): set up — the endpoints must differ: \(String(describing: a)), \(String(describing: b))")
            return
        }
        #expect(mid > min(a, b) && mid < max(a, b), "\(name): half-way \(mid) must lie strictly between \(a) and \(b)")
    }
    let leaf = Rectangle(width: Pixels(10), height: Pixels(10))
    arm("frame", { leaf.frame(width: Pixels($0 ? 300 : 100), height: Pixels(40)).background(.accent) }) {
        rect($0, height: 40)?.bounds.size.width
    }
    arm("flexibleFrame", {
        leaf.frame(minWidth: Pixels($0 ? 300 : 100), minHeight: Pixels(40), maxHeight: Pixels(40)).background(.accent)
    }) { rect($0, height: 40)?.bounds.size.width }
    arm("padding", { leaf.padding(Edges(all: Pixels($0 ? 30 : 10))).background(.accent) }) {
        widest($0)?.bounds.size.width
    }
    arm("opacity", {
        leaf.frame(width: Pixels(50), height: Pixels(40)).background(.accent).opacity($0 ? 0.2 : 1)
    }) { rect($0, height: 40)?.background.a }
    arm("clip", { leaf.frame(width: Pixels(50), height: Pixels(40)).clip(cornerRadius: Pixels($0 ? 12 : 2)) }) {
        rect($0, height: 10)?.maskCornerRadii.topLeft
    }
    arm("border width", {
        leaf.frame(width: Pixels(50), height: Pixels(40)).border(.accent, width: Pixels($0 ? 5 : 1))
    }) { borderRect($0)?.borderWidths.top }
    arm("background colour", {
        leaf.frame(width: Pixels(50), height: Pixels(40)).background($0 ? .accent : .background)
    }) { rect($0, height: 40)?.background.l }
    arm("border colour", {
        leaf.frame(width: Pixels(50), height: Pixels(40)).border($0 ? .accent : .background, width: Pixels(2))
    }) { borderRect($0)?.borderColor.l }
}

// MARK: - 2.9

@Observable final class WrapperModel {
    var width: Float = 100
    var show = true
}

/// **2.9.** A proposal layer that leaves (inside an `if`) for a frame and
/// returns under a transaction with a new width SNAPS: its track was dropped by
/// the frame that did not touch it (`AN-AB`), so its return is a first sighting
/// — `ID-C`'s answer for the `$anim` slots. The control, no detour, animates.
/// Green first (a pin). Mutation: keep untouched entries across a frame.
@Test @MainActor func aProposalModifierReturningInsideAnIfSnaps() throws {
    func tree(_ show: Bool, _ w: Float) -> some Element {
        Column {
            if show {
                Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(40))
                    .background(.accent)
            }
        }
    }
    let control = WrapperHarness()
    control.frame(0, nil, tree(true, 100))
    control.frame(0.1, nil, tree(true, 100))
    let animates = rect(control.frame(0.2, linear1, tree(true, 300)), height: 40)?.bounds.size.width
    try #require(animates == 100, "the control: with no detour the change animates from 100, got \(String(describing: animates))")

    let h = WrapperHarness()
    h.frame(0, nil, tree(true, 100))
    h.frame(0.1, nil, tree(false, 100))
    let returned = rect(h.frame(0.2, linear1, tree(true, 300)), height: 40)?.bounds.size.width
    let later = rect(h.frame(0.7, nil, tree(true, 300)), height: 40)?.bounds.size.width
    #expect(returned == 300 && later == 300,
            "a layer returning inside an if is a first sighting and snaps to 300; got \(String(describing: returned)), \(String(describing: later))")
}

// MARK: - 2.10

/// **2.10.** Through a real `Window`: a proposal frame's animation keeps
/// `hasActiveAnimations` raised while it runs and lets the display link pause on
/// the frame after it lands (`AN-M`). Mutation: omit `noteActiveAnimation()`.
@Test @MainActor func aProposalAnimationKeepsTheDisplayLinkAwakeUntilItSettles() throws {
    let model = WrapperModel()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 300, startsDisplayLink: true) {
        Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(model.width), height: Pixels(40))
            .background(.accent)
    }
    platform.simulateTick(timestamp: 100)
    try #require(!window.hasActiveAnimations, "set up: nothing live at rest")
    withAnimation(.linear(duration: 1)) { model.width = 300 }
    platform.simulateTick(timestamp: 100.1)
    #expect(window.hasActiveAnimations, "the frame that starts the animation is live")
    platform.simulateTick(timestamp: 100.6)
    #expect(window.hasActiveAnimations, "half-way is live")
    #expect(window.lastScene.rects.first { $0.bounds.size.height == 40 }?.bounds.size.width == 200,
            "half-way the width is 200 (through the production dirty path)")
    platform.simulateTick(timestamp: 101.2)
    #expect(!window.hasActiveAnimations, "landed: nothing live")
    platform.simulateTick(timestamp: 101.3)
    #expect(platform.pauseCalls.last == true, "the display link pauses on the frame after the animation lands")
}

// MARK: - 2.11

/// **2.11.** Proposal layers mint NO `StateTable` entry (`AN-AB`): a chain of six
/// animatable layers over a leaf leaves the table the size the bare leaf leaves
/// it, at rest and mid-flight, while the `AnimationStore` holds their tracks.
/// Mutation: store proposal baselines in `StateTable`.
@Test @MainActor func aProposalTreeMintsNoStateTableEntryForItsModifiers() throws {
    let bare = WrapperHarness()
    bare.frame(0, nil, Rectangle(width: Pixels(10), height: Pixels(10)))
    func chain(_ w: Float) -> some Element {
        Rectangle(width: Pixels(10), height: Pixels(10)).padding(Edges(all: Pixels(4)))
            .frame(width: Pixels(w), height: Pixels(40)).background(.accent).border(.surface, width: Pixels(2))
            .clip(cornerRadius: Pixels(4)).opacity(0.9)
    }
    let h = WrapperHarness()
    h.frame(0, nil, chain(100))
    #expect(h.table.count == bare.table.count,
            "at rest: \(h.table.count) table entries with six layers, \(bare.table.count) without")
    try #require(h.store.count > 0, "set up: the layers' tracks are in the store")
    h.frame(0, linear1, chain(300))
    h.frame(0.5, nil, chain(300))
    #expect(h.table.count == bare.table.count,
            "mid-flight: \(h.table.count) table entries with six layers, \(bare.table.count) without")
}

// MARK: - 2.12

/// **2.12.** A work counter, not a clock: `AnimationStore.lastFrameInterpolations`
/// reads 0 on every settled frame and exactly `n` while `n` layers move (each
/// changing one number). Mutation: interpolate (count) every frame.
@Test @MainActor func aSettledProposalTreeInterpolatesNothing() throws {
    let h = WrapperHarness()
    func tree(_ w: Float) -> some Element {
        HStack(spacing: Pixels(0)) {
            Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(40))
            Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(41))
            Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(42))
                .opacity(0.5)
        }
    }
    h.frame(0, nil, tree(50))
    h.frame(0.1, nil, tree(50))
    #expect(h.store.lastFrameInterpolations == 0, "a settled frame interpolates nothing, got \(h.store.lastFrameInterpolations)")
    h.frame(0.2, linear1, tree(80))
    #expect(h.store.lastFrameInterpolations == 3, "three layers move: 3, got \(h.store.lastFrameInterpolations)")
    h.frame(0.7, nil, tree(80))
    #expect(h.store.lastFrameInterpolations == 3, "still three half-way, got \(h.store.lastFrameInterpolations)")
    h.frame(1.2, nil, tree(80))
    h.frame(1.3, nil, tree(80))
    #expect(h.store.lastFrameInterpolations == 0, "landed: 0 again, got \(h.store.lastFrameInterpolations)")
}

// MARK: - 2.14

/// **2.14.** A legacy border fade does not retarget the background's fade: the
/// background starts `.surface → .accent` at 0, the border starts `.surface →
/// .separator` at 0.25 under a transaction of its own; at 0.5 the background is
/// exactly its own half-way colour. Mutation: key the border track on the
/// `$anim-color` entry.
@Test @MainActor func aBorderFadeDoesNotRetargetTheBackgroundFade() throws {
    let h = WrapperHarness()
    let theme = h.theme
    func tree(_ fill: ColorToken, _ border: ColorToken) -> some Element {
        Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(fill).border(border, width: Pixels(4))
    }
    func fill(_ f: Frame) -> MUIRect? {
        f.scene.rects.first { $0.bounds.size.width == 40 && $0.borderColor.a == 0 }
    }
    h.frame(0, nil, tree(.surface, .surface))
    h.frame(0, linear1, tree(.accent, .surface))
    h.frame(0.25, linear1, tree(.accent, .separator))
    let mid = try #require(fill(h.frame(0.5, nil, tree(.accent, .separator))), "a fill rect")
    let want = lerpColour(.surface, .accent, 0.5, in: theme)
    #expect(close(hsla(mid.background), want),
            "the background is its own half-way colour \(want), untouched by the border's fade; got \(hsla(mid.background))")
}

// MARK: - 2.15

/// **2.15 (`AN-AH` item 3).** The legacy border-colour track mints NO
/// `StateTable` entry: a `Box` whose background and border both change under a
/// transaction leaves the table the size the same `Box` without a border leaves
/// it — and the border still reads a mid-flight colour. Mutation: store the
/// track in `StateTable` under a named child.
@Test @MainActor func theBorderColourTrackMintsNoStateTableEntry() throws {
    let theme = Theme.light
    func run(bordered: Bool) -> (WrapperHarness, Frame) {
        let h = WrapperHarness()
        func tree(_ t: ColorToken) -> Box<EmptyGroup> {
            let box = Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(t)
            return bordered ? box.border(t, width: Pixels(4)) : box
        }
        h.frame(0, nil, tree(.surface))
        h.frame(0, linear1, tree(.accent))
        return (h, h.frame(0.5, nil, tree(.accent)))
    }
    let (plain, _) = run(bordered: false)
    let (bordered, mid) = run(bordered: true)
    #expect(bordered.table.count == plain.table.count,
            "\(bordered.table.count) table entries with the border, \(plain.table.count) without")
    let border = try #require(borderRect(mid), "a border rect")
    #expect(close(hsla(border.borderColor), lerpColour(.surface, .accent, 0.5, in: theme)),
            "and the border fades: half-way colour expected, got \(hsla(border.borderColor))")
}

// MARK: - 2.16

@Observable final class HoverBorderModel { var hoverToken: ColorToken = .surface }

/// **2.16.** Through a real `Window`, genuinely hovered: the RESOLVED border
/// (the hover border, since the pointer is over the box) fades when its token
/// changes under a transaction. Mutation: resolve the border track from the
/// plain field only.
@Test @MainActor func aHoverBorderFadesItsResolvedColour() throws {
    let model = HoverBorderModel()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 100, startsDisplayLink: true) {
        Box().cssWidth(Pixels(40)).cssHeight(Pixels(40))
            .border(.background, width: Pixels(4))
            .hoverBorder(model.hoverToken, width: Pixels(4))
            .onClick {}
    }
    let theme = window.theme
    platform.simulateTick(timestamp: 100)
    _ = platform.simulateInput(.mouseMoved(MouseEvent(position: Point(x: Pixels(50), y: Pixels(50)))))
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 100.05)
    let hovered = try #require(window.lastScene.rects.first { $0.borderColor.a > 0 }, "a border rect")
    try #require(isColour(hovered.borderColor, .surface, in: theme),
                 "set up: hovered, the hover border's token is drawn, got \(hsla(hovered.borderColor))")

    withAnimation(.linear(duration: 1)) { model.hoverToken = .accent }
    platform.simulateTick(timestamp: 100.2)
    platform.simulateTick(timestamp: 100.7)
    let mid = try #require(window.lastScene.rects.first { $0.borderColor.a > 0 })
    #expect(!isColour(mid.borderColor, .surface, in: theme) && !isColour(mid.borderColor, .accent, in: theme)
                && !isColour(mid.borderColor, .background, in: theme),
            "the hover border fades: half-way is neither endpoint, got \(hsla(mid.borderColor))")
    platform.simulateTick(timestamp: 101.3)
    let landed = try #require(window.lastScene.rects.first { $0.borderColor.a > 0 })
    #expect(isColour(landed.borderColor, .accent, in: theme), "lands on the hover token")
}

// MARK: - 2.17, 2.18: a Component's caller modifiers (B-7)

private struct OneMember: Component {
    var content: some ElementGroup {
        Box().cssWidth(Pixels(20)).cssHeight(Pixels(10)).background(.accent)
    }
}

/// **2.17 (`AN-AC`, B-7 fixed).** A caller's `.width` and `.padding` on a
/// `Component` animate. The member (20 wide) is centred in its width frame
/// (`LR-BG`), which sits inside the padding, so its x is `p + (w − 20) / 2`:
/// `.width(100 → 300)` with `.padding(4 → 20)` reads 44 → 102 → 160 (half-way
/// w 200, p 12), and its y moves with the padding alone, +8 then +16. Mutation:
/// drop the op interpolation (also reddens arm (c) of
/// `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`).
@Test @MainActor func aComponentsCallerModifierAnimates() throws {
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    let member = GlobalElementID.child(of: GlobalElementID.child(of: root, at: 0, name: nil), at: 0, name: nil)
    func tree(_ w: Float, _ p: Float) -> some Element {
        DifferentialRoot(width: 300, height: 100) { OneMember().width(Pixels(w)).padding(Pixels(p)) }
    }
    let h = WrapperHarness()
    func memberBounds(_ f: Frame) -> Bounds<Pixels>? { f.elementBounds[member] }
    let rest = try #require(memberBounds(h.frame(0, nil, tree(100, 4))), "set up: the member's bounds")
    try #require(rest.origin.x.value == 44, "set up: 4 + (100 − 20) / 2 = 44, got \(rest)")
    let start = memberBounds(h.frame(0, linear1, tree(300, 20)))
    let mid = memberBounds(h.frame(0.5, nil, tree(300, 20)))
    let end = memberBounds(h.frame(1.0, nil, tree(300, 20)))
    #expect(start == rest, "the start frame reads its from: \(rest), got \(String(describing: start))")
    #expect(mid?.origin.x.value == 102 && mid?.origin.y.value == rest.origin.y.value + 8,
            "half-way (w 200, p 12) the member is at x 102 and 8 lower, got \(String(describing: mid)) from \(rest)")
    #expect(end?.origin.x.value == 160 && end?.origin.y.value == rest.origin.y.value + 16,
            "landed (w 300, p 20): x 160 and 16 lower, got \(String(describing: end))")
    #expect(h.frame(1.1, nil, tree(300, 20)).hasActiveAnimations == false, "settled")
}

@Observable final class MemberModel { var second = false }

private struct MaybeTwo: Component {
    let second: Bool
    var content: some ElementGroup {
        Box().cssWidth(Pixels(20)).cssHeight(Pixels(10)).background(.accent)
        if second {
            Box().cssWidth(Pixels(20)).cssHeight(Pixels(11)).background(.accent)
        }
    }
}

/// **2.18.** Each member's op is its own track: a member that appears on the
/// frame a caller's `.width` changes under a transaction is a first sighting and
/// snaps to 300, while the member that was there animates from 100. Mutation:
/// key without the member index (the new member reads the old one's track).
@Test @MainActor func aComponentsOpsAnimateEachMemberSeparately() throws {
    let h = WrapperHarness()
    func tree(_ second: Bool, _ w: Float) -> some Element {
        DifferentialRoot(width: 300, height: 100) { MaybeTwo(second: second).width(Pixels(w)) }
    }
    func frameWidth(_ f: Frame, height: Float) -> Float? {
        // The member is centred in its frame (`LR-BG`): the frame's width is
        // twice its x plus its own 20, measured from the frame's origin at 0.
        guard let r = f.scene.rects.first(where: { $0.bounds.size.height == height }) else { return nil }
        return 2 * r.bounds.origin.x + 20
    }
    h.frame(0, nil, tree(false, 100))
    let start = h.frame(0, linear1, tree(true, 300))
    let mid = h.frame(0.5, nil, tree(true, 300))
    try #require(frameWidth(start, height: 10) == 100, "set up: the first member starts from 100, got \(String(describing: frameWidth(start, height: 10)))")
    #expect(frameWidth(mid, height: 10) == 200, "the first member animates: 200 half-way")
    #expect(frameWidth(start, height: 11) == 300 && frameWidth(mid, height: 11) == 300,
            "the new member snaps to 300 — its own track, a first sighting; got \(String(describing: frameWidth(start, height: 11))), \(String(describing: frameWidth(mid, height: 11)))")
}

// MARK: - 2.19: divergence 96, pinned wrong on purpose

/// A layout that records every width it is proposed and answers it.
final class ProposalWidthLog: @unchecked Sendable { var widths: [Double] = [] }

struct RecordsProposedWidth: ProposalLayout {
    let log: ProposalWidthLog
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        log.widths.append(proposal.width ?? -1)
        return LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

/// **2.19 — divergence 96, WRONG ON PURPOSE.** A custom `ProposalLayout` inside
/// `.frame(width: 100 → 300)` is proposed the INTERMEDIATE width half-way (200):
/// MetalUI interpolates the frame's declared width and re-runs layout every
/// frame (`AN-E`, `AN-X`). SwiftUI lays out once at the final values and
/// interpolates placed geometry — its P1 proposes only 300. If this reads only
/// 300, MetalUI moved to the geometry model: re-rule divergence 96. Mutation:
/// lay out at the final value (the layer not rewritten before its native
/// wrapper registers) — the red shows the pin sees the difference.
@Test @MainActor func aProposalFrameReLaysItsChildAtEachIntermediateWidth() throws {
    let log = ProposalWidthLog()
    let h = WrapperHarness()
    func tree(_ w: Float) -> some Element {
        ProposalLayoutContainer(RecordsProposedWidth(log: log)) { Rectangle(width: Pixels(10), height: Pixels(10)) }
            .frame(width: Pixels(w), height: Pixels(40))
    }
    h.frame(0, nil, tree(100))
    h.frame(0, linear1, tree(300))
    log.widths.removeAll()
    h.frame(0.5, nil, tree(300))
    #expect(log.widths.contains(200) && !log.widths.contains(300),
            "WRONG ON PURPOSE (divergence 96): half-way the child is proposed 200, where SwiftUI's P1 proposes only 300; got \(log.widths)")
}

// MARK: - Fix round: the in-flight clamps under an overshooting spring (AN-AJ item 4)

/// The bouncy spring the clamp pins run under: `bounce: 0.8` (ζ 0.2) overshoots
/// by roughly half its travel, measured below before a pin relies on it.
private let bouncy = Animation.spring(duration: 0.5, bounce: 0.8)

/// The sample times (0.02 s apart over 2 s) at which `from → to` under
/// `bouncy` has passed BELOW `floor` — the frames where only a clamp stands
/// between the interpolated value and a precondition.
private func overshootTimes(from: Double, to: Double, below floor: Double) -> [Double] {
    (1...100).map { Double($0) * 0.02 }.filter {
        bouncy.value(at: $0, from: from, to: to, initialVelocity: 0).value < floor
    }
}

/// **Fix round (`AN-AJ` item 4) — the separating arm.** Each clamp pin below is
/// only a pin if its spring really overshoots past the bound at a sampled
/// frame; this measures it, so a gentler spring cannot leave the exit tests
/// passing for free.
@Test func theClampPinsSpringOvershootsPastEachBound() throws {
    #expect(!overshootTimes(from: 1, to: 0, below: 0).isEmpty, "opacity 1 → 0 goes below 0")
    #expect(!overshootTimes(from: 4, to: 0, below: 0).isEmpty, "a border width 4 → 0 goes below 0")
    #expect(!overshootTimes(from: 100, to: 0, below: 0).isEmpty, "a frame width 100 → 0 goes below 0")
    // A minWidth 10 → 100 under a fixed maxWidth 100 goes above the maximum.
    #expect(!overshootTimes(from: -10, to: -100, below: -100).isEmpty, "a minWidth 10 → 100 passes 100")
}

/// **Fix round (`AN-AJ` item 4).** A proposal `.opacity(1 → 0)` under the bouncy
/// spring, ticked every 0.02 s: no frame traps (`PaintPass.opacity`'s `0...1`
/// precondition), and at every sampled frame where the spring is below 0 the
/// fill is drawn at alpha 0 — the clamp's value, read mid-overshoot. An exit
/// test, because without the clamp the process traps. Mutation C1 (drop
/// `animatedNumbers`' in-flight clamp).
@Test func aProposalOpacityClampsAnOvershootingSpringToZero() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let h = WrapperHarness()
            @MainActor func tree(_ o: Float) -> some Element {
                Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(50), height: Pixels(40))
                    .background(.accent).opacity(o)
            }
            h.frame(0, nil, tree(1))
            h.frame(0, bouncy, tree(0))
            let under = Set(overshootTimes(from: 1, to: 0, below: 0))
            precondition(!under.isEmpty, "the spring must overshoot")
            for t in (1...100).map({ Double($0) * 0.02 }) {
                let alpha = rect(h.frame(t, nil, tree(0)), height: 40)?.background.a ?? 0
                if under.contains(t) { precondition(alpha == 0, "t \(t): clamped to 0, got \(alpha)") }
            }
        }
    }
}

/// **Fix round (`AN-AJ` item 4).** A legacy `.opacity(1 → 0)` under the bouncy
/// spring: no trap, and alpha 0 at every sampled overshoot. Mutation C2 (drop
/// `Decoration.setInterpolatedOpacity`'s clamp).
@Test func aLegacyOpacityClampsAnOvershootingSpringToZero() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let h = WrapperHarness()
            @MainActor func tree(_ o: Float) -> some Element {
                Box().cssWidth(Pixels(50)).cssHeight(Pixels(40)).background(.accent).opacity(o)
            }
            h.frame(0, nil, tree(1))
            h.frame(0, bouncy, tree(0))
            let under = Set(overshootTimes(from: 1, to: 0, below: 0))
            precondition(!under.isEmpty, "the spring must overshoot")
            for t in (1...100).map({ Double($0) * 0.02 }) {
                let alpha = rect(h.frame(t, nil, tree(0)), height: 40)?.background.a ?? 0
                if under.contains(t) { precondition(alpha == 0, "t \(t): clamped to 0, got \(alpha)") }
            }
        }
    }
}

/// **Fix round (`AN-AJ` item 4).** A legacy border width 4 → 0 under the bouncy
/// spring: no trap (`BorderStyle.validate`'s non-negative precondition), and
/// every sampled overshoot draws width 0. Mutation G (drop `borderWidths`'
/// `max(0, …)`).
@Test func aLegacyBorderWidthClampsAnOvershootingSpringToZero() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let h = WrapperHarness()
            @MainActor func tree(_ w: Float) -> some Element {
                Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).border(.accent, width: Pixels(w))
            }
            h.frame(0, nil, tree(4))
            h.frame(0, bouncy, tree(0))
            let under = Set(overshootTimes(from: 4, to: 0, below: 0))
            precondition(!under.isEmpty, "the spring must overshoot")
            for t in (1...100).map({ Double($0) * 0.02 }) {
                let f = h.frame(t, nil, tree(0))
                let width = f.scene.rects.first { $0.bounds.size.width == 40 }?.borderWidths.top ?? 0
                if under.contains(t) { precondition(width == 0, "t \(t): clamped to 0, got \(width)") }
            }
        }
    }
}

/// **Fix round (`AN-AJ` item 4).** A proposal `.frame(width: 100 → 0)` under the
/// bouncy spring: no trap (a negative frame size is a kernel precondition,
/// `SA-J`), and every sampled overshoot lays the frame out 0 wide. Mutation C1.
@Test func aProposalFrameClampsAnOvershootingSpringToZero() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let h = WrapperHarness()
            @MainActor func tree(_ w: Float) -> some Element {
                Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(40))
                    .background(.accent)
            }
            h.frame(0, nil, tree(100))
            h.frame(0, bouncy, tree(0))
            let under = Set(overshootTimes(from: 100, to: 0, below: 0))
            precondition(!under.isEmpty, "the spring must overshoot")
            for t in (1...100).map({ Double($0) * 0.02 }) {
                let width = rect(h.frame(t, nil, tree(0)), height: 40)?.bounds.size.width ?? 0
                if under.contains(t) { precondition(width == 0, "t \(t): clamped to 0, got \(width)") }
            }
        }
    }
}

/// **Fix round (`AN-AJ` item 4).** A proposal `.frame(minWidth: 10 → 100,
/// maxWidth: 100)` under the bouncy spring: the interpolated minimum overshoots
/// past the fixed maximum, and the bounds are re-ordered rather than reaching
/// the kernel's `min ≤ max` precondition — every sampled overshoot lays out at
/// the maximum, 100. Mutation H (drop `ordered`'s re-ordering).
@Test func aProposalFlexibleFrameKeepsItsBoundsInOrderUnderAnOvershootingSpring() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let h = WrapperHarness()
            @MainActor func tree(_ m: Float) -> some Element {
                Rectangle(width: Pixels(10), height: Pixels(10))
                    .frame(minWidth: Pixels(m), maxWidth: Pixels(100), minHeight: Pixels(40), maxHeight: Pixels(40))
                    .background(.accent)
            }
            h.frame(0, nil, tree(10))
            h.frame(0, bouncy, tree(100))
            let over = Set(overshootTimes(from: -10, to: -100, below: -100))
            precondition(!over.isEmpty, "the spring must overshoot")
            for t in (1...100).map({ Double($0) * 0.02 }) {
                let width = rect(h.frame(t, nil, tree(100)), height: 40)?.bounds.size.width ?? 0
                if over.contains(t) { precondition(width == 100, "t \(t): held at the maximum 100, got \(width)") }
            }
        }
    }
}

// MARK: - Fix round: escapesOpacity mid-flight (AN-AJ item 3)

/// **Fix round (`AN-AJ` item 3; `LR-FW`, divergence 45 retired).** A legacy
/// background written AFTER `.opacity` stays outside the fade while the opacity
/// animates: `Box().opacity(1 → 0.2).background(.accent)` half-way under
/// `linear(1)` draws its fill at alpha 1. The control writes the fill BEFORE
/// `.opacity` and reads 0.6 half-way, so the two arms disagree. Mutation D
/// (`setInterpolatedOpacity` also empties `escapesOpacity`).
@Test @MainActor func aFillWrittenAfterAnAnimatingOpacityStaysOutsideItMidFlight() throws {
    func midAlpha(after: Bool) -> Float? {
        let h = WrapperHarness()
        func tree(_ o: Float) -> Box<EmptyGroup> {
            let box = Box().cssWidth(Pixels(50)).cssHeight(Pixels(40))
            return after ? box.opacity(o).background(.accent) : box.background(.accent).opacity(o)
        }
        h.frame(0, nil, tree(1))
        h.frame(0, linear1, tree(0.2))
        return rect(h.frame(0.5, nil, tree(0.2)), height: 40)?.background.a
    }
    let before = try #require(midAlpha(after: false), "control: a fill")
    #expect(abs(before - 0.6) < 0.001, "THE CONTROL: a fill written before .opacity fades, 0.6 half-way; got \(before)")
    let after = try #require(midAlpha(after: true), "a fill")
    #expect(after == 1, "a fill written after .opacity escapes it mid-flight, alpha 1; got \(after)")
}

// MARK: - Fix round: the lexical fallback (AN-AI item 4), one arm per copy

/// **Fix round (`AN-AI` item 4).** A headless `Frame` with no transaction of its
/// own, rendered INSIDE a `withAnimation` body, animates through the lexical
/// fallback (`pass.transaction ?? Animation.pendingTransaction`) — one arm per
/// copy: the proposal layer's `animate(for:pass:)` (a frame's width), the
/// component op's `animated(for:member:op:pass:)` (a caller's `.width`) and
/// `storedAnimatedColor` (a proposal background token). The control renders
/// the same change OUTSIDE `withAnimation` and snaps. Mutations E1/E2/E3 (drop
/// the fallback in each copy).
@Test @MainActor func aFrameRenderedInsideWithAnimationAnimatesThroughTheLexicalFallback() throws {
    // Each arm: rest, the change rendered with no frame transaction (inside or
    // outside `withAnimation`), then the half-way frame.
    func run<E: Element>(lexical: Bool, _ rest: E, _ changed: E, read: (Frame) -> Float?) -> Float? {
        let h = WrapperHarness()
        h.frame(0, nil, rest)
        if lexical {
            _ = withAnimation(.linear(duration: 1)) { h.frame(0, nil, changed) }
        } else {
            h.frame(0, nil, changed)
        }
        return read(h.frame(0.5, nil, changed))
    }
    // Copy 1: the proposal layer.
    func frameTree(_ w: Float) -> some Element {
        Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(40)).background(.accent)
    }
    let frameRead: (Frame) -> Float? = { rect($0, height: 40)?.bounds.size.width }
    #expect(run(lexical: false, frameTree(100), frameTree(300), read: frameRead) == 300, "THE CONTROL: snaps")
    #expect(run(lexical: true, frameTree(100), frameTree(300), read: frameRead) == 200,
            "copy 1, the proposal layer: 200 half-way through the lexical fallback")
    // Copy 2: a component op.
    let member = GlobalElementID.child(of: GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil),
                                                                 at: 0, name: nil), at: 0, name: nil)
    func componentTree(_ w: Float) -> some Element {
        DifferentialRoot(width: 300, height: 100) { OneMember().width(Pixels(w)) }
    }
    let memberX: (Frame) -> Float? = { $0.elementBounds[member]?.origin.x.value }
    #expect(run(lexical: false, componentTree(100), componentTree(300), read: memberX) == 140,
            "THE CONTROL: (300 − 20) / 2 = 140 at once")
    #expect(run(lexical: true, componentTree(100), componentTree(300), read: memberX) == 90,
            "copy 2, the component op: (200 − 20) / 2 = 90 half-way")
    // Copy 3: a store colour track.
    let theme = Theme.light
    func colourTree(_ token: ColorToken) -> some Element {
        Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(50), height: Pixels(40)).background(token)
    }
    let hue: (Frame) -> Float? = { rect($0, height: 40).map { hsla($0.background).l } }
    let want = lerpColour(.background, .accent, 0.5, in: theme).l
    let snapped = try #require(run(lexical: false, colourTree(.background), colourTree(.accent), read: hue))
    #expect(abs(snapped - theme[.accent].l) < 0.001, "THE CONTROL: the accent at once, got \(snapped)")
    let faded = try #require(run(lexical: true, colourTree(.background), colourTree(.accent), read: hue))
    #expect(abs(faded - want) < 0.002, "copy 3, the colour track: the half-way lightness \(want), got \(faded)")
}

// MARK: - Fix round: hover and focus border widths (AN-AJ item 1)

@Observable final class BorderWidthModel { var width: Float = 2 }

/// **Fix round (`AN-AJ` item 1).** Through a real `Window`, genuinely hovered:
/// the hover border's WIDTH 2 → 10 under a transaction reads 6 half-way.
/// Mutation F (drop the hover and focus widths from `animated()`).
@Test @MainActor func aHoverBorderAnimatesItsWidth() throws {
    let model = BorderWidthModel()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 100, startsDisplayLink: true) {
        Box().cssWidth(Pixels(40)).cssHeight(Pixels(40))
            .border(.background, width: Pixels(1))
            .hoverBorder(.accent, width: Pixels(model.width))
            .onClick {}
    }
    platform.simulateTick(timestamp: 100)
    _ = platform.simulateInput(.mouseMoved(MouseEvent(position: Point(x: Pixels(50), y: Pixels(50)))))
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 100.05)
    func width() -> Float? { window.lastScene.rects.first { $0.borderColor.a > 0 }?.borderWidths.top }
    try #require(width() == 2, "set up: hovered, the hover border's width 2 is drawn, got \(String(describing: width()))")
    withAnimation(.linear(duration: 1)) { model.width = 10 }
    platform.simulateTick(timestamp: 100.2)
    platform.simulateTick(timestamp: 100.7)
    #expect(width() == 6, "half-way the hover border is 6 wide, got \(String(describing: width()))")
    platform.simulateTick(timestamp: 101.3)
    #expect(width() == 10, "lands at 10")
}

/// **Fix round (`AN-AJ` item 1).** The focus ring's WIDTH 2 → 10 under a
/// transaction reads 6 half-way while the box is focused. Mutation F.
@Test @MainActor func aFocusRingAnimatesItsWidth() throws {
    let model = BorderWidthModel()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 100, startsDisplayLink: true) {
        Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).focusable()
            .focusBorder(.accent, width: Pixels(model.width))
    }
    platform.simulateTick(timestamp: 100)
    let id = GlobalElementID.child(of: nil, at: 0, name: nil)
    window.focus(id)
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 100.05)
    try #require(window.focusedElement == id, "set up: the box takes focus")
    func width() -> Float? { window.lastScene.rects.first { $0.borderColor.a > 0 }?.borderWidths.top }
    try #require(width() == 2, "set up: the ring is 2 wide, got \(String(describing: width()))")
    withAnimation(.linear(duration: 1)) { model.width = 10 }
    platform.simulateTick(timestamp: 100.2)
    platform.simulateTick(timestamp: 100.7)
    #expect(width() == 6, "half-way the focus ring is 6 wide, got \(String(describing: width()))")
    platform.simulateTick(timestamp: 101.3)
    #expect(width() == 10, "lands at 10")
}

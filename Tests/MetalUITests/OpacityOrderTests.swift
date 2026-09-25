import Testing
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

// Lane 3 of plan task 7 stage 11 (spec
// `docs/superpowers/specs/2026-09-25-engine-stage-11-design.md` §4, §7 lane 3;
// ruling `LR-FW` as amended by `LR-GA` items 1–2): **whatever is written after
// `.opacity` is outside it, on both paths** — probe
// `docs/probes/swiftui-border-clip-paint.swift` arms G3, G4 and group H (H1, H2,
// H3), re-run 2026-09-24, output in its header.
//
// The exit criterion of the parent spec's §4.1 row 11 reads "the outer-modifier-
// order probe's G3/G4 arms … through the unified type"; G3/G4 are the
// border-clip-paint probe's arms (`LR-FY` item 4), and N2.1 below runs them —
// with group H — through a `ModifiedContent<Box<EmptyGroup>, ModifierLayer>`
// and a `ModifiedContent<Rectangle, LayoutModifier>`, the one flat type's two
// vocabularies (`LR-FV`).
//
// Every alpha is read off the emitted rect: `Frame.fill` multiplies both the
// fill's and the border's alpha by `activeOpacity` on the way into the scene,
// so the alpha IS the scope composition, exactly.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func why(_ message: String) -> Comment { "\(message)" }

/// Renders `make` in a fresh `side`×`side` fake window and returns it.
@MainActor
private func render<E: Element>(side: Int = 100,
                                _ make: @escaping @MainActor () -> E) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: side, content: make)
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// The one rect whose bounds are `w`×`h`, found by size so a child's own fill
/// (the proposal arms' 36×36 `Rectangle`) is never mistaken for the subject.
private func sizedRect(_ scene: Scene, _ w: Float, _ h: Float) throws -> MUIRect {
    let matches = scene.rects.filter { $0.bounds.size.width == w && $0.bounds.size.height == h }
    try #require(matches.count == 1,
                 why("expected exactly one \(w)x\(h) rect, got \(matches.count) of "
                     + "\(scene.rects.count)"))
    return matches[0]
}

/// The 40×40 subject's fill alpha.
@MainActor
private func fill<E: Element>(_ make: @escaping @MainActor () -> E) throws -> Float {
    let (window, _) = try render(make)
    let subject = try sizedRect(window.lastScene, 40, 40)
    return subject.background.a
}

/// The 40×40 subject's border alpha.
@MainActor
private func ring<E: Element>(_ make: @escaping @MainActor () -> E) throws -> Float {
    let (window, _) = try render(make)
    let subject = try sizedRect(window.lastScene, 40, 40)
    return subject.borderColor.a
}

// MARK: - N2.1 (exit)

/// **N2.1 — stage 11's exit test for the opacity order** (`LR-FW` item 3,
/// `OM-AA` a closed). Probe arms G3, G4, H1, H2 and H3, each written twice:
///
/// - **legacy**, annotated `ModifiedContent<Box<EmptyGroup>, ModifierLayer>`: a
///   36×36 `Box`, `.padding(Pixels(2))` first (so the decorated layer is the
///   40×40 padding layer of the unified chain, not the `Box`'s own decoration);
/// - **proposal**, annotated `ModifiedContent<Rectangle, LayoutModifier>`: a
///   36×36 `Rectangle`, `.padding(Edges(all: 2))` first, each modifier its own
///   layer.
///
/// Per arm the two paths' alphas are **equal** (H3 compares the **fill** only:
/// its content differs by divergence 46, `OM-AH`, which this stage keeps), and
/// per path the order arms **disagree** (G3 ≠ G4, H1 ≠ H2) — shape 15, so
/// "equal" cannot be satisfied by two paths that both ignore the order.
///
/// Red before: does not compile at `47c0d98` (the unified type is lane 1's);
/// at lane 2's head the legacy G4 and H2 arms read `0.5 ×` where the proposal
/// ones read full. Mutations that must redden it: **M2a** (`.background`
/// stops inserting its member → legacy G4), **M2d** (the border members
/// ignored → legacy H2), **M2h** (`LayoutModifier`'s `.opacity` arm paints its
/// content outside the scope → proposal G3, H1).
@Test @MainActor func theOpacityOrderAnswersTheSameOnBothPathsThroughTheUnifiedType() throws {
    typealias Legacy = ModifiedContent<Box<EmptyGroup>, ModifierLayer>
    typealias Proposal = ModifiedContent<Rectangle, LayoutModifier>

    func legacyBase() -> Legacy { Box().cssWidth(px(36)).cssHeight(px(36)).padding(Pixels(2)) }
    func proposalBase() -> Proposal {
        Rectangle(width: px(36), height: px(36)).padding(Edges(all: px(2)))
    }

    struct Path { var g3, g4, h1, h2, h3: Float }

    let legacyG3: Legacy = legacyBase().background(.accent).opacity(0.5)
    let legacyG4: Legacy = legacyBase().opacity(0.5).background(.accent)
    let legacyH1: Legacy = legacyBase().border(.separator, width: px(4)).opacity(0.5)
    let legacyH2: Legacy = legacyBase().opacity(0.5).border(.separator, width: px(4))
    let legacyH3: Legacy = legacyBase().opacity(0.5).background(.accent).opacity(0.5)
    let legacy = Path(g3: try fill { legacyG3 }, g4: try fill { legacyG4 },
                      h1: try ring { legacyH1 }, h2: try ring { legacyH2 },
                      h3: try fill { legacyH3 })

    let proposalG3: Proposal = proposalBase().background(.accent).opacity(0.5)
    let proposalG4: Proposal = proposalBase().opacity(0.5).background(.accent)
    let proposalH1: Proposal = proposalBase().border(.separator, width: px(4)).opacity(0.5)
    let proposalH2: Proposal = proposalBase().opacity(0.5).border(.separator, width: px(4))
    let proposalH3: Proposal = proposalBase().opacity(0.5).background(.accent).opacity(0.5)
    let proposal = Path(g3: try fill { proposalG3 }, g4: try fill { proposalG4 },
                        h1: try ring { proposalH1 }, h2: try ring { proposalH2 },
                        h3: try fill { proposalH3 })

    for (name, path) in [("legacy", legacy), ("proposal", proposal)] {
        try #require(abs(path.g3 - path.g4) > 0.001,
                     why("\(name): set up — G3 and G4 must disagree: \(path.g3) vs \(path.g4)"))
        try #require(abs(path.h1 - path.h2) > 0.001,
                     why("\(name): set up — H1 and H2 must disagree: \(path.h1) vs \(path.h2)"))
        #expect(path.g3 < path.g4 && path.h1 < path.h2,
                why("\(name): the modifier written BEFORE `.opacity` is the faded one (G3, H1); "
                    + "got G3 \(path.g3) G4 \(path.g4) H1 \(path.h1) H2 \(path.h2)"))
    }
    #expect(legacy.g3 == proposal.g3, why("G3: legacy \(legacy.g3), proposal \(proposal.g3)"))
    #expect(legacy.g4 == proposal.g4, why("G4: legacy \(legacy.g4), proposal \(proposal.g4)"))
    #expect(legacy.h1 == proposal.h1, why("H1: legacy \(legacy.h1), proposal \(proposal.h1)"))
    #expect(legacy.h2 == proposal.h2, why("H2: legacy \(legacy.h2), proposal \(proposal.h2)"))
    #expect(legacy.h3 == proposal.h3, why("H3 (the fill): legacy \(legacy.h3), proposal \(proposal.h3)"))
    #expect(abs(legacy.h3 - legacy.g3) < 0.001,
            why("H3 fades the fill ONCE, as G3 does (probe H3 reads G3's value): "
                + "H3 \(legacy.h3), G3 \(legacy.g3)"))
}

// MARK: - N2.4

/// **N2.4** (`LR-GA` items 1–2). The escape is **per slot**, and only the slot
/// that won the pointer-state resolution decides:
///
/// 1. `Box().background(.accent).opacity(0.5).hoverBackground(.separator)` —
///    unhovered, the plain fill (written BEFORE the opacity) resolves and reads
///    `0.5 × a`, inside the scope (probe G3); hovered, the hover fill (written
///    AFTER) resolves and reads `a`, outside it (G4). The design's one `Bool`
///    per decoration would have let the hover write push the unhovered fill out.
/// 2. The border twin, `Box().border(.accent, 2).opacity(0.5)
///    .focusBorder(.separator, 2).focusable()`: unfocused faded, focused full.
///    (`.onClick {}` as well, only so the element's id can be read off its
///    hitbox for `Window.focus(_:)`, as `BorderSubject` does.)
/// 3. `Box().background(x).decoration == Decoration(background: x)` — a write
///    with no opacity before it records nothing, so decorations built without
///    an opacity compare equal (and `ModifierTests`' one-field table stays green
///    unedited).
///
/// Red before: the hovered and focused arms read `0.5 ×` at lane 2's head.
/// Mutations that must redden it: **M2i** one member for all three fill slots
/// (arm 1 unhovered escapes); **M2j** the `opacity < 1` condition dropped (arm
/// 3, and `ModifierTests`' one-field table).
@Test @MainActor func aHoverOrFocusFillWrittenAfterOpacityEscapesOnlyWhileItIsTheResolvedOne() throws {
    // 1. hover fill.
    do {
        let (window, platform) = try render {
            Box().cssWidth(px(40)).cssHeight(px(40))
                .background(.accent).opacity(0.5).hoverBackground(.separator).onClick {}
        }
        let theme = window.theme
        try #require(theme[.accent].a > 0 && theme[.separator].a > 0, "set up — visible tokens")
        let resting = try sizedRect(window.lastScene, 40, 40).background
        #expect(abs(resting.a - theme[.accent].a * 0.5) < 0.001,
                why("unhovered: the plain fill was written BEFORE `.opacity` and is inside it "
                    + "(G3) — expected \(theme[.accent].a * 0.5), got \(resting.a)"))

        let hitboxes = window.lastHitboxes
        try #require(hitboxes.count == 1, "set up — onClick registers exactly one hitbox")
        let b = hitboxes[0].bounds
        platform.simulateInput(.mouseMoved(MouseEvent(position: Point(
            x: b.origin.x + Pixels(b.size.width.value / 2),
            y: b.origin.y + Pixels(b.size.height.value / 2)))))
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        let hovered = try sizedRect(window.lastScene, 40, 40).background
        try #require(hovered.h == theme[.separator].h && hovered.l == theme[.separator].l,
                     why("set up — hovered, the hover fill must be the one painted; got \(hovered)"))
        #expect(abs(hovered.a - theme[.separator].a) < 0.001,
                why("hovered: the hover fill was written AFTER `.opacity` and escapes it (G4) — "
                    + "expected \(theme[.separator].a), got \(hovered.a)"))
    }

    // 2. focus border.
    do {
        let (window, _) = try render {
            Box().cssWidth(px(40)).cssHeight(px(40))
                .border(.accent, width: px(2)).opacity(0.5).focusBorder(.separator, width: px(2))
                .focusable().onClick {}
        }
        let theme = window.theme
        let resting = try sizedRect(window.lastScene, 40, 40).borderColor
        #expect(abs(resting.a - theme[.accent].a * 0.5) < 0.001,
                why("unfocused: the plain border was written BEFORE `.opacity` and is inside it "
                    + "(H1) — expected \(theme[.accent].a * 0.5), got \(resting.a)"))

        let hitboxes = window.lastHitboxes
        try #require(hitboxes.count == 1, "set up — one hitbox")
        window.focus(hitboxes[0].id)
        window.drawFrameIfNeeded()
        let focused = try sizedRect(window.lastScene, 40, 40).borderColor
        try #require(focused.h == theme[.separator].h && focused.l == theme[.separator].l,
                     why("set up — focused, the focus ring must be the one drawn; got \(focused)"))
        #expect(abs(focused.a - theme[.separator].a) < 0.001,
                why("focused: the focus ring was written AFTER `.opacity` and escapes it (H2) — "
                    + "expected \(theme[.separator].a), got \(focused.a)"))
    }

    // 3. no opacity, nothing recorded.
    #expect(Box().background(.accent).decoration == Decoration(background: .accent),
            "a background written with no opacity before it records nothing")
    #expect(Box().border(.accent, width: px(2)).focusBorder(.separator, width: px(2)).decoration
                == Decoration(border: BorderStyle(.accent, width: px(2)),
                              focusBorder: BorderStyle(.separator, width: px(2))),
            "a border written with no opacity before it records nothing")
}

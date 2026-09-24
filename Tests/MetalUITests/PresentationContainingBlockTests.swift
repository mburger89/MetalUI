import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 9 of the engine replacement — **lane 3**, the deletion
// (spec `docs/superpowers/specs/2026-09-24-engine-stage-9-design.md` §6 lane 3,
// rulings `LR-FF`, `LR-FH` item 5; record §51 §3 and lane 3's section).
//
// Until stage 9 a presentation whose **legacy** containing block was not the
// window — a bordered root, a root narrower or wider than the window, a
// `Deferred` root, a presentation nested in another that does not cover the
// window's padding box — was reported by name (`deferred.containingBlock`,
// `deferred.root`, `deferred.nested`, `LR-CL`, owner 9) rather than laid out,
// because the legacy engine would have placed it against that other box. Stage 9
// deletes the legacy engine, and with it the condition those reports protected:
// a presentation's containing block is the window whatever surrounds it — the
// answer `LR-CL`'s construction already gave the auto root (record §51 §3
// measured every arm at it with the reports removed). `deferred.amended` is
// **kept**, re-owned to stage 11 (`LR-FF`): deleting it drops a
// `Component.width` over a presentation member silently.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func dim(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }
private func cbBounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}
private func cbInsets(top: MetalUICore.Dimension = .auto, right: MetalUICore.Dimension = .auto,
                      bottom: MetalUICore.Dimension = .auto,
                      left: MetalUICore.Dimension = .auto) -> Edges<MetalUICore.Dimension> {
    Edges(top: top, right: right, bottom: bottom, left: left)
}

/// `PresentationLoweringTests`' presented content: a 10×10 painted, clickable
/// absolute box at the right/bottom 5-point insets, inside a `Deferred`. Against
/// a 200×100 window it sits at (185, 85).
@MainActor
private func cbPresented() -> Deferred<Box<EmptyGroup>> {
    Deferred {
        Box().background(.accent).onClick {}.position(.absolute)
            .inset(cbInsets(right: dim(5), bottom: dim(5))).cssWidth(px(10)).cssHeight(px(10))
    }
}

/// A `Component` whose one member is a `Deferred` over a top/left-5 10×10
/// absolute box — `PresentationLoweringTests`' `PresentingSolo`.
private struct CBPresentingSolo: Component {
    var content: some ElementGroup {
        Deferred {
            Box().background(.accent).onClick {}.position(.absolute)
                .inset(cbInsets(top: dim(5), left: dim(5))).cssWidth(px(10)).cssHeight(px(10))
        }
    }
}

/// `make()` rendered **as the root** of a plain 200×100 `Frame` with diagnostics
/// on: what it reported, and every hitbox's rect.
@MainActor
private func renderAsRoot<E: Element>(_ make: () -> E) -> (fields: [UnlowerableField], hitboxes: [Bounds<Pixels>]) {
    var root = make()
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                      reportsUnlowerableFields: true)
    frame.render(&root)
    return (frame.unlowerableFields, frame.hitboxes.map(\.bounds))
}

/// **N3.1** (`LR-FF`; record §51 §3). The seven trees whose legacy containing
/// block was not the window — each rendered as the root of a plain 200×100
/// `Frame` with diagnostics — lay the presented box out against the window: its
/// hitbox (the only one in each tree; the outer presentations of the two nested
/// arms carry no `onClick`) is **(185, 85) 10×10**, and nothing is reported. Plus
/// the amended arm: `Box { CBPresentingSolo().width(70) }` still reports exactly
/// `deferred.amended`, now owned by stage **11**.
///
/// Red before (at lane 2's head `a84db27`): the five root arms report
/// `deferred.containingBlock` (four) or `deferred.root` (the `Deferred` root),
/// the two nested arms `deferred.nested`, and the amended field's owner reads "9".
///
/// Mutations that must redden it: **M3a** the `reportPresentationContainingBlock`
/// call restored → the five root arms; **M3b** `Deferred`'s nested report
/// restored → the two nested arms; **M3c** `.deferred`'s `owningStage` back to "9"
/// → the amended arm.
@MainActor
@Test func aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt() throws {
    var bordered = Style()
    bordered.border = Edges(all: .pixels(px(4)))
    var borderedCover = Style()
    borderedCover.border = Edges(all: .pixels(px(3)))

    typealias Arm = (name: String, fields: [UnlowerableField], hitboxes: [Bounds<Pixels>])
    var arms: [Arm] = []
    func arm<E: Element>(_ name: String, _ make: () -> E) {
        let r = renderAsRoot(make)
        arms.append((name, r.fields, r.hitboxes))
    }
    arm("bordered root") { Box(style: bordered) { cbPresented() } }
    arm("root width 100 in 200") { Box { cbPresented() }.cssWidth(px(100)) }
    arm("Deferred root") { cbPresented() }
    arm("inside a top/left-5 presentation") {
        Box {
            Deferred {
                Box { cbPresented() }.background(.surface).position(.absolute)
                    .inset(cbInsets(top: dim(5), left: dim(5)))
            }
        }
    }
    arm("root .frame(maxWidth: 100)") { Box { cbPresented() }.frame(maxWidth: px(100)) }
    arm("root .frame(minWidth: 300)") { Box { cbPresented() }.frame(minWidth: px(300)) }
    arm("inside a bordered inset(0) presentation") {
        Box {
            Deferred {
                Box(style: borderedCover) { cbPresented() }.background(.surface).position(.absolute).inset(px(0))
            }
        }
    }
    try #require(arms.count == 7)
    for arm in arms {
        #expect(arm.fields.isEmpty, "\(arm.name): reported \(arm.fields.map(\.description))")
        #expect(arm.hitboxes == [cbBounds(185, 85, 10, 10)], "\(arm.name): hitboxes \(arm.hitboxes)")
    }

    let amended = renderAsRoot { Box { CBPresentingSolo().width(px(70)) } }
    #expect(amended.fields.map(\.description) == ["deferred.amended"], "\(amended.fields)")
    for field in amended.fields {
        #expect(field.owningStage == "11", "\(field) is owned by stage \(field.owningStage)")
    }
}

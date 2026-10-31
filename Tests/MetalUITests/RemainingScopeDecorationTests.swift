import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// `ES-D`, `ES-E`: the remaining transparent scopes that forward a decoration written after them (transition,
// glass tags). Each arm writes the decoration after the scope and compares it with the same decoration written
// before, SwiftUI's two orders, which agree for these scopes. The two refused scopes (`ES-F` coordinate space,
// `ES-G` transaction) were measured here with a temporary conformance and disagree (record 168); their pins are
// the plain-import negatives in `ScopeDecorationCompileGuards.swift`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let linear1 = Animation.linear(duration: 1)

// MARK: - TransitionGroup

@MainActor private func isAccentRect(_ c: MUIHsla) -> Bool {
    let accent = Theme.light[.accent]
    return abs(c.h - accent.h) < 0.001 && abs(c.s - accent.s) < 0.001 && abs(c.l - accent.l) < 0.001
}

/// The stage of `TransitionTests`: a 200 × 100 box fixing the container, and a 50 × 30 accent tile under
/// `if shown` with its background written after `.transition(.opacity)`.
@MainActor private func stageAfter(_ shown: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown { Box().frame(width: px(50), height: px(30)).transition(.opacity).background(.accent) }
        }
    }
}

/// The same with the background written before (the control: the tile's own background).
@MainActor private func stageBefore(_ shown: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown { Box().frame(width: px(50), height: px(30)).background(.accent).transition(.opacity) }
        }
    }
}

/// The accent tile's alpha half-way through an insertion under `linear(1)`, and settled.
@MainActor private func midAlpha<E: Element>(_ stage: (Bool) -> E) -> (mid: Float?, end: Float?) {
    let h = TransitionHarness()
    h.frame(0, nil, stage(false))
    h.frame(0, linear1, stage(true))
    let mid = h.frame(0.5, nil, stage(true)).scene.rects.first { isAccentRect($0.background) }
    let end = h.frame(2, nil, stage(true)).scene.rects.first { isAccentRect($0.background) }
    return (mid?.background.a, end?.background.a)
}

/// **ES-E.** A background written after `.transition(.opacity)` fades in with the tile: alpha ½ half-way through
/// a `linear(1)` insertion, 1 settled, exactly as the background written before (the control). Mutation: the
/// `TransitionGroup` `decoration` setter drops the write (the after arm paints no accent rect).
@MainActor @Test func aBackgroundAfterATransitionTransitionsWithTheContent() throws {
    let after = midAlpha(stageAfter)
    let before = midAlpha(stageBefore)
    try #require(before.mid == 0.5 && before.end == 1, "control: the background before fades: \(before)")
    #expect(after.mid == 0.5 && after.end == 1, "after: \(after)")
}

/// **ES-E.** On the `Element` path (the transition as a window's root) nothing inserts it, so it is inert: the tile
/// and its background after the transition paint at full alpha on the first frame.
@MainActor @Test func aTransitionAtTheRootIsInertAndKeepsItsDecoration() throws {
    let frame = effectFrame(Box().frame(width: px(50), height: px(30)).transition(.opacity).background(.accent))
    let tile = frame.scene.rects.first { isAccentRect($0.background) }
    #expect(tile?.background.a == 1, "\(String(describing: tile))")
}

// MARK: - GlassTagScope

private func records(_ scene: Scene) -> [Int] { scene.backdrops.map(\.glassMemberCount) }

/// Two 60-point glass circles 120 apart in a default container, inside a legacy `Box`: apart unless a union tag
/// joins them (`LG-H`: a union merges regardless of distance).
@MainActor private func glassPair() -> some StyledElement {
    Box {
        GlassEffectContainer {
            HStack(spacing: px(120)) {
                Color.clear.frame(width: px(60), height: px(60)).glassEffect(in: Circle())
                Color.clear.frame(width: px(60), height: px(60)).glassEffect(in: Circle())
            }
        }
    }
}

/// **ES-D.** A union tag over a legacy element, followed by a decoration, still tags the glass inside: one record
/// of two members, in a container (the group path) and as the frame's root (the `Element` path); without the tag
/// the two stay apart (the control). Mutation: drop the `glassTags` push in `GlassTagScope.prepaint(_:bounds:layout:pass:)`
/// (the root arm reads `[1, 1]`).
@MainActor @Test func aGlassUnionTagKeepsTaggingWithADecorationAfterIt() throws {
    let ns = Namespace.ID(owner: nil)
    let apart = records(effectFrame(Column { glassPair() }, side: 600).finalizedScene())
    try #require(apart == [1, 1], "control: untagged circles 120 apart stay two: \(apart)")
    let grouped = records(effectFrame(Column {
        glassPair().glassEffectUnion(id: "u", namespace: ns).accessibilityIdentifier("g")
    }, side: 600).finalizedScene())
    #expect(grouped == [2], "in a container: \(grouped)")
    let root = records(effectFrame(glassPair().glassEffectUnion(id: "u", namespace: ns).accessibilityIdentifier("r"),
                                   side: 600).finalizedScene())
    #expect(root == [2], "as the root: \(root)")
}

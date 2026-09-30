import Testing
import Observation
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// Plan task 13, lane 1 — `Transaction`, `withTransaction`, `.animation(_:value:)`,
// `.transaction(_:)`, `Binding.animation`/`.transaction` and the window
// registry's prune (rulings `AN-Y`, `AN-Z`, `AN-AF` item 8). Spec
// `docs/superpowers/specs/2026-09-30-transactions-animation-design.md` §6.1,
// §6.2, tests 1.1–1.12 and 1.19; SwiftUI's side is
// `docs/probes/swiftui-transactions-animation.swift`, arms T1–T13.
//
// **Every test drives a real `Window` by timestamps** (`simulateTick`), never
// a sleep: the write happens outside the build, the build is a separate tick,
// and a mid-flight value is read off the scene. A linear second from 100 to
// 200 reads 150 at its halfway point, and only a running animation produces
// that number.

// MARK: - Fixtures

@Observable
final class TransactionModel {
    var width: Float = 100
    var other: Float = 100
    var flag = 0
    var flag2 = 0
    var useAccent = false
}

/// What each recorder saw, by label: the transaction's animation at layout
/// and at paint, and the environment's Reduce Motion at layout.
@MainActor
final class TransactionLog {
    var layout: [String: Animation?] = [:]
    var paint: [String: Animation?] = [:]
    var reduceMotion: [String: Bool] = [:]
}

/// A 10 × 10 proposal leaf that records `pass.transaction` in layout and
/// paint. A `ProposalElement`, so it sits in a legacy container (the untyped
/// entry) and in a proposal stack (the typed entry) alike.
struct TransactionRecorder: ProposalElement {
    let label: String
    let log: TransactionLog

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        log.layout[label] = .some(pass.transaction)
        log.reduceMotion[label] = pass.environment.accessibilityReduceMotion
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.paint[label] = .some(pass.transaction)
    }
}

/// The width of the one rect the scene paints at `height` — each fixture gives
/// its subjects distinct heights so they can be told apart. The fake surface's
/// scale factor is 1, so device pixels are points.
@MainActor func transactionRectWidth(_ window: Window, height: Float) -> Float? {
    window.lastScene.rects.first { $0.bounds.size.height == height }?.bounds.size.width
}

@MainActor func transactionRectColour(_ window: Window, height: Float) -> Hsla? {
    guard let rect = window.lastScene.rects.first(where: { $0.bounds.size.height == height }) else {
        return nil
    }
    return Hsla(h: rect.background.h, s: rect.background.s, l: rect.background.l, a: rect.background.a)
}

@MainActor private func makeTransactionWindow<Root: Element>(
    _ content: @escaping @MainActor () -> Root
) throws -> (Window, FakePlatformWindow) {
    try makeFakeWindowOnDefaultDevice(size: 300, startsDisplayLink: true, content: content)
}

/// A sized, painted legacy box: `width` wide, `height` tall, background token
/// `token` — the subject every width arm reads.
@MainActor private func subject(_ width: Float, _ height: Float,
                                _ token: ColorToken = .accent) -> some ElementGroup {
    Box().background(token).cssWidth(Pixels(width)).cssHeight(Pixels(height))
}

// MARK: - 1.1, 1.2: withTransaction (T5, T5n)

/// **1.1 (T5).** `withTransaction(Transaction(animation: linear(1)))` whose body
/// writes the width animates exactly as `withAnimation` does: 150 at 0.5 s.
/// Mutation **M1.1**: `withTransaction` parks `nil`.
@MainActor @Test func withTransactionAnimatesAChangeAsWithAnimationDoes() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column { subject(model.width, 40) }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100, "set up: the resting width")

    withTransaction(Transaction(animation: .linear(duration: 1))) { model.width = 200 }
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "withTransaction(linear 1) is withAnimation(linear 1): 150 at 0.5 s; 200 is a snap")
    platform.simulateTick(timestamp: 101.1)
    #expect(transactionRectWidth(window, height: 40) == 200)

    // withTransaction returns its body's result and rethrows (SwiftUI's signature).
    let answer = withTransaction(Transaction()) { 42 }
    #expect(answer == 42)
}

/// **1.2 (T5n).** A transaction whose animation is `nil` snaps — through
/// `withTransaction(Transaction(animation: nil))` and through
/// `withAnimation(nil)`. Mutation **M1.2**: a `nil` animation parks `.default`.
@MainActor @Test func aTransactionWithNoAnimationSnaps() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column { subject(model.width, 40) }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)

    withTransaction(Transaction(animation: nil)) { model.width = 200 }
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.2)
    #expect(transactionRectWidth(window, height: 40) == 200,
            "Transaction(animation: nil) snaps (T5n)")
    #expect(!window.hasActiveAnimations)

    withAnimation(nil) { model.width = 100 }
    platform.simulateTick(timestamp: 101)
    platform.simulateTick(timestamp: 101.1)
    #expect(transactionRectWidth(window, height: 40) == 100, "withAnimation(nil) snaps")
    #expect(!window.hasActiveAnimations)

    // Control: the same shape with an animation does animate, so the two nils
    // above are about the nil and not about the fixture.
    withAnimation(.linear(duration: 1)) { model.width = 200 }
    platform.simulateTick(timestamp: 102)
    platform.simulateTick(timestamp: 102.5)
    #expect(transactionRectWidth(window, height: 40) == 150, "control: an animation animates")
}

// MARK: - 1.3–1.8: .animation(_:value:) and .transaction(_:) (T1–T8)

/// **1.3 (T1, T2).** `.animation(linear(1), value: flag)` animates a change when
/// `flag` changed in the same frame, with no `withAnimation` anywhere (T1), and a
/// change of anything else under it snaps (T2). A first sighting stores and
/// does not animate. Mutation **M1.3**: drop the value comparison (always push
/// the animation) — the T2 arm.
@MainActor @Test func anAnimationModifierAnimatesOnlyWhenItsValueChanges() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40).animation(.linear(duration: 1), value: model.flag)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)

    // T1: the value and the width change together.
    model.flag = 1
    model.width = 200
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "T1: a changed value animates the change under it with no withAnimation")
    platform.simulateTick(timestamp: 101.1)
    try #require(transactionRectWidth(window, height: 40) == 200)

    // T2: the width alone changes; the value does not.
    model.width = 100
    platform.simulateTick(timestamp: 102)
    #expect(transactionRectWidth(window, height: 40) == 100,
            "T2: a change of anything else under the modifier snaps")
    #expect(!window.hasActiveAnimations)
}

/// **1.3b.** A first sighting stores and does not animate — reached where the
/// scope's stored value is gone but its content's `$anim` baseline survives
/// (a `List` row returning into its window has this shape: its store entry
/// dropped after one frame, its `$anim` kept by `TB-AH`). The store is
/// emptied directly here (`endFrame()` outside a frame drops every untouched
/// entry). Mutation **V1** (`?? false` → `?? true` in `Frame.scopedTransaction`).
@MainActor @Test func anAnimationScopesFirstSightingSnapsOverASurvivingBaseline() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40).animation(.linear(duration: 1), value: model.flag)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)
    try #require(window.animationStore.count == 1, "set up: the scope stored its value")
    window.animationStore.endFrame()
    try #require(window.animationStore.count == 0, "set up: the stored value is gone")

    model.flag = 1
    model.width = 200
    platform.simulateTick(timestamp: 101)
    platform.simulateTick(timestamp: 101.5)
    #expect(transactionRectWidth(window, height: 40) == 200,
            "a first sighting stores and does not animate, even over a surviving $anim baseline")
    #expect(!window.hasActiveAnimations)
    #expect(window.animationStore.count == 1, "and it stored the value it saw")
}

/// **1.4 (T3, T3b).** The modifier reaches only its content: a sibling snaps,
/// and a modifier written after it is outside it (`EV-X`). Legacy arm (the
/// untyped entry, in a `Column`) and proposal arm (the typed entry, in an
/// `HStack`). Mutations **M1.4a**: never pop the pushed transaction — the
/// sibling arm; **M1.4b**: skip the typed entry's push — the proposal arm.
@MainActor @Test func anAnimationModifierReachesOnlyItsContent() throws {
    let model = TransactionModel()
    let log = TransactionLog()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40).animation(.linear(duration: 1), value: model.flag)
            subject(model.other, 41)
            TransactionRecorder(label: "legacy-in", log: log)
                .animation(.linear(duration: 1), value: model.flag)
            TransactionRecorder(label: "legacy-out", log: log)
            // T3b: a frame layer written AFTER the modifier is outside it.
            TransactionRecorder(label: "after", log: log)
                .animation(.linear(duration: 1), value: model.flag)
                .frame(width: Pixels(model.other), height: Pixels(42))
                .background(.accent)
            HStack(spacing: Pixels(0)) {
                TransactionRecorder(label: "proposal-in", log: log)
                    .animation(.linear(duration: 1), value: model.flag)
                TransactionRecorder(label: "proposal-out", log: log)
            }
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)
    try #require(transactionRectWidth(window, height: 41) == 100)

    model.flag = 1
    model.width = 200
    model.other = 200
    platform.simulateTick(timestamp: 100.1)
    // The recorders' own reading of the frame that changed the value.
    #expect(log.layout["legacy-in"] == .some(.linear(duration: 1)),
            "the content sees the pushed animation in layout (untyped entry)")
    #expect(log.paint["legacy-in"] == .some(.linear(duration: 1)), "and in paint")
    #expect(log.layout["legacy-out"] == .some(nil), "a sibling does not (T3)")
    #expect(log.paint["legacy-out"] == .some(nil), "not in paint either")
    #expect(log.layout["proposal-in"] == .some(.linear(duration: 1)),
            "the typed entry pushes too (a proposal stack's content)")
    #expect(log.paint["proposal-in"] == .some(.linear(duration: 1)))
    #expect(log.layout["proposal-out"] == .some(nil), "a proposal sibling does not")

    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 150, "the content animates")
    #expect(transactionRectWidth(window, height: 41) == 200, "a sibling snaps (T3)")
    #expect(transactionRectWidth(window, height: 42) == 200,
            "a modifier written after the scope is outside it and snaps (T3b)")
}

/// **1.5 (T4, T4n).** Inside `withAnimation(linear(4))`, `.animation(linear(1),
/// value:)` overrides its content to linear(1) — a sibling keeps linear(4) —
/// and `.animation(nil, value:)` snaps. Mutation **M1.5**: keep the explicit
/// animation when the root has one.
@MainActor @Test func anAnimationModifierOverridesTheExplicitTransaction() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40).animation(.linear(duration: 1), value: model.flag)
            subject(model.width, 41).animation(nil, value: model.flag)
            subject(model.width, 42)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)

    withAnimation(.linear(duration: 4)) {
        model.flag = 1
        model.width = 200
    }
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "T4: the modifier's linear(1) overrides withAnimation's linear(4)")
    #expect(transactionRectWidth(window, height: 41) == 200,
            "T4n: .animation(nil, value:) snaps inside withAnimation")
    platform.simulateTick(timestamp: 101.1)
    #expect(transactionRectWidth(window, height: 42) == 125,
            "the sibling keeps the explicit linear(4): 125 at 1 s")
}

/// **1.6 (T8, T8b, T8c).** `disablesAnimations` suppresses `.animation(_:value:)`
/// and never the explicit animation: under a parked transaction with
/// `disablesAnimations` and linear(4), the modifier's linear(1) is suppressed and
/// linear(4) still applies (T8); with no animation, nothing (T8b); and a
/// `.transaction { $0.disablesAnimations = true }` leaves `withAnimation`'s
/// animation alone (T8c). Mutations **M1.6a**: ignore `disablesAnimations` (T8,
/// T8b arms); **M1.6b**: let it also clear the explicit animation (T8c arm).
@MainActor @Test func disablesAnimationsSuppressesOnlyTheAnimationModifier() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40).animation(.linear(duration: 1), value: model.flag)
            subject(model.other, 41).transaction { $0.disablesAnimations = true }
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)

    // T8: linear(4) with disablesAnimations; the modifier's linear(1) is suppressed.
    var t8 = Transaction(animation: .linear(duration: 4))
    t8.disablesAnimations = true
    withTransaction(t8) {
        model.flag = 1
        model.width = 200
    }
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 101.1)
    #expect(transactionRectWidth(window, height: 40) == 125,
            "T8: disablesAnimations suppresses .animation(_:value:); the explicit linear(4) applies (125 at 1 s)")
    platform.simulateTick(timestamp: 104.1)
    try #require(transactionRectWidth(window, height: 40) == 200)

    // T8b: no animation at all, disablesAnimations: the modifier animates nothing.
    var t8b = Transaction()
    t8b.disablesAnimations = true
    withTransaction(t8b) {
        model.flag = 2
        model.width = 100
    }
    platform.simulateTick(timestamp: 105)
    #expect(transactionRectWidth(window, height: 40) == 100,
            "T8b: with disablesAnimations and no animation, a changed value snaps")

    // T8c: `.transaction { disablesAnimations = true }` never clears the explicit animation.
    withAnimation(.linear(duration: 1)) { model.other = 200 }
    platform.simulateTick(timestamp: 106)
    platform.simulateTick(timestamp: 106.5)
    #expect(transactionRectWidth(window, height: 41) == 150,
            "T8c: disablesAnimations does not suppress the explicit animation")
}

/// **1.6b.** A parked `disablesAnimations` is used by exactly ONE build and
/// is rolled back beside its animation (`AN-AI` item 1): (a) a
/// `withTransaction` whose body dirties nothing leaves no disables flag behind,
/// so the next plain write under `.animation(_:value:)` animates; (b) a
/// disables transaction consumed by one build does not reach the next, so a
/// later plain write animates too. Mutations **V9** (drop the flag's rollback
/// in `parkTransaction`) — arm (a); **V10** (`takeParkedTransaction` stops
/// clearing `parkedDisablesAnimations`) — arm (b).
@MainActor @Test func aDisablingTransactionReachesExactlyOneBuildAndRollsBack() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40).animation(.linear(duration: 1), value: model.flag)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)
    try #require(!Animation.parkedDisablesAnimations, "set up: nothing parked")

    // (a) A disables transaction whose body changes nothing is rolled back whole.
    var disabling = Transaction()
    disabling.disablesAnimations = true
    withTransaction(disabling) { }
    #expect(!Animation.parkedDisablesAnimations,
            "a body that dirties nothing rolls the disables flag back with the animation")
    model.flag = 1
    model.width = 200
    platform.simulateTick(timestamp: 101)
    platform.simulateTick(timestamp: 101.5)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "(a) the next plain value change animates: 150 at 0.5 s; 200 means a rolled-back disables flag leaked")
    platform.simulateTick(timestamp: 102.1)
    try #require(transactionRectWidth(window, height: 40) == 200)

    // (b) A disables transaction with a write: one build consumes it (and snaps).
    withTransaction(disabling) {
        model.flag = 2
        model.width = 100
    }
    platform.simulateTick(timestamp: 103)
    try #require(transactionRectWidth(window, height: 40) == 100,
                 "set up: the disabling build suppresses the modifier and snaps")
    #expect(!Animation.parkedDisablesAnimations, "the build took and cleared the flag")
    model.flag = 3
    model.width = 200
    platform.simulateTick(timestamp: 104)
    platform.simulateTick(timestamp: 104.5)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "(b) the NEXT build is not disabled: 150 at 0.5 s; 200 means the parked flag outlived its build")
}

/// **1.7 (T6, T7, T7c).** `.transaction { $0.animation = nil }` snaps its subtree
/// only (T6); `= linear(1)` rewrites withAnimation's linear(4) (T7); and it
/// rewrites even when there is no transaction at all (T7c). Mutation **M1.7**:
/// apply the transform only when the root has an animation (T7c arm).
@MainActor @Test func aTransactionModifierRewritesItsSubtreesAnimation() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40).transaction { $0.animation = nil }
            subject(model.width, 41).transaction { $0.animation = .linear(duration: 1) }
            subject(model.width, 42)
            subject(model.other, 43).transaction { $0.animation = .linear(duration: 1) }
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)

    withAnimation(.linear(duration: 4)) { model.width = 200 }
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 200, "T6: animation = nil snaps its subtree")
    #expect(transactionRectWidth(window, height: 41) == 150, "T7: animation = linear(1) rewrites linear(4)")
    platform.simulateTick(timestamp: 101.1)
    #expect(transactionRectWidth(window, height: 42) == 125, "T6: a sibling keeps linear(4)")

    // T7c: no withAnimation anywhere.
    model.other = 200
    platform.simulateTick(timestamp: 110)
    platform.simulateTick(timestamp: 110.5)
    #expect(transactionRectWidth(window, height: 43) == 150,
            "T7c: the transform rewrites even with no transaction at all")
}

/// **1.8.** The modifier's transaction reaches paint as it reaches layout: a
/// `Box`'s width (layout helper) and its background (paint helper) animate
/// together under `.animation(linear(1), value:)`. Mutation **M1.8**: skip the
/// push in `paintGroup` — the colour arm.
@MainActor @Test func theAnimationModifierAppliesInPaintAsInLayout() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40, model.useAccent ? .accent : .background)
                .animation(.linear(duration: 1), value: model.flag)
        }
    }
    platform.simulateTick(timestamp: 100)
    let from = try #require(transactionRectColour(window, height: 40))

    model.flag = 1
    model.width = 200
    model.useAccent = true
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 150, "the width animates (layout)")
    let mid = try #require(transactionRectColour(window, height: 40))
    platform.simulateTick(timestamp: 101.1)
    let to = try #require(transactionRectColour(window, height: 40))
    try #require(from != to, "set up: the two tokens resolve to different colours")
    #expect(mid != from && mid != to,
            "the background is mid-fade at 0.5 s (paint sees the pushed transaction); got \(mid), from \(from), to \(to)")
}

// MARK: - 1.9, 1.10: Binding.animation / .transaction (T11, T11s, T12s)

@MainActor
private final class KeptWidth { var binding: Binding<Float>? }

private struct SizeValue: Equatable { var width: Float }

@MainActor
private final class KeptSize { var binding: Binding<SizeValue>? }

private struct SizeOwner: Component {
    @State var size = SizeValue(width: 100)
    let kept: KeptSize
    var content: some ElementGroup {
        if kept.binding == nil { kept.binding = $size }
        return Box().background(.accent).cssWidth(Pixels(size.width)).cssHeight(Pixels(41))
    }
}

private struct WidthOwner: Component {
    @State var width: Float = 100
    let kept: KeptWidth
    var content: some ElementGroup {
        if kept.binding == nil { kept.binding = $width }
        return Box().background(.accent).cssWidth(Pixels(width)).cssHeight(Pixels(40))
    }
}

/// **1.9 (T11s, T12s).** A write through `$state.animation(linear(1))` animates;
/// so does one through `$state.transaction(Transaction(animation: linear(1)))`,
/// and one through each binding derived from it (`AN-Z`'s "every binding
/// derived from one"): the optional lift, the unwrapping initialiser and a
/// key-path member. Mutation **M1.9**: `animation(_:)` returns `self`
/// unchanged; **V5** (drop the flag inside `derived`) — the three derived
/// arms; **V11** (the unwrap initialiser builds a plain `Binding(get:set:)`)
/// — the unwrap arm; **V12** (the dynamic-member subscript builds a plain
/// `Binding(get:set:)`) — the key-path arm.
@MainActor @Test func aBindingAnimationAnimatesAStateWrite() throws {
    let kept = KeptWidth()
    let keptSize = KeptSize()
    let (window, platform) = try makeTransactionWindow {
        Column {
            WidthOwner(kept: kept)
            SizeOwner(kept: keptSize)
        }
    }
    platform.simulateTick(timestamp: 100)
    let binding = try #require(kept.binding)
    try #require(transactionRectWidth(window, height: 40) == 100)

    // T11s
    let animated = binding.animation(.linear(duration: 1))
    #expect(animated.transaction.animation == .linear(duration: 1))
    animated.wrappedValue = 200
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "T11s: a write through $state.animation(linear 1) animates")
    platform.simulateTick(timestamp: 101.1)

    // T12s
    binding.transaction(Transaction(animation: .linear(duration: 1))).wrappedValue = 100
    platform.simulateTick(timestamp: 102)
    platform.simulateTick(timestamp: 102.5)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "T12s: a write through $state.transaction(…) animates")
    platform.simulateTick(timestamp: 103)

    // A binding derived from an animated @State binding keeps the source.
    let lifted = Binding<Float?>(binding.animation(.linear(duration: 1)))
    lifted.wrappedValue = 200
    platform.simulateTick(timestamp: 104)
    platform.simulateTick(timestamp: 104.5)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "a binding derived from $state keeps its transaction and its source")
    platform.simulateTick(timestamp: 105)

    // The unwrapping initialiser over an animated lift keeps both too.
    let unwrapped = try #require(Binding<Float>(Binding<Float?>(binding.animation(.linear(duration: 1)))))
    unwrapped.wrappedValue = 100
    platform.simulateTick(timestamp: 105.2)
    platform.simulateTick(timestamp: 105.7)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "the unwrapping initialiser keeps the source and the transaction")
    platform.simulateTick(timestamp: 106.3)
    try #require(transactionRectWidth(window, height: 40) == 100)

    // A key-path member of an animated $state binding keeps both too.
    let sizeBinding = try #require(keptSize.binding)
    try #require(transactionRectWidth(window, height: 41) == 100)
    sizeBinding.animation(.linear(duration: 1)).width.wrappedValue = 200
    platform.simulateTick(timestamp: 107)
    platform.simulateTick(timestamp: 107.5)
    #expect(transactionRectWidth(window, height: 41) == 150,
            "a key-path member binding keeps the source and the transaction")
    platform.simulateTick(timestamp: 108.1)
    try #require(transactionRectWidth(window, height: 41) == 200)
    binding.wrappedValue = 200
    platform.simulateTick(timestamp: 108.5)
    try #require(transactionRectWidth(window, height: 40) == 200)

    // Control: a plain $state write snaps (T11c).
    binding.wrappedValue = 100
    platform.simulateTick(timestamp: 109)
    #expect(transactionRectWidth(window, height: 40) == 100, "control: a plain write snaps")
}

/// **1.10 (T11).** A `Binding(get:set:)` over a model ignores its transaction:
/// `.animation(linear(1))` on it snaps, where the same write through `$state`
/// animates (1.9). Mutation **M1.10**: apply the transaction to every binding's
/// write.
@MainActor @Test func aClosureBindingIgnoresItsTransaction() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column { subject(model.width, 40) }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)

    let closure = Binding(get: { model.width }, set: { model.width = $0 })
    let animated = closure.animation(.linear(duration: 1))
    #expect(animated.transaction.animation == .linear(duration: 1),
            "the transaction is carried (SwiftUI's surface) — it is only not applied")
    animated.wrappedValue = 200
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 200,
            "T11: a closure binding's transaction does not animate the write")
    #expect(!window.hasActiveAnimations)
}

// MARK: - 1.11, 1.12: the value store (AN-AB)

/// **1.11.** Two `.animation(_:value:)` scopes nested at one position keep
/// separate stored values: changing only the INNER one's value animates with
/// the inner's curve, and a later width-only change snaps. Mutation **M1.11**:
/// drop the depth from the store key.
@MainActor @Test func twoAnimationScopesAtOnePositionKeepSeparateValues() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            subject(model.width, 40)
                .animation(.linear(duration: 1), value: model.flag)
                .animation(.linear(duration: 4), value: model.flag2 + 10)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(transactionRectWidth(window, height: 40) == 100)

    // Width alone: neither value changed, so it snaps — and does so only if the
    // two scopes' stored values are not one slot overwritten by the other.
    model.width = 200
    platform.simulateTick(timestamp: 101)
    #expect(transactionRectWidth(window, height: 40) == 200,
            "neither value changed: a width-only change snaps")
    #expect(!window.hasActiveAnimations)

    // The inner value changes: its linear(1) applies (the outer pushes unchanged).
    model.flag = 1
    model.width = 100
    platform.simulateTick(timestamp: 102)
    platform.simulateTick(timestamp: 102.5)
    #expect(transactionRectWidth(window, height: 40) == 150,
            "the inner value changed: its linear(1) animates, 150 at 0.5 s")
}

/// **1.12.** A `.animation(_:value:)` scope stores its value in the window's
/// `AnimationStore`, not in `StateTable`: the table's entry count is the same
/// with and without the scope, and the store holds the one value. Mutation
/// **M1.12**: store the value in `StateTable`.
@MainActor @Test func anAnimationScopeStoresNoStateTableEntry() throws {
    let model = TransactionModel()
    let (bare, bareFake) = try makeTransactionWindow {
        Column { subject(model.width, 40) }
    }
    let (scoped, scopedFake) = try makeTransactionWindow {
        Column { subject(model.width, 40).animation(.linear(duration: 1), value: model.flag) }
    }
    bareFake.simulateTick(timestamp: 100)
    scopedFake.simulateTick(timestamp: 100)
    try #require(bare.stateTable.count > 0, "set up: the fixture mints table entries")
    #expect(scoped.stateTable.count == bare.stateTable.count,
            "the scope adds no StateTable entry: \(scoped.stateTable.count) vs \(bare.stateTable.count)")
    #expect(scoped.animationStore.count == 1, "the value lives in the store")
    #expect(bare.animationStore.count == 0)
}

/// **1.12b.** The store drops an entry the frame does not touch (`AN-AB`): a
/// scope inside an `if` toggled off for one frame leaves the store empty, and
/// back on it stores again. Mutation **V2** (`endFrame` never filters).
@MainActor @Test func anAnimationScopeThatLeavesForAFrameLeavesTheStore() throws {
    let model = TransactionModel()
    let (window, platform) = try makeTransactionWindow {
        Column {
            if model.flag2 == 0 {
                subject(model.width, 40).animation(.linear(duration: 1), value: model.flag)
            }
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(window.animationStore.count == 1, "set up: the scope stored its value")

    model.flag2 = 1
    platform.simulateTick(timestamp: 101)
    try #require(transactionRectWidth(window, height: 40) == nil, "set up: the scope is gone")
    #expect(window.animationStore.count == 0,
            "an entry no frame touched is dropped at the end of that frame")

    model.flag2 = 0
    platform.simulateTick(timestamp: 102)
    #expect(window.animationStore.count == 1, "returning, the scope stores afresh")
}

// MARK: - 1.19: the registry prune (AN-AF item 8)

/// **1.19.** `Window.aFrameBuildIsPending` is a pure read: asking it does not
/// compact the weak registry (registration does). A dead window's entry
/// survives the read. Mutation **M1.19**: put the prune back into the getter.
@MainActor @Test func aFrameBuildIsPendingDoesNotPruneTheRegistry() throws {
    weak var dead: Window?
    do {
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 32) { Column { } }
        dead = window
    }
    try #require(dead == nil, "set up: the window deallocated, leaving a dead entry")
    let before = Window.registeredWindowCount
    _ = Window.aFrameBuildIsPending
    #expect(Window.registeredWindowCount == before,
            "reading aFrameBuildIsPending must not mutate the registry: \(before) → \(Window.registeredWindowCount)")

    // Registration still compacts, so the registry stays bounded.
    let (live, _) = try makeFakeWindowOnDefaultDevice(size: 32) { Column { } }
    #expect(Window.registeredWindowCount < before + 1, "registration prunes the dead entries")
    _ = live
}

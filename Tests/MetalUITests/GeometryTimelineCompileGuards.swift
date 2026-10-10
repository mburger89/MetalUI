import Testing
import MetalUITestSupport

// Key and focus scoping, lane B guards (rulings `KF-J`, `KF-K`, `KF-S`,
// `KF-T`, `KF-V` item 1; spec `docs/superpowers/specs/2026-10-08-key-focus-design.md`
// §5.2). Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN
// import — a `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `KF geometry/timeline spellings` and
// `KF timeline proposal type` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **Guard B-G1** (`KF-J`, `KF-K`, `KF-S`, `KF-T`, `KF-V` item 1). Every
/// geometry and timeline spelling typechecks from an external module, on both
/// vocabularies: both `onGeometryChange` forms on a legacy `Text` and a
/// `ProposalText`, `.padding(4)` BEFORE it, every built-in schedule; the
/// `KF-S` arms — a transform capturing a non-`Sendable` model (SwiftUI's
/// `@Sendable` transform would refuse it) and an explicit `@Sendable`
/// transform over a `Sendable` `T` (SwiftUI's spelling); the `KF-T` arms —
/// `TimelineView<PeriodicTimelineSchedule, ProposalText>.Context` and a custom
/// schedule spelling `mode: Mode`. Two must-not-compile arms: a
/// non-`Equatable` `T`, and `.padding(4)` written AFTER `.onGeometryChange` on
/// a `Box` (divergence 120).
///
/// Mutation **MG-B1**: mark the transform `@Sendable` in both
/// `onGeometryChange` overloads (the non-`Sendable` capture fails, so the
/// positive does).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func onGeometryChangeAndTimelineViewCompileOnBothVocabularies() throws {
    let positive = try typecheckFile("""
        import Foundation
        @MainActor final class Viewport {
            var size = Size<Pixels>(width: Pixels(0), height: Pixels(0))
            var scale: Float = 1
        }
        struct Steps: TimelineSchedule {
            func entries(from startDate: Date, mode: Mode) -> [Date] { [startDate] }
        }
        @MainActor func legacy(_ v: Viewport) -> some Element {
            Column {
                Text("a")
                    .onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { v.size = $0 }
                Text("b")
                    .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) }) { old, new in
                        _ = (old, new)
                    }
                Box {}.padding(4).onGeometryChange(for: Float.self, of: { _ in v.scale }) { _ in }
                TimelineView(.animation) { context in ProposalText("\\(context.date)") }
            }
        }
        @MainActor func proposal(_ v: Viewport) -> some Element {
            HStack {
                ProposalText("c")
                    .onGeometryChange(for: Float.self, of: { @Sendable proxy in proxy.size.width.value }) { _ in }
                    .offset(x: Pixels(2))
                TimelineView(.animation(minimumInterval: 0.1, paused: false)) { _ in ProposalText("d") }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ProposalText(context.cadence == .live ? "live" : "other")
                }
                TimelineView(.everyMinute) { _ in ProposalText("e") }
                TimelineView(.explicit([Date()])) { _ in ProposalText("f") }
                TimelineView(Steps()) { _ in ProposalText("g") }
            }
        }
        let contextual: (TimelineView<PeriodicTimelineSchedule, ProposalText>.Context) -> Void = { _ in }
        let cadence: TimelineView<PeriodicTimelineSchedule, ProposalText>.Context.Cadence = .live
        let mode: TimelineScheduleMode = Steps.Mode.normal
        """, importing: "MetalUI")
    let nonEquatable = try typecheckFile("""
        struct Token { var n: Int }
        @MainActor func tree() -> some Element {
            Column { Text("a").onGeometryChange(for: Token.self, of: { _ in Token(n: 1) }) { _ in } }
        }
        """, importing: "MetalUI")
    let decorationAfter = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column { Box {}.onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in }.padding(4) }
        }
        """, importing: "MetalUI")
    print("""
        KF geometry/timeline spellings: positive succeeded=\(positive.succeeded) messages=[\(positive.messages)]; \
        non-Equatable succeeded=\(nonEquatable.succeeded) messages=[\(nonEquatable.messages)]; \
        decoration after succeeded=\(decorationAfter.succeeded) messages=[\(decorationAfter.messages)]
        """)
    try #require(positive.succeeded && !nonEquatable.succeeded && !decorationAfter.succeeded,
                 """
                 every spelling must compile and both separating arms must not, or this guard cannot fail:
                 positive:
                 \(positive.output)
                 non-Equatable:
                 \(nonEquatable.output)
                 decoration after:
                 \(decorationAfter.output)
                 """)
    #expect(nonEquatable.messages.contains("Equatable"), "\(nonEquatable.output)")
    #expect(decorationAfter.messages.contains("padding"), "\(decorationAfter.output)")
}

/// **Guard B-G2** (`KF-L`, `PE-B`). A `TimelineView` inside an `HStack` keeps
/// its proposal type through `ProposalContentBuilder` —
/// `HStack<TimelineView<AnimationTimelineSchedule, ProposalText>>` — so the
/// stack reaches its typed entry. The separating arm: the same content typed
/// as `LegacyContent<…>` does not compile.
///
/// Mutation **MG-B2**: declare `TimelineView` an `ElementGroup` only (its
/// typed entry kept as a plain method): the builder adopts it as
/// `LegacyContent`, so the positive fails and the negative compiles.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aTimelineViewInsideAnHStackKeepsItsProposalType() throws {
    let positive = try typecheckFile("""
        @MainActor public func typed() {
            let _: HStack<TimelineView<AnimationTimelineSchedule, ProposalText>> =
                HStack { TimelineView(.animation) { _ in ProposalText("a") } }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor public func wrapped() {
            let _: HStack<LegacyContent<TimelineView<AnimationTimelineSchedule, ProposalText>>> =
                HStack { TimelineView(.animation) { _ in ProposalText("a") } }
        }
        """, importing: "MetalUI")
    print("""
        KF timeline proposal type: positive succeeded=\(positive.succeeded); negative \
        succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 the proposal type must compile and the LegacyContent one must not, or this guard \
                 cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
}

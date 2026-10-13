import Testing
import MetalUITestSupport

// Window drag (item C22, rulings `WD-B`, `WD-C`; spec
// `docs/superpowers/specs/2026-10-12-window-drag-design.md` §5, guard 3.2).
// Whole-file Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`,
// ruling SA-P). **A guard skips silently when `.build/<triple>/debug/Modules`
// is absent** (CLAUDE.md, "Guards"); grep the log for `WD GUARD`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **3.2** (`WD-B`). An outside module can attach `WindowDragGesture()` with
/// `.gesture(_:)`, `.highPriorityGesture(_:)` and `.simultaneousGesture(_:)` on
/// both vocabularies and name its `Value`; it cannot give it callbacks
/// (`onChanged`, `onEnded`) nor make a `Value` (no members, SwiftUI's).
/// Mutation: a public `onChanged` on `WindowDragGesture` (negative arm B
/// compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImporterCanAttachWindowDragGestureButCannotGiveItCallbacks() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() -> some Element {
            let _: WindowDragGesture.Value.Type = WindowDragGesture.Value.self
            return ZStack {
                Rectangle().frame(width: Pixels(10), height: Pixels(10)).gesture(WindowDragGesture())
                Rectangle().highPriorityGesture(WindowDragGesture())
                Rectangle().simultaneousGesture(WindowDragGesture())
                Box().frame(width: Pixels(10), height: Pixels(10)).gesture(WindowDragGesture())
            }
        }
        """, importing: "MetalUI")
    print("WD GUARD 3.2 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let callbacks = try typecheckFile("""
        @MainActor public func bad() {
            _ = WindowDragGesture().onChanged { _ in }
        }
        """, importing: "MetalUI")
    print("WD GUARD 3.2 callbacks: succeeded=\(callbacks.succeeded)\n\(callbacks.messages)")
    let value = try typecheckFile("""
        @MainActor public func bad() {
            _ = WindowDragGesture.Value()
        }
        """, importing: "MetalUI")
    print("WD GUARD 3.2 value: succeeded=\(value.succeeded)\n\(value.messages)")
    try #require(positive.succeeded, "the control must compile, or this guard cannot fail:\n\(positive.output)")
    #expect(!callbacks.succeeded, "no onChanged: \(callbacks.output)")
    #expect(!value.succeeded, "no outside Value: \(value.output)")
}

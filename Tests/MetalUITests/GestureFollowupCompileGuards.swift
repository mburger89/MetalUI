import Testing
import MetalUITestSupport

// Input follow-ups, lane 1 — typecheck guards (rulings `IF-C` item 3, `IF-E`).
// Whole-file Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`,
// ruling SA-P). **A guard skips silently when `.build/<triple>/debug/Modules`
// is absent** (CLAUDE.md, "Guards"); grep the log for `IF GESTURE GUARD`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1 — a drag value built without a click count still compiles** (`IF-C`
/// item 3), and one built with it does. The negative arm passes a click count
/// of the wrong type. Mutation: remove `clickCount`'s default (the 3-argument
/// spelling no longer compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aDragValueBuiltWithoutAClickCountStillCompiles() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() {
            let a = DragGesture.Value(startLocation: Point(x: Pixels(0), y: Pixels(0)),
                                      location: Point(x: Pixels(1), y: Pixels(1)))
            let b = DragGesture.Value(startLocation: Point(x: Pixels(0), y: Pixels(0)),
                                      location: Point(x: Pixels(1), y: Pixels(1)), modifiers: [.shift])
            let c = DragGesture.Value(startLocation: Point(x: Pixels(0), y: Pixels(0)),
                                      location: Point(x: Pixels(1), y: Pixels(1)), modifiers: [], clickCount: 2)
            let _: Int = a.clickCount + b.clickCount + c.clickCount
            let _ = SpatialTapGesture.Value(location: Point(x: Pixels(0), y: Pixels(0)))
            let _: EventModifiers = SpatialTapGesture.Value(location: Point(x: Pixels(0), y: Pixels(0)),
                                                            modifiers: [.command]).modifiers
        }
        """, importing: "MetalUI")
    print("IF GESTURE GUARD G1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let negative = try typecheckFile("""
        @MainActor public func bad() {
            _ = DragGesture.Value(startLocation: Point(x: Pixels(0), y: Pixels(0)),
                                  location: Point(x: Pixels(1), y: Pixels(1)), modifiers: [], clickCount: "2")
        }
        """, importing: "MetalUI")
    print("IF GESTURE GUARD G1 negative: succeeded=\(negative.succeeded)\n\(negative.messages)")
    try #require(positive.succeeded != negative.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(negative.output)")
    #expect(positive.succeeded, "\(positive.output)")
    #expect(!negative.succeeded, "\(negative.output)")
}

/// **G2 — `onCancelled` is offered on drag, magnify and rotate** (`IF-E`), as
/// a `@MainActor` closure returning the same gesture type. The negative arm
/// calls it on `TapGesture`, which has none. Mutation: remove
/// `RotateGesture.onCancelled`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func onCancelledIsOfferedOnDragMagnifyAndRotate() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() {
            let _: DragGesture = DragGesture().onChanged { _ in }.onCancelled { }
            let _: MagnifyGesture = MagnifyGesture().onChanged { _ in }.onCancelled { }
            let _: RotateGesture = RotateGesture().onChanged { _ in }.onCancelled { }
            let _: Box<EmptyGroup> = Box().gesture(DragGesture().onCancelled { })
        }
        """, importing: "MetalUI")
    print("IF GESTURE GUARD G2 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let negative = try typecheckFile("""
        @MainActor public func bad() {
            _ = TapGesture().onCancelled { }
        }
        """, importing: "MetalUI")
    print("IF GESTURE GUARD G2 negative: succeeded=\(negative.succeeded)\n\(negative.messages)")
    try #require(positive.succeeded != negative.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(negative.output)")
    #expect(positive.succeeded, "\(positive.output)")
    #expect(!negative.succeeded, "\(negative.output)")
}

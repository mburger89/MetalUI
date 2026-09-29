import Testing
import MetalUITestSupport

// Plan task 12, part 1, lane 1, guards G1.1–G1.2 (ruling `IX-B`). Whole-file
// Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`, ruling SA-P): what
// an external module may write with the gesture surface.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `GESTURE GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.1 — an outside type cannot conform to `Gesture`.** `Gesture` is a public
/// protocol whose one recognizer requirement is SPI (`@_spi(MetalUIGesture)`),
/// so a plain importer can neither see nor forward it (`IX-B`: "a public
/// protocol an outside module cannot conform to"). The fabricated conformance
/// forwards to a real gesture's requirement — the one way an outside type could
/// satisfy it if it were visible. The control uses `TapGesture()` as a gesture.
///
/// Mutation that must redden it: the requirement (and its description type)
/// made plainly public.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anOutsideTypeCannotConformToGesture() throws {
    let fabricated = try typecheckFile("""
        struct Mine: Gesture {
            typealias Value = Void
            func _recognizers() -> _GestureRecognizers { TapGesture()._recognizers() }
        }
        """, importing: "MetalUI")
    print("GESTURE GUARD G1.1 fabricated: succeeded=\(fabricated.succeeded)\n\(fabricated.messages)")

    let control = try typecheckFile("""
        @MainActor public func good() {
            _ = Box().gesture(TapGesture())
            _ = Box().gesture(TapGesture().exclusively(before: DragGesture()))
        }
        """, importing: "MetalUI")
    print("GESTURE GUARD G1.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(fabricated.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(fabricated.output)\n\(control.output)")
    #expect(!fabricated.succeeded, "an outside conformance to Gesture must not compile:\n\(fabricated.output)")
    #expect(control.succeeded, "TapGesture must be usable as a gesture outside the module:\n\(control.output)")
}

/// **G1.2 — every lane-1 spelling of spec §4 compiles from a plain import**,
/// on a `StyledElement` and on the proposal path; the negative arm spells
/// `sequenced(before:)`, which `IX-B` does not offer.
///
/// Mutation that must redden it: one spelling made `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theGestureSpellingsCompileFromAPlainImport() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() {
            let tap: TapGesture = TapGesture(count: 2).onEnded { }
            let long: LongPressGesture = LongPressGesture(minimumDuration: 0.4, maximumDistance: Pixels(12))
                .onChanged { (_: Bool) in }.onEnded { (_: Bool) in }
            let drag: DragGesture = DragGesture(minimumDistance: Pixels(4))
                .onChanged { (v: DragGesture.Value) in
                    let _: Point<Pixels> = v.startLocation
                    let _: Point<Pixels> = v.location
                    let _: Size<Pixels> = v.translation
                }
                .onEnded { (_: DragGesture.Value) in }
            let either: ExclusiveGesture<TapGesture, DragGesture> = tap.exclusively(before: drag)
            let both: SimultaneousGesture<LongPressGesture, TapGesture> = long.simultaneously(with: tap)
            _ = TapGesture()
            _ = LongPressGesture()
            _ = DragGesture()
            let _: Box<EmptyGroup> = Box()
                .onTapGesture { }
                .onTapGesture(count: 2) { }
                .onLongPressGesture { }
                .onLongPressGesture(minimumDuration: 1, maximumDistance: Pixels(3), perform: { },
                                    onPressingChanged: { (_: Bool) in })
                .gesture(either)
                .simultaneousGesture(both)
                .highPriorityGesture(drag)
            let proposal: GestureModifier<GestureModifier<Rectangle>> = Rectangle()
                .onTapGesture(count: 1) { }
                .gesture(tap)
            _ = HStack {
                proposal
                    .simultaneousGesture(long)
                    .highPriorityGesture(drag)
                    .onLongPressGesture(minimumDuration: 0.2) { }
            }
        }
        """, importing: "MetalUI")
    print("GESTURE GUARD G1.2 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let negative = try typecheckFile("""
        @MainActor public func bad() {
            _ = Box().gesture(TapGesture().sequenced(before: DragGesture()))
        }
        """, importing: "MetalUI")
    print("GESTURE GUARD G1.2 negative: succeeded=\(negative.succeeded)\n\(negative.messages)")

    try #require(positive.succeeded != negative.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(negative.output)")
    #expect(positive.succeeded, "every lane-1 spelling must compile outside the module:\n\(positive.output)")
    #expect(!negative.succeeded, "sequenced(before:) is not offered (IX-B):\n\(negative.output)")
}

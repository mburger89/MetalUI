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

/// **G1.1 (amended by `GE-A`) — an outside type can conform to `Gesture` only through a `body`.** The recognizer
/// requirement is still SPI (`@_spi(MetalUIGesture)`), so a plain importer can neither see nor forward it: the
/// fabricated conformance that implements `_recognizers()` does not compile (the control arm is `GE.1`'s custom
/// gesture). Two guards: `anOutsideTypeCanConformToGestureThroughABody` (the positive arm) and this one.
///
/// Mutation that must redden it: the requirement (and its description type) made plainly public.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anOutsideTypeCannotDescribeRecognizersItself() throws {
    let fabricated = try typecheckFile("""
        struct Mine: Gesture {
            typealias Value = Void
            var body: Never { fatalError() }
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
    #expect(!fabricated.succeeded, "an outside module must not implement _recognizers():\n\(fabricated.output)")
    #expect(control.succeeded, "TapGesture must be usable as a gesture outside the module:\n\(control.output)")
}

/// **GE.1 — a third-party module can declare a custom `Gesture` with a `body`** (ruling `GE-A`), name its value,
/// compose it with the combinators and attach it, on a `StyledElement` and on the proposal path; every
/// `sequenced`/`onChanged`/`onEnded`/`updating` spelling compiles from a plain import. The negative arm is a
/// conformance with no `body` and no `Value`, which cannot compile.
///
/// Mutation that must redden it: remove `Gesture.body`'s requirement, or make `GestureStateGesture` internal.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anOutsideTypeCanConformToGestureThroughABody() throws {
    let positive = try typecheckFile("""
        struct PressThenDrag: Gesture {
            var body: SequenceGesture<LongPressGesture, DragGesture> {
                LongPressGesture(minimumDuration: 0.4).sequenced(before: DragGesture())
            }
        }
        struct Hold: Gesture {
            var seconds = 0.3
            var body: some Gesture { LongPressGesture(minimumDuration: seconds) }
        }
        @MainActor struct Holder {
            @GestureState var offset = Size<Pixels>(width: Pixels(0), height: Pixels(0))
            @GestureState var lifted = false
            func spellings() {
                let custom: _EndedGesture<PressThenDrag> = PressThenDrag().onEnded { (value: PressThenDrag.Value) in
                    switch value {
                    case .first(let held): _ = held
                    case .second(let held, let drag): _ = (held, drag?.velocity, drag?.predictedEndLocation, drag?.time)
                    }
                }
                let updated: GestureStateGesture<PressThenDrag, Size<Pixels>> = PressThenDrag()
                    .updating($offset) { value, state, _ in
                        if case .second(_, let drag?) = value { state = drag.translation }
                    }
                let both = Hold().simultaneously(with: DragGesture()).updating($lifted) { value, state, _ in
                    state = value.first != nil
                }
                let either = Hold().exclusively(before: DragGesture()).onChanged { _ in }
                let sequence = TapGesture().sequenced(before: Hold().sequenced(before: DragGesture()))
                _ = Box().gesture(custom).simultaneousGesture(updated).highPriorityGesture(both)
                _ = Rectangle().gesture(either).gesture(sequence)
            }
        }
        """, importing: "MetalUI")
    print("GESTURE GUARD GE.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let negative = try typecheckFile("""
        struct NoBody: Gesture {}
        """, importing: "MetalUI")
    print("GESTURE GUARD GE.1 negative: succeeded=\(negative.succeeded)\n\(negative.messages)")

    try #require(positive.succeeded != negative.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(negative.output)")
    #expect(positive.succeeded, "a custom gesture with a body must compile outside the module:\n\(positive.output)")
    #expect(!negative.succeeded, "a gesture with no body and no recognizers cannot conform:\n\(negative.output)")
}

/// **G1.2 — every lane-1 spelling of spec §4 compiles from a plain import**,
/// on a `StyledElement` and on the proposal path; the negative arm spells
/// `including: GestureMask`, which is carried (`GE-H`).
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
            _ = Box().gesture(TapGesture(), including: .all)
        }
        """, importing: "MetalUI")
    print("GESTURE GUARD G1.2 negative: succeeded=\(negative.succeeded)\n\(negative.messages)")

    try #require(positive.succeeded != negative.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(negative.output)")
    #expect(positive.succeeded, "every lane-1 spelling must compile outside the module:\n\(positive.output)")
    #expect(!negative.succeeded, "GestureMask/including: is not offered (IX-B, GE-H):\n\(negative.output)")
}

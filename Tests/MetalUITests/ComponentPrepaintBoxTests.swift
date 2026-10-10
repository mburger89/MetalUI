import Testing
@testable import MetalUI

// Ruling `SG-E` (MG-27, `LK-X`): a `Component`'s prepaint record is one heap
// box, `ComponentPrepaint`, so an enclosing record holds a class reference and
// never the inner content's eager-move leaf — the shape Swift's asserts
// compilers crash on. That the trigger shapes compile under such a compiler is
// the env-gated `theComponentSwitchShapeAgainstAnAssertsCompiler`
// (`MetalUIScaffoldTests`); this file pins the box itself.

/// A group whose prepaint record is an `Array`, as a `ForEach`'s is — the
/// eager-move leaf of `LK-X`'s trigger. It registers nothing.
private struct ArrayRecordGroup: ElementGroup {
    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], Void) { ([], ()) }
    mutating func prepaintGroup(layout: inout Void, pass: inout PrepaintPass) -> [Int] { [] }
    mutating func paintGroup(layout: inout Void, prepaint: inout [Int], pass: inout PaintPass) {}
}

private struct LoopingComponent: Component {
    var content: ArrayRecordGroup { ArrayRecordGroup() }
}

/// **3.3** (`SG-E` item 2, the `PE-J` pattern). `ComponentPrepaint` is one
/// reference wide whatever its content, and a copy shares the record: a
/// write through `withPrepaint` on one is read through the other, so
/// `paintGroup` mutates the record `prepaintGroup` made, in place.
/// Mutation: un-box (`Storage`'s field stored inline in the struct) — both
/// arms redden.
@Test func aComponentsPrepaintIsHeldOnceAndMutatedInPlace() {
    typealias Record = ComponentPrepaint<LoopingComponent>
    #expect(MemoryLayout<Record>.size == MemoryLayout<AnyObject>.size,
            "one reference wide: \(MemoryLayout<Record>.size) bytes")
    let made = Record([1, 2])
    let copy = made
    made.withPrepaint { $0.append(3) }
    #expect(copy.withPrepaint { $0 } == [1, 2, 3], "the copy reads the write: one record, held once")
}

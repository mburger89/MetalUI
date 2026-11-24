import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Sift gap G17 (ruling `PE-AB`): a builder block's cost is linear in its child count.
//
// `ElementBuilder.buildPartialBlock` gave each intermediate `Pair<Pair<…>>` a stack slot holding the whole prefix at
// `-Onone`, so a closure's frame grew with the square of its child count. `buildBlock<each>` (`TupleGroup`) stores
// the members once. The figures are `StackMeter`'s (debug builds only; zero in release, where the test is skipped).

private struct Buttons4: Component {
    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) { Button("a") { }; Button("b") { }; Button("c") { }; Button("d") { } }
    }
}
private struct Buttons8: Component {
    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) { Button("a") { }; Button("b") { }; Button("c") { }; Button("d") { }; Button("e") { }; Button("f") { }; Button("g") { }; Button("h") { } }
    }
}
private struct Buttons11: Component {
    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) { Button("a") { }; Button("b") { }; Button("c") { }; Button("d") { }; Button("e") { }; Button("f") { }; Button("g") { }; Button("h") { }; Button("i") { }; Button("j") { }; Button("k") { } }
    }
}
private struct Buttons16: Component {
    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) { Button("a") { }; Button("b") { }; Button("c") { }; Button("d") { }; Button("e") { }; Button("f") { }; Button("g") { }; Button("h") { }; Button("i") { }; Button("j") { }; Button("k") { }; Button("l") { }; Button("m") { }; Button("n") { }; Button("o") { }; Button("p") { } }
    }
}

private func kib(_ bytes: Int) -> String { String(format: "%.1f KiB", Double(bytes) / 1024) }

@MainActor
private func closureStack<C: Component>(_ component: C) -> Int {
    StackMeter.measuring { _ = component.content }.highWater
}

/// 16 buttons cost at most 2.5 times what 8 do, and 11 buttons stay under 450 KiB. Measured (macOS arm64, debug, KiB for
/// 4 / 8 / 11 / 16 `Button`s): 195 / 491 / 802 / 1472 with the `buildPartialBlock` chain (16 over 8: 3.0), 139 / 277 / 381 / 553
/// with `buildBlock<each>` (2.0). Mutation: the `buildPartialBlock` chain restored reddens both (3.0 and 802 KiB).
@Test(.enabled(if: StackMeter.isEnabled, "StackMeter measures debug builds only"))
@MainActor func aBuilderBlocksStackGrowsLinearlyWithItsChildren() {
    let four = closureStack(Buttons4())
    let eight = closureStack(Buttons8())
    let eleven = closureStack(Buttons11())
    let sixteen = closureStack(Buttons16())
    print("STACK-METER builder 4 \(four) (\(kib(four))), 8 \(eight) (\(kib(eight))), 11 \(eleven) (\(kib(eleven))), 16 \(sixteen) (\(kib(sixteen)))")
    #expect(Double(sixteen) <= 2.5 * Double(eight), "16 children \(kib(sixteen)) against 8 children \(kib(eight))")
    #expect(eleven <= 450 * 1024, "11 children \(kib(eleven))")
}

/// What `IDLeaf` records: the id each phase saw.
@MainActor private final class IDLog { var ids: [GlobalElementID] = [] }

/// A native leaf recording the id it was identified by and counting its frames in `@State`.
private struct IDLeaf: Element {
    @State var count = 0
    var elementID: ElementID?
    let name: String
    let log: IDLog

    init(_ name: String, log: IDLog) { self.name = name; self.log = log }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        count += 1
        log.ids.append(id)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, 0)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Int, pass: inout PrepaintPass) -> Int { 0 }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Int, prepaint: inout Int, pass: inout PaintPass) {}
}

/// Eleven children in one block: each gets the flat index of its position under the container's id (0 to 10, one
/// cursor threaded through every member, as the `Pair` chain threaded it), every frame, and the `@State` of the one
/// at position 7 survives the rebuilds. Mutation: `TupleGroup` handing each member a fresh cursor (ids all index 0)
/// reddens it.
@Test @MainActor func elevenChildrenOfOneBlockKeepTheirFlatIdsAndTheirState() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(400), height: Pixels(100))
    let log = IDLog()
    var tree = Box {
        IDLeaf("0", log: log)
        IDLeaf("1", log: log)
        IDLeaf("2", log: log)
        IDLeaf("3", log: log)
        IDLeaf("4", log: log)
        IDLeaf("5", log: log)
        IDLeaf("6", log: log)
        IDLeaf("7", log: log)
        IDLeaf("8", log: log)
        IDLeaf("9", log: log)
        IDLeaf("10", log: log)
    }
    var perFrame: [[GlobalElementID]] = []
    for _ in 0..<3 {
        log.ids = []
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
        perFrame.append(log.ids)
    }
    let members = tree.content.members
    #expect(members.7.count == 3, "the child at position 7 kept its @State across 3 frames; got \(members.7.count)")
    #expect(members.0.count == 3 && members.10.count == 3)
    for ids in perFrame {
        #expect(ids.count == 11)
        #expect(ids.map(\.component) == (0..<11).map { .positional($0) }, "flat positions 0 to 10, got \(ids.map(\.component))")
        #expect(Set(ids.map(\.parent)).count == 1, "one container id for all eleven")
    }
    #expect(perFrame[0] == perFrame[1] && perFrame[1] == perFrame[2], "ids are stable from frame to frame")
}

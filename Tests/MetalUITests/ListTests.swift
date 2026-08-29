import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private struct Item: Identifiable {
    let id: String
}

private func items(_ n: Int) -> [Item] {
    (0..<n).map { Item(id: "item-\($0)") }
}

/// A minimal row: contributes one childless layout node and registers ITS OWN
/// `GlobalElementID` as a scroll region during prepaint. That registry is the
/// observable this file uses to recover a row's identity — the same technique
/// `DeferredTests` uses (a `ScrollView`'s registered region id), specialised
/// to register directly rather than through a full `ScrollView`, since a `Row`
/// needs no scrolling of its own.
private struct Row: Element {
    let item: Item
    init(_ item: Item) { self.item = item }

    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        (pass.requestNode(style: Style(), children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {
        pass.registerScrollRegion(bounds, id: id, axis: .vertical)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// Runs layout only — the idiom `ScrollViewTests.laidOut` and
/// `TextMeasureTests.laidOut` already use — and hands back the root node so a
/// caller can read its resolved bounds. `Frame.render` discards the root
/// `LayoutNodeID` it builds internally, so a test that needs the ROOT's own
/// bounds (rather than a descendant's, reachable through a registry) has no
/// other way back to it.
@MainActor
private func laidOut<E: Element>(_ element: inout E,
                                 width: Float = 400, height: Float = 600)
    -> (Frame, LayoutNodeID) {
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1)
    var pass = LayoutPass(frame: frame)
    let (root, _) = element.requestLayout(GlobalElementID.child(of: nil, at: 0, name: nil),
                                          pass: &pass)
    frame.computeRootLayout(root: root)
    return (frame, root)
}

/// A row's `GlobalElementID`, recovered from `frame.scrollRegions` rather than
/// from any accessor `Frame` does not have. `data`'s declared order is known at
/// the call site, so the row named `name`'s expected `y` — `index * rowHeight`,
/// exactly the invariant a uniform `rowHeight` buys — locates its registered
/// region without reading any GlobalElementID directly.
@MainActor
private func idOfRow(named name: String, in data: [Item], rowHeight: Pixels,
                     frame: Frame) throws -> GlobalElementID {
    let index = try #require(data.firstIndex { $0.id == name })
    let expectedY = px(rowHeight.value * Float(index))
    let region = try #require(frame.scrollRegions.first { $0.bounds.origin.y == expectedY },
                              "no row registered at y == \(expectedY.value), the position '\(name)' should have under this list's declared order")
    return region.id
}

// 10 rows x 28 = 280, regardless of what any row measures.
@Test @MainActor func aListSizesItselfToCountTimesRowHeight() throws {
    var list = List(items(10), rowHeight: px(28)) { Row($0) }
    let (frame, root) = laidOut(&list)
    #expect(frame.bounds(of: root).size.height == px(280))
}

/// Identity comes from the DATA, not from position — the property windowing
/// depends on. A row that moves position keeps its state; under positional
/// identity it would adopt its new neighbour's.
@Test @MainActor func aRowKeepsItsIdentityWhenItsPositionChanges() throws {
    let dataA = items(3)
    var listA = List(dataA, rowHeight: px(28)) { Row($0) }
    let frameA = Frame(contentSize: Size(width: px(400), height: px(600)), scaleFactor: 1)
    frameA.render(&listA)

    let dataB = Array(items(3).reversed())
    var listB = List(dataB, rowHeight: px(28)) { Row($0) }
    let frameB = Frame(contentSize: Size(width: px(400), height: px(600)), scaleFactor: 1)
    frameB.render(&listB)

    let idA = try idOfRow(named: "item-0", in: dataA, rowHeight: px(28), frame: frameA)
    let idB = try idOfRow(named: "item-0", in: dataB, rowHeight: px(28), frame: frameB)
    #expect(idA == idB)
}

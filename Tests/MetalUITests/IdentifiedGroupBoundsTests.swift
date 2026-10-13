import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// C30 (`TW-A`…`TW-C`, record §108): an `IdentifiedGroup` records its own `elementBounds`
// row only when the frame records, and the row is never a `scrollTo` target.

private struct TwoBoxes: Component {
    var content: some ElementGroup {
        Box(style: sizedStyle(width: 100, height: 10))
        Box(style: sizedStyle(width: 100, height: 30))
    }
}

private func sizedStyle(width: Float, height: Float) -> Style {
    var s = Style()
    s.size.width = .length(.pixels(Pixels(width)))
    s.size.height = .length(.pixels(Pixels(height)))
    s.flexShrink = 0
    return s
}

/// **1.38 (`TW-E`, spec test 10).** A group's layout keeps its nodes only while the frame
/// records element bounds: with recording off the list is empty (a production frame
/// allocates nothing), with it on the list holds the content's nodes. Mutation: remove the
/// `recordsElementBounds` gate in either entry (the first arm reddens).
@Test @MainActor func anIdentifiedGroupKeepsNoNodesWhenTheFrameDoesNotRecord() {
    for recording in [false, true] {
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                          recordsElementBounds: recording)
        var pass = LayoutPass(frame: frame)
        var group = IdentifiedGroup(content: TwoBoxes(), name: ElementID("g"))
        var cursor = 0
        let (nodes, layout) = group.requestGroupLayout(under: nil, at: &cursor, pass: &pass)
        #expect(nodes.count == 2)
        #expect(layout.nodes.count == (recording ? 2 : 0), "recording \(recording)")
    }
}

/// **1.39 (`TW-C`, spec test 9).** `scrollTo("g", anchor: .bottom)` over a two-node group named
/// `g`: the request resolves against the content's own first row (the first node, 10pt tall at
/// content y 200), not the group's union (40pt tall). With a 100pt viewport the `.bottom` offset
/// is 200 + 10 − 100 = 110; a union row (200 + 40 − 100 = 140) would win if
/// `recordIdentifiedBounds` called `matchScrollRequests`. Mutation: make it do so.
@Test @MainActor func anIdentifiedGroupIsNotAScrollToTarget() throws {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
        Box(style: fixedColumn(width: 100, height: 100)) {
            ScrollViewReader { proxy in
                let _ = Holder.proxy = proxy
                ScrollView {
                    Box(style: fixedColumn(width: 100, height: nil)) {
                        Box(style: sizedStyle(width: 100, height: 200))
                        TwoBoxes().id("g")
                        Box(style: sizedStyle(width: 100, height: 1000))
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
    var frames = 0
    while window.needsRedraw && frames < 6 { window.drawFrameIfNeeded(); frames += 1 }
    let proxy = try #require(Holder.proxy)
    proxy.scrollTo("g", anchor: .bottom)
    frames = 0
    while window.needsRedraw && frames < 6 { window.drawFrameIfNeeded(); frames += 1 }
    let id = try #require(window.lastScrollRegions.first).id
    #expect(window.stateTable.peek(id, as: ScrollState.self)?.offset == 110)
}

@MainActor private enum Holder { static var proxy: ScrollViewProxy? }

private func fixedColumn(width: Float, height: Float?) -> Style {
    var s = Style()
    s.flexDirection = .column
    s.size.width = .length(.pixels(Pixels(width)))
    if let height { s.size.height = .length(.pixels(Pixels(height))) }
    s.flexShrink = 0
    return s
}

import Foundation
import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// `HT-X` 1: the headless window answers `setDropOperation` honestly (record 192, `DE-H`).

@MainActor private final class MovingDelegate: DropDelegate {
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { true }
}

/// **DE-18**. Every operation `Window` reports reaches the headless window, in order: a
/// delegate's move, then none when the drag leaves the destination.
/// Mutation: the headless `setDropOperation` does not append.
@Test @MainActor func theHeadlessWindowRecordsEachReportedOperation() throws {
    let delegate = MovingDelegate()
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Color.clear.frame(width: Pixels(100), height: Pixels(100))
            Color.clear.frame(width: Pixels(100), height: Pixels(100))
                .onDrop(of: [.plainText], delegate: delegate)
                .id("dest")
        }
    }
    window.tick()
    let dest = try window.frame(ofID: "dest")
    let inside = Point(x: Pixels(dest.origin.x.value + 5), y: Pixels(dest.origin.y.value + 5))
    let outside = Point(x: Pixels(dest.origin.x.value + dest.size.width.value + 20), y: Pixels(dest.origin.y.value + 5))
    let platform = window.platformWindow
    let text = DropItem(types: [PasteboardType(identifier: "public.utf8-plain-text",
                                               conformsTo: ["public.plain-text", "public.text", "public.data", "public.item"])]) { _ in
        Array("x".utf8)
    }
    platform.simulateInput(.drop(.entered(position: inside, items: [text])))
    platform.simulateInput(.drop(.moved(position: outside)))
    #expect(platform.dropOperations == [.move, .none], "\(platform.dropOperations)")
}

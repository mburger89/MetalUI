// SCRATCH (stage 6b design): the deepest native recursion each production root
// reaches through a real `Window` under the proposal authority. Not committed
// past the scratch arm.
import Testing
import Foundation
import Metal
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI
@testable import MetalUIDemoContent

private struct Item6b: Identifiable { let id: Int }

@MainActor
private func deepest(_ name: String, width: Int = 920, height: Int = 560,
                     authority: LayoutAuthority,
                     _ content: @escaping @MainActor () -> some Element) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device, size: width, layoutAuthority: authority,
                                         content: content)
    NativeLayoutRun.deepestReached = 0
    for _ in 0..<2 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    print("SIXB-DEPTH \(name) \(authority) deepest=\(NativeLayoutRun.deepestReached)")
}

@Test @MainActor func zzRootDepthProbe() throws {
    guard ProcessInfo.processInfo.environment["METALUI_DEPTH_PROBE"] == "1" else { return }
    demoModel.showModal = false; demoModel.animationDemoActive = false
    try deepest("demo", authority: .proposal) { demoContent() }
    demoModel.showModal = true
    try deepest("demo-modal", authority: .proposal) { demoContent() }
    demoModel.showModal = false
    demoModel.animationDemoActive = true
    try deepest("demo-animation", authority: .proposal) { demoContent() }
    demoModel.animationDemoActive = false
    try deepest("preview", authority: .proposal) { nativeLayoutPreviewContent() }
    try deepest("preview-legacy", authority: .legacy) { nativeLayoutPreviewContent() }
    let items = (0..<200).map(Item6b.init)
    try deepest("list", authority: .proposal) {
        ScrollView(.vertical) {
            List(items, rowHeight: Pixels(28)) { item in
                Box { Text("Row \(item.id)") }
                    .alignItems(.center).flexGrow(1).padding(Pixels(12)).width(Pixels(420))
            }
        }
    }
}

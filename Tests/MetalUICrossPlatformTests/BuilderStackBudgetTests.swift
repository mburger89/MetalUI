import Foundation
import Testing
@testable import MetalUI

// Sift gap G17 (ruling `PE-AB`): a builder block's frame in a debug build.
//
// `ElementBuilder.buildPartialBlock` folded a block into `Pair<Pair<…>>`, and at `-Onone` every intermediate got a
// stack slot holding the whole prefix, so a closure's frame grew with the SQUARE of its child count: Sift's
// 11-child map toolbar (a segmented `Picker` with three tagged `Text`s among them) needed 512 KiB for its closure and
// 176 KiB more for the component's getter, and overflowed the 1 MB Windows test-worker thread. The pack-based
// `buildBlock` (`TupleGroup`) is linear. This builds the shape on a 768 KiB thread, which the old builder cannot (it needs about 950 KiB on macOS arm64, the new one about 560),
// inside an exit test so that an overflow fails the test rather than killing the run (as
// `DemoStackBudgetTests.swift`'s harness does, and for the same reasons: only the BUILD runs off the main thread,
// because layout reaches `Text`'s `MainActor.assumeIsolated`).

private enum Mode: Hashable { case table, map, query }

/// Sift's map toolbar: 11 children, one of them a segmented picker over three tagged texts.
private struct SiftToolbar: Component {
    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) {
            Picker("View", selection: .constant(Mode.map)) {
                Text("Table").tag(Mode.table)
                Text("Map").tag(Mode.map)
                Text("Query").tag(Mode.query)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("map.mode")
            TextField("Find a table", text: .constant(""))
                .frame(width: Pixels(200))
                .accessibilityIdentifier("map.search")
            Button("Find") { }.keyboardShortcut("f").accessibilityIdentifier("map.find")
            Spacer()
            Button("Fit") { }.keyboardShortcut("0").accessibilityIdentifier("map.fit")
            Button("\u{2212}") { }.accessibilityLabel("Zoom out").accessibilityIdentifier("map.zoomOut")
            Text(verbatim: "100%").font(size: 12).foregroundColor(.secondary)
                .frame(width: Pixels(40), alignment: .trailing)
            Button("+") { }.accessibilityLabel("Zoom in").accessibilityIdentifier("map.zoomIn")
            Menu { Toggle("a", isOn: .constant(true)) } label: { Text("Schemas") }
            Toggle("Views", isOn: .constant(true)).accessibilityIdentifier("map.views")
            Button("Reset layout") { }.accessibilityIdentifier("map.reset")
        }
        .padding(Edges(all: Pixels(12)))
        .frame(maxWidth: .infinity, minHeight: Pixels(48), maxHeight: Pixels(48))
        .accessibilityElement(children: .contain)
    }
}

/// A component between the shell and the toolbar, as Sift's detail pane is.
private struct SiftDetail: Component {
    var content: some ElementGroup {
        VStack(spacing: 0) {
            SiftToolbar()
            Text("body")
        }
    }
}

/// The shell: three levels of `if`/`else if` over the detail pane.
private struct SiftShell: Component {
    var level = 3
    var content: some ElementGroup {
        VStack {
            if level == 0 {
                Text("empty")
            } else if level == 1 {
                Text("loading")
            } else if level == 2 {
                Text("failed")
            } else {
                SiftDetail()
            }
        }
    }
}

/// Each tree's getters in a frame of their own, as the demo harness does (a debug build reserves a slot per temporary
/// for the whole function).
@MainActor @inline(never) private func buildTheToolbarGetter() { _ = SiftToolbar().content }
@MainActor @inline(never) private func buildTheDetailGetter() { _ = SiftDetail().content }
@MainActor @inline(never) private func buildTheShellGetter() { _ = SiftShell().content }

@MainActor
private func buildTheSiftShape() {
    buildTheShellGetter()
    buildTheDetailGetter()
    buildTheToolbarGetter()
}

/// Runs `build` on a thread of `stackSize` bytes and waits. `@MainActor` work, with the isolation stripped as
/// `DemoStackBudgetTests.swift`'s `buildEveryProductionTree(onAThreadOf:)` strips it.
private func buildTheSiftShape(onAThreadOf stackSize: Int) {
    nonisolated(unsafe) let build = unsafeBitCast(buildTheSiftShape as @MainActor () -> Void,
                                                  to: (() -> Void).self)
    let thread = Thread { build() }
    thread.stackSize = stackSize
    thread.start()
    while !thread.isFinished { Thread.sleep(forTimeInterval: 0.001) }
}

/// Three quarters of Windows' 1 MB. Smallest thread stack that builds the shape on macOS arm64 (a bisection at 64 KiB
/// steps): 1024 KiB with the `buildPartialBlock` chain (it failed at 896), 576 KiB since `PE-AB` (it fails at 512). The
/// getters are measured by `StackMeter` at 926 KiB and 522 KiB. What is left is the children's own expression
/// temporaries (a `Button(…).keyboardShortcut(…).accessibilityIdentifier(…)` is four 4 KB values per child in a debug
/// build), which no builder can remove. Red with the chain restored: `.signal(SIGBUS)` on macOS arm64 (a crash, not a
/// clean failure), so this test stands alone for the crash to be attributable to it.
@Test func theSiftToolbarShapeBuildsOnA768KiBThread() async {
    await #expect(processExitsWith: .success) {
        buildTheSiftShape(onAThreadOf: 768 * 1024)
    }
}

// The documented CI smoke test of the real window (rulings `IC-M`, `IC-P`;
// `docs/testing.md` "A CI smoke test of the real window"): `SDLPlatform(options:
// .headless)`, an `App`, a `.task` that records and stops the loop, exit 0.
// **A plain import**: that `Options` is reachable without SPI is part of the
// check. The loop is bounded by iterations, never a clock; a run that never
// starts its task ends at the bound and prints `task ran=false`.
//
// No `armMainRunLoopExitCheck()`: this process is meant to exit when its loop
// returns (see `MainQueueDrainCheck`).
import Foundation
import MetalUI
import MetalUICore
import MetalUIPlatform
import MetalUIPortableText
import MetalUISDL

@MainActor final class SmokeState {
    var taskRan = false
}

@MainActor func portableTextSystem() throws -> PortableTextSystem {
    let fonts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Fonts/NotoSans-Regular.ttf")
    let resolver = try PortableFontResolver(defaultFont: [UInt8](try Data(contentsOf: fonts)))
    return PortableTextSystem(resolver: resolver)
}

// Generous: under SDL's offscreen driver a pass does almost nothing and main-queue
// work is serviced some passes later (see `MainQueueDrainCheck`).
let iterationLimit = 200_000

let state = SmokeState()
let platform = try SDLPlatform(options: .headless)
let textSystem = try portableTextSystem()
let app = App(platform: platform, textSystem: { textSystem })
try app.openWindow(title: "HeadlessLaunchCheck", size: Size(width: Pixels(64), height: Pixels(64))) {
    Column {
        Box().frame(width: Pixels(20), height: Pixels(20)).background(.accent)
            .task {
                state.taskRan = true
            }
    }
}
var iterations = 0
let window = try platform.openSDLWindow(title: "HeadlessLaunchCheckBound", size: Size(width: Pixels(16), height: Pixels(16)))
window.startDisplayLink { _ in
    iterations += 1
    // `platform.stop()` from the task could run before `run()` begins and be
    // lost: the loop's own tick reads the flag instead.
    if state.taskRan || iterations >= iterationLimit { platform.stop() }
}
app.run()
print("task ran=\(state.taskRan) iterations=\(iterations)")
exit(state.taskRan ? 0 : 1)

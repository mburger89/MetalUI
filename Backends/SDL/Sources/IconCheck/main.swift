// The X11 window icon, checked from outside the process (ruling `WI-E`): an `App` over a
// real `SDLPlatform` window sets `app.icon` to solid squares of the sizes named by the
// first argument ("256" or "16,32,256"), then runs the shell command of the second
// argument once the window has been drawn for a few frames and exits with its status.
// The CI step runs it under Xvfb with `SDL_VIDEO_DRIVER=x11` and the command reads
// `_NET_WM_ICON` back with `xprop` (`.github/fixtures/x11-icon/check.sh`). A plain import,
// the way an app writes it. The third argument "after" sets the icon after the window
// opened instead of before. The loop is bounded by passes, never a clock.
import Foundation
import MetalUI
import MetalUICore
import MetalUIPlatform
import MetalUIPortableText
import MetalUISDL

@MainActor func portableTextSystem() throws -> PortableTextSystem {
    let fonts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Fonts/NotoSans-Regular.ttf")
    let resolver = try PortableFontResolver(defaultFont: [UInt8](try Data(contentsOf: fonts)))
    return PortableTextSystem(resolver: resolver)
}

/// An opaque solid square whose colour varies with its side, so no two sizes share bytes.
func square(_ side: Int) -> ImageBitmap {
    var rgba: [UInt8] = []
    rgba.reserveCapacity(side * side * 4)
    for _ in 0..<(side * side) { rgba += [UInt8(side % 256), 40, 200, 255] }
    return ImageBitmap(width: side, height: side, rgba: rgba)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: IconCheck <sizes, e.g. 16,32,256> <shell command> [after]\n".utf8))
    exit(2)
}
let sizes = arguments[1].split(separator: ",").compactMap { Int($0) }
let command = arguments[2]
let iconAfterOpen = arguments.count > 3 && arguments[3] == "after"
let passesBeforeCommand = 60

let platform = try SDLPlatform()
let textSystem = try portableTextSystem()
let app = App(platform: platform, textSystem: { textSystem })
if !iconAfterOpen { app.icon = sizes.map(square) }
try app.openWindow(title: "IconCheck", size: Size(width: Pixels(200), height: Pixels(120))) {
    Box().frame(width: Pixels(20), height: Pixels(20)).background(.accent)
}
if iconAfterOpen { app.icon = sizes.map(square) }
var passes = 0
var status: Int32 = 1
let tick = try platform.openSDLWindow(title: "IconCheckTick", size: Size(width: Pixels(16), height: Pixels(16)))
tick.startDisplayLink { _ in
    passes += 1
    guard passes == passesBeforeCommand else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    do { try process.run(); process.waitUntilExit(); status = process.terminationStatus }
    catch { print("IconCheck: cannot run the command: \(error)") }
    platform.stop()
}
app.run()
exit(status)

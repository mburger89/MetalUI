// DemoCapture (ruling DC-B): the demo on this platform, compared with macOS.
//
// Builds the demo's tree natively — MetalUI's layout, the portable text system
// over Noto Sans — and checks it against `frame-5.muireplay`, which macOS
// recorded from the same tree with the production Metal renderer:
//
// 1. the scene's primitives and atlas coverage are byte-for-byte macOS's;
// 2. `SDLWindowRenderer` draws it within the replay parity tolerance of the
//    Metal pixels (≤1 step outside glyph quads, ≤8 inside).
//
// Usage: DemoCapture <fixture-dir> [--driver metal|vulkan|direct3d12] [--dump <dir>]
import Foundation
import MetalUI
import MetalUIDemoContent
import MetalUIPortableText
import MetalUISDL
import ReplayFixture

struct CaptureError: Error, CustomStringConvertible { let description: String }

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let fontPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts/NotoSans-Regular.ttf").path

@MainActor
func capture() throws {
    let optionValues = Set(["--driver", "--dump"].compactMap(option))
    guard let directory = CommandLine.arguments.dropFirst()
        .first(where: { !$0.hasPrefix("--") && !optionValues.contains($0) }) else {
        throw CaptureError(description: "usage: DemoCapture <fixture-dir> [--driver …] [--dump dir]")
    }
    guard let data = FileManager.default.contents(atPath: directory + "/frame-5.muireplay") else {
        throw CaptureError(description: "no frame-5.muireplay in \(directory)")
    }
    let recorded = try ReplayFixture(decoding: [UInt8](data))

    // The tree, built here.
    guard let font = FileManager.default.contents(atPath: fontPath) else {
        throw CaptureError(description: "cannot read \(fontPath)")
    }
    let system = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](font)))
    let atlas = GlyphAtlas(width: 1024, height: 1024)
    let scene = renderFrame(demoContent,
                            size: Size(width: Pixels(Float(recorded.width)), height: Pixels(Float(recorded.height))),
                            scaleFactor: 1, textSystem: system, atlas: atlas)
    let native = try ReplayFixture(scene: scene, atlas: atlas, width: recorded.width, height: recorded.height,
                                   projection: recorded.projection, reference: recorded.reference)
    let sameScene = native.rects == recorded.rects && native.glyphs == recorded.glyphs
        && native.runs == recorded.runs && native.atlas == recorded.atlas
    print("scene built here: \(scene.rects.count) rects, \(scene.glyphs.count) glyphs, \(scene.drawList.count) runs; "
          + "byte-for-byte macOS's: \(sameScene)")

    // Drawn here, by the backend an app on this platform uses.
    let renderer = try SDLWindowRenderer(offscreenWidth: Int(recorded.width), height: Int(recorded.height),
                                         driver: option("--driver") ?? SDLWindowRenderer.defaultDriver)
    guard renderer.beginFrame() != nil, renderer.finishFrame(scene: scene, atlas: atlas) else {
        throw CaptureError(description: "SDLWindowRenderer could not draw the frame")
    }
    let pixels = try renderer.readPixels(width: Int(recorded.width), height: Int(recorded.height))
    if let dump = option("--dump") {
        _ = FileManager.default.createFile(atPath: dump + "/demo.bgra", contents: Data(pixels))
    }
    let parity = recorded.parity(of: pixels)
    print("drawn by SDL \(renderer.driver): outside glyphs \(parity.outside.pixels) px, max Δ\(parity.outside.maxDelta) "
          + "(≤\(ParityTolerance.outsideGlyphs)); inside glyphs \(parity.inside.pixels) px, max Δ\(parity.inside.maxDelta) "
          + "(≤\(ParityTolerance.insideGlyphs))")
    guard sameScene else { throw CaptureError(description: "the demo's scene differs from the one macOS recorded") }
    guard parity.passes else { throw CaptureError(description: "the demo's pixels are outside the parity tolerance") }
    print("PASS")
}

do { try MainActor.assumeIsolated { try capture() } } catch {
    print("ERROR: \(error)")
    exit(1)
}

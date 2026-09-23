import Foundation
import Testing
import MetalUIDemoContent
import MetalUIPortableText
import MetalUIScene
@testable import MetalUI

// XP-C: the whole framework — layout, both engines' text through the portable
// text system, paint — produces the same frame on every platform. The demo's
// own tree (`demoContent()`) is rendered by a `Frame` with a
// `PortableTextSystem` over Noto Sans, and every primitive's fields, the draw
// list and the atlas coverage are hashed. Recorded on macOS
// (`METALUI_CROSSPLATFORM_RECORD=1`); Linux and Windows CI must read the same
// numbers. A difference off macOS is the finding: do not re-record from there.

private let fontURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")

/// FNV-1a 64.
private struct Hasher64 {
    var value: UInt64 = 0xcbf2_9ce4_8422_2325
    mutating func add(_ bytes: some Sequence<UInt8>) {
        for byte in bytes { value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
    }
    mutating func add(_ float: Float) { add(withUnsafeBytes(of: float.bitPattern.littleEndian) { Array($0) }) }
    mutating func add(_ int: UInt32) { add(withUnsafeBytes(of: int.littleEndian) { Array($0) }) }
    mutating func add(_ b: MUIBounds) { add(b.origin.x); add(b.origin.y); add(b.size.width); add(b.size.height) }
    mutating func add(_ c: MUICorners) { add(c.topLeft); add(c.topRight); add(c.bottomRight); add(c.bottomLeft) }
    mutating func add(_ e: MUIEdges) { add(e.top); add(e.right); add(e.bottom); add(e.left) }
    mutating func add(_ h: MUIHsla) { add(h.h); add(h.s); add(h.l); add(h.a) }
}

struct DemoFrame: Equatable, CustomStringConvertible {
    let rects: Int, glyphs: Int, runs: Int
    let primitives: UInt64
    let atlas: UInt64
    var description: String {
        "rects \(rects), glyphs \(glyphs), runs \(runs), primitives 0x\(String(primitives, radix: 16)), atlas 0x\(String(atlas, radix: 16))"
    }
}

@MainActor
func renderDemoFrame(scale: Float) throws -> DemoFrame {
    let system = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: fontURL))))
    let atlas = GlyphAtlas(width: 1024, height: 1024)
    let frame = Frame(contentSize: Size(width: Pixels(920), height: Pixels(560)), scaleFactor: scale,
                      textSystem: system, glyphAtlas: atlas)
    var root = demoContent()
    frame.render(&root)
    let scene = frame.finalizedScene()
    var hasher = Hasher64()
    for rect in scene.rects {
        hasher.add(rect.bounds); hasher.add(rect.contentMask); hasher.add(rect.maskCornerRadii)
        hasher.add(rect.background); hasher.add(rect.borderColor); hasher.add(rect.cornerRadii)
        hasher.add(rect.borderWidths); hasher.add(rect.order)
    }
    for glyph in scene.glyphs {
        hasher.add(glyph.bounds); hasher.add(glyph.atlasBounds); hasher.add(glyph.contentMask)
        hasher.add(glyph.maskCornerRadii); hasher.add(glyph.color); hasher.add(glyph.order)
    }
    for run in scene.drawList {
        hasher.add(UInt32(run.kind == .glyph ? 1 : 0)); hasher.add(UInt32(run.start)); hasher.add(UInt32(run.count))
    }
    var atlasHasher = Hasher64()
    atlasHasher.add(atlas.pixels)
    return DemoFrame(rects: scene.rects.count, glyphs: scene.glyphs.count, runs: scene.drawList.count,
                     primitives: hasher.value, atlas: atlasHasher.value)
}

@MainActor
@Test func theDemoFrameMatchesTheValuesRecordedOnMacOS() throws {
    for (scale, expected) in expectedDemoFrames {
        let frame = try renderDemoFrame(scale: scale)
        #expect(frame == expected, "scale \(scale): measured \(frame), recorded on macOS \(expected)")
    }
}

/// Not degenerate: the frame draws rects and text, and scale 2 differs from 1.
@MainActor
@Test func theDemoFrameDrawsRectsAndText() throws {
    let one = try renderDemoFrame(scale: 1), two = try renderDemoFrame(scale: 2)
    #expect(one.rects > 20 && one.glyphs > 200)
    #expect(one.primitives != two.primitives)
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_CROSSPLATFORM_RECORD"] == "1"))
func recordDemoFrames() throws {
    for scale: Float in [1, 2] {
        let frame = try renderDemoFrame(scale: scale)
        print("RECORD (\(scale), DemoFrame(rects: \(frame.rects), glyphs: \(frame.glyphs), runs: \(frame.runs), primitives: 0x\(String(frame.primitives, radix: 16)), atlas: 0x\(String(frame.atlas, radix: 16)))),")
    }
}

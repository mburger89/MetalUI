import Testing
import Foundation
import MetalUIPortableText
import MetalUIScene
import MetalUIShaderTypes

// Placeholder: the Apple-path oracle (PT-F) replaces this.
func fontBytes(_ name: String) throws -> [UInt8] {
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fonts/\(name)")
    return [UInt8](try Data(contentsOf: path))
}

@Test func emittingAStringFillsTheSceneAndTheAtlas() throws {
    let font = try PortableFont(data: fontBytes("NotoSans-Regular.ttf"), size: 13)
    var scene = Scene()
    let atlas = GlyphAtlas(width: 512, height: 512)
    atlas.beginFrame()
    let advance = try PortableText.emit("Hi there", font: font, origin: (x: 10, y: 20),
                                        scaleFactor: 2, color: MUIHsla(h: 0, s: 0, l: 0, a: 1),
                                        contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                                               size: MUISize(width: 400, height: 100)),
                                        into: &scene, atlas: atlas)
    atlas.endFrame()
    scene.finalize()
    // "Hi there" is 8 characters, one of them a space, which is packed but
    // never emitted (PT-D).
    #expect(scene.glyphs.count == 7)
    #expect(advance > 0)
    #expect(atlas.pixels.contains { $0 > 0 })
    let first = try #require(scene.glyphs.first)
    print("SMOKE advance=\(advance) first=\(first.bounds.origin.x),\(first.bounds.origin.y) "
          + "size=\(first.bounds.size.width)x\(first.bounds.size.height) "
          + "inked=\(atlas.pixels.filter { $0 > 0 }.count)")
}

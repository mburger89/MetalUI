import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// `SYM-K`: image scale, symbol variants and the rendering mode reach a retained decision through the environment
// fingerprint. Four `.equatable()` panels draw a symbol; a change of `imageScale` or `symbolVariant` above them must miss and
// re-measure. Read from the scene's image quads (device pixels, scale factor 2), compared with a retention-off twin.

@Observable @MainActor final class SymbolBox {
    var scale: Image.Scale = .medium
    var variants: SymbolVariants = .none
}

struct SymbolPanel: Component, @MainActor Equatable {
    let index: Int
    var content: some ElementGroup {
        Image(systemName: "star").font(.system(size: 13))
    }
    static func == (l: SymbolPanel, r: SymbolPanel) -> Bool { l.index == r.index }
}

struct SymbolParent: Component {
    let box: SymbolBox
    var content: some ElementGroup {
        let scale = box.scale, variants = box.variants
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(0..<4), id: \.self) { i in
                SymbolPanel(index: i).equatable().imageScale(scale).symbolVariant(variants)
            }
        }
    }
}

@MainActor func symbolWindow(retain: Bool = true) throws -> (TestWindow, SymbolBox) {
    let box = SymbolBox()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(400, 100), colorScheme: .light, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { SymbolParent(box: box) }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, box)
}

@Suite(.serialized) @MainActor
struct RetainedSymbolImageTests {
    private func widths(_ window: TestWindow) -> [Float] { window.scene.images.map { $0.bounds.size.width } }

    /// An `imageScale` change misses every panel and re-measures: the quads go from 34 to 46 device pixels wide (`star` at 13 pt,
    /// medium 17 pt, large 23 pt, probe S1), as in a retention-off twin; a `symbolVariant` change swaps `star` for `star.fill`
    /// (same size, so read through the texture identity). **Mutation:** `imageScale` removed from `retainedFingerprint`
    /// (the retained window keeps 34).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func anImageScaleChangeAboveAnEquatablePanelRemeasuresIt() throws {
        let (on, onBox) = try symbolWindow()
        let (off, offBox) = try symbolWindow(retain: false)
        try #require(widths(on) == [34, 34, 34, 34] && widths(off) == [34, 34, 34, 34], "set up: \(widths(on)) \(widths(off))")
        onBox.scale = .large; offBox.scale = .large
        on.window.setNeedsRedraw(); on.tick()
        off.window.setNeedsRedraw(); off.tick()
        #expect(widths(off) == [46, 46, 46, 46], "the twin: \(widths(off))")
        #expect(widths(on) == widths(off), "the retained window re-measured: \(widths(on))")
    }

    /// A `symbolVariant` change reaches the panels (the texture identity changes to the `star.fill` raster). **Mutation:**
    /// `symbolVariants` removed from `retainedFingerprint`.
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func aSymbolVariantChangeAboveAnEquatablePanelRedraws() throws {
        let (on, onBox) = try symbolWindow()
        let before = on.scene.textures.map { ObjectIdentifier($0) }
        try #require(!before.isEmpty)
        onBox.variants = .fill
        on.window.setNeedsRedraw(); on.tick()
        let after = on.scene.textures.map { ObjectIdentifier($0) }
        #expect(after != before, "the filled star is a different raster")
    }

    @Test func theSymbolFieldsAreNamedInTheFingerprint() {
        var a = EnvironmentValues(), b = EnvironmentValues()
        #expect(a.retainedFingerprint == b.retainedFingerprint)
        b.imageScale = .large
        #expect(b.retainedFingerprint.differences(from: a.retainedFingerprint) == ["imageScale"])
        b = a; b.symbolVariants = .fill
        #expect(b.retainedFingerprint.differences(from: a.retainedFingerprint) == ["symbolVariants"])
        b = a; b.symbolRenderingMode = .hierarchical
        #expect(b.retainedFingerprint.differences(from: a.retainedFingerprint) == ["symbolRenderingMode"])
        a.imageScale = .large
        b = a
        #expect(a.retainedFingerprint == b.retainedFingerprint, "equal values are an equal fingerprint")
    }
}

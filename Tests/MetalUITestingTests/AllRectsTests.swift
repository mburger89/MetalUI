import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Alloy: a rounded clip around an island moved the clipped content's rects into offscreen groups, so a test reading
// `scene.rects` lost them (ruling `CT-D`, record 292; the rects' counterpart of `CT-A`'s `allGlyphs`). `TestWindow.allRects` and
// `allImages` read the root scene and, recursively, every offscreen group. **Red before the change** (the accessors absent;
// with them, mutation M1: not recursing into `groupScenes`: the group arms; M2: also reading `groupMasks`: the mask arm).

private enum RectWrap: String, CaseIterable, Sendable {
    case none, rounded, ellipse, crossing
    /// Whether the wrap builds an offscreen group around the content.
    var group: Bool { self == .ellipse || self == .crossing }
}

private let red = Color(red: 1, green: 0, blue: 0)

@MainActor private func swatch() -> some ElementGroup {
    VStack(alignment: .leading, spacing: Pixels(0)) { red.frame(width: Pixels(100), height: Pixels(40)) }
        .frame(width: Pixels(150), height: Pixels(60), alignment: .topLeading)
}

@MainActor private func window(_ wrap: RectWrap) throws -> TestWindow {
    let size = Size(width: Pixels(300), height: Pixels(300))
    let w: TestWindow
    switch wrap {
    case .none: w = try TestWindow(size: size, textSystem: harnessTextSystem) { VStack { swatch() }.frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading) }
    case .rounded:
        w = try TestWindow(size: size, textSystem: harnessTextSystem) { VStack { swatch() }.frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: Pixels(10))) }
    case .ellipse:
        w = try TestWindow(size: size, textSystem: harnessTextSystem) { VStack { swatch() }.frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading).clipShape(Ellipse()) }
    case .crossing:
        w = try TestWindow(size: size, textSystem: harnessTextSystem) {
            VStack { swatch() }.frame(width: Pixels(150), height: Pixels(60), alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: Pixels(4)))
                .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: Pixels(80)))
        }
    }
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    return w
}

/// The swatch's rects: saturated red, whatever the group.
private func reds(_ rects: [MUIRect]) -> [MUIRect] { rects.filter { $0.background.s > 0.9 && $0.background.a > 0.3 } }

@MainActor
struct AllRectsTests {
    /// **1 (`CT-D`).** Whatever wraps the swatch, the window draws one red rect, at the unwrapped one's place, and `allRects` finds
    /// it; a group wrap holds it in a group scene and none in the root (what `scene.rects` read). Mutation **M1**: the group arms.
    @Test(arguments: RectWrap.allCases)
    fileprivate func everyWrapDrawsTheUnwrappedRect(wrap: RectWrap) throws {
        let plain = try window(.none)
        let w = try window(wrap)
        let expected = try #require(reds(plain.allRects).first)
        let found = reds(w.allRects)
        #expect(found.count == 1, "\(wrap): \(found.count) red rects")
        if let rect = found.first {
            #expect(rect.bounds.origin.x == expected.bounds.origin.x && rect.bounds.origin.y == expected.bounds.origin.y, "\(wrap): the unwrapped place")
            #expect(rect.bounds.size.width == expected.bounds.size.width && rect.bounds.size.height == expected.bounds.size.height, "\(wrap): the unwrapped size")
        }
        if wrap.group {
            #expect(w.scene.groupScenes.count == 1, "\(wrap): one group")
            #expect(reds(w.scene.rects).isEmpty, "\(wrap): the root scene holds none of the group's rects")
        } else {
            #expect(w.scene.groupScenes.isEmpty, "\(wrap): no group")
            #expect(reds(w.scene.rects).count == 1)
        }
    }

    /// **2 (`CT-D`).** `allRects` is exactly the root's rects when there is no group, and is longer by the groups' own rects when
    /// there is one.
    @Test(arguments: RectWrap.allCases)
    fileprivate func allRectsIsTheRootsPlusTheGroupsOwn(wrap: RectWrap) throws {
        let w = try window(wrap)
        let own = w.scene.groupScenes.reduce(0) { $0 + $1.rects.count }
        #expect(w.allRects.count == w.scene.rects.count + own, "\(wrap)")
        if !wrap.group { #expect(w.allRects.count == w.scene.rects.count) }
    }

    /// **3 (`CT-D`).** A clip's mask scene is not ink: the crossing wrap's mask holds white coverage rects, and `allRects` has none
    /// of them. Mutation **M2** (also reading `groupMasks`).
    @Test func aMaskScenesRectsAreNotInk() throws {
        let w = try window(.crossing)
        let masks = w.scene.groupMasks.compactMap { $0 }
        let maskRects = masks.flatMap(\.rects)
        #expect(!maskRects.isEmpty, "the crossing clip builds a mask of rects")
        let white = w.allRects.filter { $0.background.s < 0.01 && $0.background.l > 0.99 && $0.background.a > 0.99 }
        #expect(white.isEmpty, "no mask coverage among the window's rects: \(white.count)")
    }

    #if os(macOS)
    /// **4 (`CT-D`).** `allImages` reaches an image (a symbol) inside a masked group, which `scene.images` does not.
    @Test(arguments: [RectWrap.none, .crossing])
    fileprivate func allImagesReachesTheGroups(wrap: RectWrap) throws {
        let size = Size(width: Pixels(300), height: Pixels(300))
        func star() -> some ElementGroup { VStack(alignment: .leading, spacing: Pixels(0)) { Image(systemName: "star").font(.system(size: 30)) } }
        let w: TestWindow
        if wrap == .none {
            w = try TestWindow(size: size, textSystem: harnessTextSystem) { VStack { star() } }
        } else {
            w = try TestWindow(size: size, textSystem: harnessTextSystem) {
                VStack { star() }.frame(width: Pixels(150), height: Pixels(60), alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: Pixels(4)))
                    .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: Pixels(80)))
            }
        }
        for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
        #expect(w.allImages.count == 1, "\(wrap): one symbol image")
        if wrap == .crossing { #expect(w.scene.images.isEmpty, "inside the group, not the root") }
    }
    #endif
}

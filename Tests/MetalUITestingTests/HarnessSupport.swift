import Foundation
import MetalUI
import MetalUIPortableText
import MetalUITesting

// The public harness's own tests (spec §4.1, lane 1): portable, run on macOS,
// Linux and Windows, with PLAIN imports of `MetalUI` and `MetalUITesting` —
// what an app's test target can write (ruling `HT-N`'s footing). Text uses
// `PortableTextSystem` over Noto Sans on every platform (ruling `HT-J`), so
// a literal agrees on all three; layout literals use fixed-size frames.

/// Noto Sans, read once from `Tests/Fonts` by `#filePath`.
@MainActor let harnessFontBytes: [UInt8] = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")
    guard let data = try? Data(contentsOf: url) else {
        preconditionFailure("Tests/Fonts/NotoSans-Regular.ttf is missing")
    }
    return [UInt8](data)
}()

/// A fresh `PortableTextSystem` over Noto Sans — one per window, as `App` makes
/// one per window.
@MainActor func harnessTextSystem() -> any TextSystem {
    guard let resolver = try? PortableFontResolver(defaultFont: harnessFontBytes) else {
        preconditionFailure("Noto Sans did not load")
    }
    return PortableTextSystem(resolver: resolver)
}

/// A point in window points.
func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

/// A size in window points.
func sz(_ width: Float, _ height: Float) -> Size<Pixels> { Size(width: Pixels(width), height: Pixels(height)) }

/// A rect in window points.
func rect(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: sz(width, height))
}

/// A 400 × 300 harness window over `content`, text through Noto Sans.
@MainActor func harnessWindow<Root: Element>(
    size: Size<Pixels> = Size(width: Pixels(400), height: Pixels(300)),
    colorScheme: ColorScheme = .light, scaleFactor: Float = 1,
    options: HeadlessPlatformWindow.Options = .init(),
    recordsLayout: Bool = true,
    _ content: @escaping @MainActor () -> Root
) throws -> TestWindow {
    try TestWindow(size: size, colorScheme: colorScheme, scaleFactor: scaleFactor, options: options,
                   recordsLayout: recordsLayout, textSystem: harnessTextSystem, content: content)
}

/// A string log the trees' handlers append to.
@MainActor final class HarnessLog {
    var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}

/// The rects of the last presented scene `height` device pixels tall.
@MainActor func rects(_ window: TestWindow, height: Float) -> [MUIRect] {
    window.scene.rects.filter { $0.bounds.size.height == height }
}

/// A presented rect's device bounds as (x, y, width, height).
func xywh(_ rect: MUIRect) -> [Float] {
    [rect.bounds.origin.x, rect.bounds.origin.y, rect.bounds.size.width, rect.bounds.size.height]
}

import Foundation
import MetalUIPortableText
import MetalUIScene
import MetalUITerminal
import MetalUITextSystem
@testable import MetalUITerminalUI
#if os(macOS)
import MetalUIText
#endif

/// Noto Sans, read once from `Tests/Fonts` by `#filePath` (the harness's own footing, `HT-J`): the portable system
/// is deterministic on every platform, so literals pinned against it hold on macOS, Linux and Windows.
@MainActor let notoBytes: [UInt8] = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts/NotoSans-Regular.ttf")
    guard let data = try? Data(contentsOf: url) else { preconditionFailure("Tests/Fonts/NotoSans-Regular.ttf is missing") }
    return [UInt8](data)
}()

@MainActor func portableSystem() -> any TextSystem {
    guard let resolver = try? PortableFontResolver(defaultFont: notoBytes) else { preconditionFailure("Noto Sans did not load") }
    return PortableTextSystem(resolver: resolver)
}

/// The rows a fresh emulator publishes after `input` (a full frame), in order.
func terminalRows(_ input: String, cols: Int = 80, rows: Int = 24) -> [TerminalRow] {
    let emulator = TerminalEmulator(cols: cols, rows: rows)
    Array(input.utf8).withUnsafeBytes { emulator.feed($0) }
    return emulator.publishSnapshot().damagedRows.sorted { $0.index < $1.index }.map(\.row)
}

@MainActor func makeSink(_ atlas: GlyphAtlas = GlyphAtlas(width: 512, height: 512)) -> SurfaceTextSink {
    let sink = SurfaceTextSink(atlas: atlas)
    sink.beginSurface(SurfaceID(rawValue: 1))
    return sink
}

/// A cache and painter over Noto Sans (the portable system) at `scale`, 14 points.
@MainActor func notoPainter(scale: Float = 1, scheme: TerminalColorScheme = .xterm)
    -> (TerminalRowPainter, TerminalGlyphCache) {
    let cache = TerminalGlyphCache(system: portableSystem(), family: nil, size: 14, scale: scale)
    return (TerminalRowPainter(cache: cache, scheme: scheme), cache)
}

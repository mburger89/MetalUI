import MetalUICore
import MetalUITextSystem

/// Renders `content` into a `Scene` exactly as one frame of a window of `size`
/// would, with no platform, window or GPU — the scene a `WindowRenderer`
/// would be handed (ruling DC-A). For snapshot tests and headless capture:
/// the same tree gives the same scene on every platform (`XP-C`).
///
/// `atlas` receives the glyph coverage the scene samples; pass the same atlas
/// to the renderer. The frame is the first a fresh window draws: no pointer,
/// no focus, no animation in flight.
@MainActor
public func renderFrame<Root: Element>(_ content: () -> Root, size: Size<Pixels>, scaleFactor: Float,
                                       textSystem: any TextSystem, atlas: GlyphAtlas,
                                       theme: Theme = .light) -> Scene {
    let frame = Frame(contentSize: size, scaleFactor: scaleFactor, textSystem: textSystem,
                      glyphAtlas: atlas, theme: theme)
    var root = content()
    frame.render(&root)
    return frame.finalizedScene()
}

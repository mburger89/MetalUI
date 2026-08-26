import MetalUI

/// Milestone 1's exit criterion: a nested flex layout that resizes correctly,
/// plus a light/dark switch.
///
/// **Nothing here names a colour literal** (spec §7.9) — every fill is a
/// `ColorToken` the frame's theme resolves. Nothing here names a scale factor
/// either: `PaintPass.fill` applies it once, so every constant below is in
/// logical points and stays that size physically on a Retina display.
///
/// The layout is deliberately **non-square and four levels deep**, because a
/// square or shallow one cannot show the two things this demo exists to prove:
/// a square window hides an axis transposition, and a single-level tree makes
/// absolute and parent-relative coordinates coincide (practices doc, shape 2).
@MainActor
func demoContent() -> some Element {
    Column(gap: Pixels(12)) {
        // Header: a fixed-height row whose second child eats the slack, so a
        // horizontal resize is visible even where nothing else moves.
        Row(gap: Pixels(12)) {
            Box()
                .width(Pixels(40)).height(Pixels(40))
                .background(.accent)
                .cornerRadius(Pixels(20))
            Box()
                .height(Pixels(12))
                .flexGrow(1)
                .background(.surfaceSecondary)
                .cornerRadius(Pixels(6))
        }
        .height(Pixels(72))
        .padding(Pixels(16))
        .alignItems(.center)
        .background(.surface)
        .cornerRadius(Pixels(14))

        // A hairline. A separator is a thin filled box, which is why
        // `ColorToken.separator` is a token the renderer can actually honour.
        Box()
            .height(Pixels(1))
            .background(.separator)

        // Body: the row that absorbs every vertical resize.
        Row(gap: Pixels(12)) {
            // Fixed-width sidebar. Its children have no width of their own and
            // reach full width through `align-items: stretch` (ruling EP-6),
            // which is also what keeps them visible: an `auto` cross size
            // resolves to 0 in this engine, so an unstretched child would paint
            // nothing at all. See CLAUDE.md's inert table.
            Column(gap: Pixels(10)) {
                Box().height(Pixels(26)).background(.accent).cornerRadius(Pixels(6))
                Box().height(Pixels(26)).background(.surfaceSecondary).cornerRadius(Pixels(6))
                Box().height(Pixels(26)).background(.surfaceSecondary).cornerRadius(Pixels(6))
                Box().height(Pixels(26)).background(.surfaceSecondary).cornerRadius(Pixels(6))
            }
            .width(Pixels(196))
            .padding(Pixels(14))
            .background(.surface)
            .cornerRadius(Pixels(14))

            Column(gap: Pixels(12)) {
                Box()
                    .height(Pixels(128))
                    .background(.accent)
                    .cornerRadius(Pixels(12))
                // Three unequal weights: 1 / 2 / 1. Equal ones would still look
                // right under a grow term that ignored the weight entirely.
                Row(gap: Pixels(12)) {
                    Box().flexGrow(1).background(.surfaceSecondary).cornerRadius(Pixels(10))
                    Box().flexGrow(2).background(.surfaceSecondary).cornerRadius(Pixels(10))
                    Box().flexGrow(1).background(.surfaceSecondary).cornerRadius(Pixels(10))
                }
                .flexGrow(1)
            }
            .flexGrow(1)
            .padding(Pixels(16))
            .background(.surface)
            .cornerRadius(Pixels(14))
        }
        .flexGrow(1)
    }
    .padding(Pixels(16))
    .background(.background)
}

@MainActor
func runDemo() throws {
    let app = try App()

    // Non-square on purpose, and wider than tall: a square window cannot show a
    // width/height transposition.
    let window = try app.openWindow(title: "MetalUI — Milestone 1",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: demoContent)

    // Two independent ways to see the theme switch, because they fail
    // separately. The system path (§7.9) is the real one — toggle Appearance in
    // System Settings or Control Center and the window follows
    // `NSApp.effectiveAppearance`. The space bar below sets `window.theme`
    // directly, so a human can compare the two variants without leaving the app;
    // a later system change overwrites it, which is the correct precedence and
    // not a bug to chase.
    //
    // Both paths are covered by tests up to the point where the scene is handed
    // to the renderer. What the demo adds, and no test can, is that the frame
    // reaches a drawable someone is looking at — `MetalLayerSurface` vends
    // drawables just as happily into an orphaned layer.
    window.onInput = { [weak window] event in
        guard let window,
              case .keyDown(let key) = event,
              key.charactersIgnoringModifiers == " " else { return false }
        window.theme = window.theme == .dark ? .light : .dark
        return true
    }

    app.run()
}

try runDemo()

import MetalUI

/// Milestone 1's exit criterion: a nested flex layout that resizes correctly,
/// plus a light/dark switch. **And milestone 2's**, which is the reason the
/// three `Text` runs below are here rather than in a test.
///
/// Spec §4.2 names three failure modes that **no assertion in this repo can
/// see**, because there is no oracle for a rendered glyph the way there is a
/// browser for a layout: a **wrong glyph** (an atlas key collision — requesting
/// `"SFMono-Regular"` by name returns a font whose PostScript name is
/// `Helvetica` on the machine this was measured on, which is why nothing may be
/// keyed on a family name), **fuzzy or wobbling text** (the subpixel variant or
/// the scale factor missing from the atlas key), and **intermittent blank runs**
/// (a glyph evicted while the frame that references it is still being built).
/// All three are *key* failures: the CPU and the GPU agree on a wrong answer
/// together, so every byte-exact test in the suite passes. A human looking at
/// this window is the only check, and the three runs below are chosen to make
/// each mode show itself — see the comments at each.
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
        // Kept although ruling EP-8 now makes it the default, because it is the
        // one container here where centring is what the design *wants* — a 40pt
        // avatar and a 12pt bar on a common centre line — rather than something
        // it inherited. Both children declare a cross size, so this row needed
        // no change; every other container below did.
        .alignItems(.center)
        .background(.surface)
        .cornerRadius(Pixels(14))

        // A hairline. A separator is a thin filled box, which is why
        // `ColorToken.separator` is a token the renderer can actually honour.
        // It declares no width: it spans whatever its parent is, and the root
        // column's `.alignItems(.stretch)` below is what says so.
        Box()
            .height(Pixels(1))
            .background(.separator)

        // Body: the row that absorbs every vertical resize.
        Row(gap: Pixels(12)) {
            // Fixed-width sidebar. Its rows declare a height and no width:
            // they fill the sidebar, and `.alignItems(.stretch)` is where the
            // demo says that rather than inheriting it.
            //
            // **This is ruling EP-8 in one line.** EP-6 kept CSS's `stretch` as
            // `Column`/`Row`'s default because an `auto` cross size resolved to
            // 0, so a centred child here would have painted nothing — a
            // mechanism, not a preference. Content sizing implemented the
            // recursive subtree measurement EP-6 named as its blocker, the
            // reason expired, and EP-8 took SwiftUI's answer (EP-5): stacks
            // centre. **A childless `Box` still measures 0**, so these four
            // would be 0 wide and invisible without the modifier below. That is
            // the cost EP-8 accepted, and the remedy is exactly this — say
            // "these fill their container" out loud, rather than hardcoding
            // 196 - 28 into four children that would then silently disagree
            // with the padding above them.
            Column(gap: Pixels(10)) {
                // **The single-line path, and M2's exit criterion has two
                // halves — this is the first.** A `Text` narrower than its
                // container never reaches `CTTypesetterSuggestLineBreak`'s
                // wrapping branch at all, so it exercises shaping, the atlas
                // and the glyph draw and nothing else. If this word is legible
                // and the paragraph below is not, the fault is in wrapping; if
                // neither is, it is in the atlas or the draw path.
                Text("Library")
                Box().height(Pixels(26)).background(.accent).cornerRadius(Pixels(6))
                Box().height(Pixels(26)).background(.surfaceSecondary).cornerRadius(Pixels(6))
                Box().height(Pixels(26)).background(.surfaceSecondary).cornerRadius(Pixels(6))
                Box().height(Pixels(26)).background(.surfaceSecondary).cornerRadius(Pixels(6))
            }
            .width(Pixels(196))
            .padding(Pixels(14))
            .alignItems(.stretch)
            .background(.surface)
            .cornerRadius(Pixels(14))

            Column(gap: Pixels(12)) {
                Box()
                    .height(Pixels(128))
                    .background(.accent)
                    .cornerRadius(Pixels(12))

                // **A second size, and it is a diagnostic rather than
                // decoration.** The atlas key is
                // `(resolvedFontKey, glyphID, size, subpixelVariant,
                // scaleFactor)` (spec §3.5). Every letter of "Text renders" at
                // 22pt also occurs in the paragraph below at 13pt, so a key
                // that dropped `size` would serve one of the two from the
                // other's slot and the mismatch is visible without measuring
                // anything: a heading built from body-sized glyphs, or the
                // reverse.
                Text("Text renders").font(size: 22)

                // **The wrapping path.** No width is declared: the column's
                // `.alignItems(.stretch)` below gives this leaf the pane's
                // content width as a definite cross extent, `flexBaseSize`
                // offers that same extent when it measures the leaf's height,
                // and `textMeasure`'s `.definite(w)` row typesets at it — so
                // the paragraph re-wraps on every horizontal resize with no
                // constant in this file naming a width. The string is long
                // enough to take three or more lines at the 920pt default and
                // to change its line count well before the window reaches its
                // minimum size.
                //
                // **Two lines of it are the milestone's own record**, so that
                // what is on screen and what is written down are the same
                // sentence.
                Text("""
                     CoreText shapes this paragraph, a shelf packer places \
                     each glyph in an R8 atlas exactly once, and the fragment \
                     shader tints the coverage it samples with the theme's \
                     text colour. Drag the window's edge and watch the line \
                     breaks move: layout asks this leaf to measure itself at \
                     the width it was offered, and paint re-shapes at the \
                     width layout settled on.
                     """)

                // **The clipping-and-scroll milestone's exit criterion.**
                // Replaces the three-weights filler row (M1's flexGrow demo,
                // now covered by the sidebar rows and the header bar above) with
                // a `ScrollView` over 40 rows — the one element in this file
                // that exercises rectangular clipping, wheel routing with
                // trackpad momentum, an indicator painted over text, and the
                // corner-radius gap between what this box asks for and what it
                // gets.
                //
                // **`ScrollView` has no modifier surface** — it conforms to
                // `Element`, not `StyledElement` — so nothing here can call
                // `.height(_:)` or `.flexGrow(_:)` on it directly. Measured
                // (a throwaway probe against this exact tree) rather than
                // assumed: giving the wrapping `Box` an explicit height alone
                // does NOT bound the viewport, because CSS Sizing §4.5's
                // automatic minimum floors a container at its CONTENT height on
                // whichever axis is its MAIN axis relative to ITS OWN parent —
                // here, height — and this engine implements only the content
                // half of that floor (ruling FS-3), so an explicit height is
                // silently overridden back up to the full 1120pt of stacked
                // rows. Two things fix it, both on the wrapping `Box` alone:
                // `.minHeight(Pixels(0))` replaces the automatic (content-based)
                // floor with a literal zero, and `.flexGrow(1).flexBasis(Pixels(0))`
                // makes the box's HEIGHT grow-derived rather than content-derived,
                // so it takes exactly the pane's leftover vertical space and
                // reflows on resize. The automatic minimum only ever binds an
                // item's MAIN axis, so the viewport's HEIGHT — the wrapping
                // `Box`'s CROSS axis, since it keeps `Box`'s default `.row`
                // direction — reaches it cleanly through ordinary
                // `align-items: stretch`, with no override needed there.
                //
                // **Width takes the opposite route, and is a real cost.** The
                // same automatic-minimum gap means nothing here can make the
                // viewport's WIDTH responsive either — it is `ScrollView`'s own
                // MAIN axis relative to this wrapping `Box`, and there is no
                // modifier to grow it. Each row below is pinned to a literal
                // 420pt instead, which is what fixes the viewport's own
                // content-based width at exactly 420 regardless of the pane's
                // available space; the wrapping `Box` repeats the same literal
                // so its rounded background matches the viewport with no gap.
                // Unlike the height fix, this one does not reflow on resize —
                // the same trade-off the 196pt sidebar above already makes.
                Box {
                    ScrollView(.vertical) {
                        for i in 0..<40 {
                            // Alternating row backgrounds, deliberately painted
                            // edge-to-edge with the viewport: `cornerRadius`
                            // below only rounds THIS box's own background —
                            // the clip stack `ScrollView` pushes is a
                            // rectangular `Bounds` (`Frame.activeClip`), so a
                            // row scrolled to the very top or bottom paints
                            // square into the corner its rounded container
                            // left transparent, and the rounding never shows
                            // through. `Box.cornerRadius`'s doc comment names
                            // the same limitation; ruling CL-A in
                            // `docs/superpowers/2026-08-28-clipping-scroll-decisions.md`
                            // names this exact demo as where it is visible.
                            Box(decoration: Decoration(
                                background: i.isMultiple(of: 2) ? .surface : .surfaceSecondary)) {
                                Text("Row \(i + 1) of 40 — a scrollable list item")
                            }
                            .padding(Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(12)),
                                          bottom: .pixels(Pixels(0)), left: .pixels(Pixels(12))))
                            .height(Pixels(28))
                            .width(Pixels(420))
                            // Vertical centring within the row; horizontal
                            // stays flex-start, the ordinary reading direction
                            // for a list item's label.
                            .alignItems(.center)
                        }
                    }
                }
                .width(Pixels(420))
                .flexGrow(1)
                .flexBasis(Pixels(0))
                .minHeight(Pixels(0))
                .background(.surface)
                .cornerRadius(Pixels(14))
            }
            .flexGrow(1)
            .padding(Pixels(16))
            // The hero box and the row of weights each declare one axis and
            // fill the other.
            .alignItems(.stretch)
            .background(.surface)
            .cornerRadius(Pixels(14))
        }
        .flexGrow(1)
        // Sidebar and main pane are full-height columns side by side.
        .alignItems(.stretch)
    }
    .padding(Pixels(16))
    // Header, hairline and body are full-width bands stacked down the window.
    .alignItems(.stretch)
    .background(.background)
}

@MainActor
func runDemo() throws {
    let app = try App()

    // Non-square on purpose, and wider than tall: a square window cannot show a
    // width/height transposition.
    let window = try app.openWindow(title: "MetalUI — Milestones 1 and 2",
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

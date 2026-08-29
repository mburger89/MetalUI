import MetalUI

/// Whether the modal is on screen. Toggled by the **M** key (`runDemo` below)
/// and read by `demoContent`, which `Window` re-invokes every frame — so
/// flipping this and marking the window dirty is the whole mechanism.
///
/// **Default `false`, and that is the load-bearing half.** An always-on modal
/// lays a translucent scrim over the entire window, and this one file carries
/// the exit criteria of four milestones: M1's nested reflow, M2's "the
/// paragraph renders legibly" — a *contrast* judgement — and the
/// clipping-and-scroll looks that chased an indicator against a rounded corner.
/// Every one of those would have paid a third of a stop of dimming forever to
/// buy this milestone's criterion once.
///
/// **And gating it makes this milestone's own criterion stronger, not weaker.**
/// A human toggling M separates "the modal covers the window" from "the modal
/// replaced the window" by watching the transition, rather than inferring it
/// from the scrim's alpha.
///
/// **Four things to report, and the fourth is a report rather than a
/// pass/fail.** The scrim covers the whole window rather than the 420pt scroll
/// viewport; the panel and scrim paint over rows declared after them; the modal
/// does not move when the list scrolls; and — **wheeling over the scrim** —
/// whether the list moves underneath it. Expect that it **does**: this scrim is
/// not a `ScrollView`, so it registers no scroll region, and `Frame.scrollRegions`
/// is the only hitbox list the framework has. An overlay that does not itself
/// scroll cannot block input until §8.1's general hitbox list exists. What a
/// hoisted subtree *does* now win is the neighbouring case — a `ScrollView`
/// inside a `Deferred` outranks one it paints over, because the registration
/// carries its layer (`Frame.scrollRegions`, ruling AP-N).
///
/// **No `@MainActor` attribute, deliberately** — this is top-level code in
/// `main.swift`, where the compiler rejects an explicit global actor
/// ("top-level code variables cannot have a global actor") because it already
/// isolates them to the main actor for you.
var showModal = false

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
                // **The Stack milestone's exit criterion.** Replaces the
                // plain accent hero box with a `Stack` of three children of
                // visibly different sizes — a backdrop, a "photo" panel
                // nested inside it, and a numeral badge nested inside that —
                // all centred on one another rather than sequenced.
                //
                // **Z-order is the one thing about a `Stack` no positional
                // test can see.** Every rect's `(x, y, width, height)` comes
                // out identical whichever child painted first, so a
                // regression that reversed paint order would leave all 517+
                // layout tests green; only a human looking at the window can
                // tell that "3" is drawn ON the panel rather than the panel
                // painting over it. That is why this element, and not a unit
                // test, is what the milestone's exit criterion asks a human
                // to look at (CLAUDE.md records whether that look has
                // happened yet).
                //
                // Declaration order is back-to-front (the `Stack` TYPE's doc
                // comment, `Stack.swift` — not `Stack.paint`'s, which says
                // only why the stack's own background is emitted before its
                // children; `paint` itself just calls `content.paintGroup`
                // and the ordering claim is one level up): the backdrop is
                // declared first and painted
                // first, the badge is declared last and painted last, so it
                // sits on top. If the order in this file were reversed, the
                // backdrop — the largest child, exactly covering the
                // container — would paint over both smaller children and
                // "3" would vanish entirely; that is the plainly-wrong
                // result a flipped z-order produces here.
                //
                // `.alignSelf(.flexStart)` opts this one item out of the
                // surrounding column's `.alignItems(.stretch)` (EP-8):
                // without it, the `Stack`'s own auto width would stretch to
                // the whole pane and the "sizes to its largest child"
                // property (`Stack.swift`'s doc comment) would be invisible
                // — the backdrop would end up centred in far more empty
                // space than its own 360×128, rather than the container
                // visibly being exactly that size.
                Stack(alignment: .center) {
                    Box()
                        .width(Pixels(360))
                        .height(Pixels(128))
                        .background(.accent)
                        .cornerRadius(Pixels(12))
                    Box()
                        .width(Pixels(160))
                        .height(Pixels(72))
                        .background(.surface)
                        .cornerRadius(Pixels(10))
                    Box(decoration: Decoration(background: .surfaceSecondary,
                                               cornerRadius: Pixels(14))) {
                        Text("3").font(size: 13)
                    }
                    .width(Pixels(28))
                    .height(Pixels(28))
                    .alignItems(.center)
                    .justifyContent(.center)
                }
                .alignSelf(.flexStart)

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
                // that exercises clipping (rectangular AND, since ruling CL-A's
                // follow-on, rounded), wheel routing with trackpad momentum,
                // and an indicator painted over text.
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
                        // **The absolute-positioning milestone's exit
                        // criterion**, and it is deliberately declared HERE —
                        // inside the scroller, above the rows — because both
                        // properties it exists to show are invisible anywhere
                        // else in this file.
                        //
                        // `Deferred` does two things and each one has a
                        // plainly-wrong failure: it hoists its subtree to the
                        // root layer, so the 40 rows declared *after* it would
                        // paint over the panel if the hoist were lost, and it
                        // resets the clip stack to the whole surface with no
                        // accumulated offset, so the scrim would be cropped to
                        // the 420pt viewport — and would slide away as the
                        // list scrolled — if the portal were lost.
                        //
                        // **Neither is checkable by any assertion over rects.**
                        // A `Deferred` contributes no layout node: its child's
                        // `(x, y, width, height)` are identical whether or not
                        // the hoist and the clip reset happen, exactly as a
                        // `Stack`'s children are identical under a reversed
                        // paint order. That is why this is a look and not a
                        // test, and why CLAUDE.md records the look as the
                        // milestone's open criterion.
                        //
                        // **`.position(.absolute)` is what "against the window"
                        // means**, mechanically: an absolute box is placed
                        // against the nearest ancestor whose position is not
                        // `.static`, and nothing between here and the root
                        // declares one — so its containing block is the root's
                        // padding box, the whole window. `inset(Pixels(0))`
                        // then gives both insets on both axes with an `auto`
                        // size, which stretches the scrim across all of it.
                        // Being absolute also takes it out of the scroll
                        // content's flow, so it adds no row and no height.
                        //
                        // **The scrim is translucent rather than opaque**, so
                        // that "the modal covers the window" and "the modal
                        // replaced the window" are distinguishable at a glance
                        // — an opaque one makes them identical to the only
                        // check that can see either. It is *gated* rather than
                        // dimmed further: see `showModal`'s own comment for why
                        // the demo must be un-scrimmed by default.
                        //
                        // **Gated on `showModal`, and the `if` has a caveat
                        // worth reading before adding state below it.** A
                        // vanishing `if` does not reset its trailing siblings'
                        // identity — it makes them ADOPT the vanished
                        // element's slot, because the cursor that assigns
                        // `.positional(_:)` components advances one place
                        // differently on the two frames. The 40 rows below
                        // hold no cross-frame state, so today this is
                        // invisible; the `ScrollView`'s own offset is keyed on
                        // the `ScrollView` node, which sits OUTSIDE this
                        // builder and does not move. If a stateful element
                        // ever lands after this `if`, the remedy is to name
                        // the *trailing sibling* with `.id(_:)` — naming the
                        // conditional content is the half that does not work
                        // (CLAUDE.md's identity bullet).
                        if showModal {
                            Deferred {
                                Stack(alignment: .center) {
                                    Column(gap: Pixels(8)) {
                                        Text("Modal").font(size: 22)
                                        Text("""
                                             Declared inside the list, painted \
                                             over it, and clipped by the window \
                                             rather than by the scroller.
                                             """)
                                    }
                                    .width(Pixels(360))
                                    .padding(Pixels(20))
                                    // The fifth `.alignItems(.stretch)` in this
                                    // file, and the only one not paying for a
                                    // childless `Box` measuring 0 (ruling
                                    // EP-8): both children here are `Text`,
                                    // which shrink-wraps correctly on a
                                    // column's cross axis since ruling TX-H. It
                                    // buys two other things. The labels read
                                    // left-aligned rather than centred, and —
                                    // the load-bearing half — each `Text` takes
                                    // the panel's whole 320pt content width, an
                                    // integer, instead of shrink-wrapping to
                                    // its own fractional max-content, which is
                                    // the input divergence 8 needs to make
                                    // paint wrap a line layout measured as
                                    // fitting.
                                    .alignItems(.stretch)
                                    .background(.surface)
                                    .cornerRadius(Pixels(16))
                                }
                                .position(.absolute)
                                .inset(Pixels(0))
                                .background(.scrim)
                            }
                        }

                        for i in 0..<40 {
                            // Alternating row backgrounds, deliberately painted
                            // edge-to-edge with the viewport: `ScrollView`'s
                            // own `.cornerRadius(_:)` below (ruling CL-A) cuts
                            // the clip to the SAME 14pt curve the wrapping
                            // `Box`'s background paints, so a row scrolled to
                            // the very top or bottom is cut by that curve too
                            // instead of painting square into the corner the
                            // background left transparent. The two radii are
                            // two separate literals that must agree — nothing
                            // enforces that they do, see `ScrollView.cornerRadius`'s
                            // doc comment — and this demo is where a mismatch
                            // would show.
                            Box(decoration: Decoration(
                                background: i.isMultiple(of: 2) ? .surface : .surfaceSecondary)
                            ) {
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
                    .cornerRadius(Pixels(14))
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
            // The hero box declares its height and fills its width from
            // here, and so does the wrapping paragraph — which is what makes
            // it re-wrap on resize. (This used to name "the row of weights";
            // the clipping-and-scroll milestone replaced that row with the
            // `ScrollView` box above, which declares both of its axes and
            // takes nothing from this line.)
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
    //
    // **M toggles the modal**, and the key was chosen for not colliding with
    // the space bar above. `Window` re-invokes the content closure every frame
    // and marks itself dirty after every input event either way, so flipping
    // `showModal` here is the whole mechanism — there is no hit-testing in the
    // framework yet and this needs none.
    window.onInput = { [weak window] event in
        guard let window, case .keyDown(let key) = event else { return false }
        switch key.charactersIgnoringModifiers {
        case " ":
            window.theme = window.theme == .dark ? .light : .dark
            return true
        case "m", "M":
            showModal.toggle()
            return true
        default:
            return false
        }
    }

    app.run()
}

try runDemo()

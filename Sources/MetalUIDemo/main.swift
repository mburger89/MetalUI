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
/// **Four things to report, and the fourth's expected answer INVERTED with the
/// input-and-state milestone.** The scrim covers the whole window rather than
/// the 420pt scroll viewport; the panel and scrim paint over rows declared
/// after them; the modal does not move when the list scrolls; and — **wheeling
/// over the scrim** — whether the list moves underneath it. It must now
/// **not**, where three milestones of this comment said it would.
///
/// **What changed is the scrim, not only the framework.** §8.1's general hitbox
/// list exists and wheel routing walks it, so an opaque hitbox over the list
/// swallows the wheel; this scrim used to register none, because `Deferred` and
/// `Box` contribute no `insertHitbox` call on their own. It now carries
/// `.onClick { showModal = false }`, and `onClick` is exactly what makes an
/// element an opaque hit target — so the wheel stops there and the list does
/// not move. A human who reports it still scrolling under the modal is
/// reporting a regression now rather than a known limitation.
///
/// **A hoisted subtree also wins the neighbouring case** — a `ScrollView`
/// inside a `Deferred` outranks one it paints over, because the registration
/// carries its layer (`Hitbox.layer`, ruling AP-N).
///
/// **No `@MainActor` attribute, deliberately** — this is top-level code in
/// `main.swift`, where the compiler rejects an explicit global actor
/// ("top-level code variables cannot have a global actor") because it already
/// isolates them to the main actor for you.
var showModal = false

/// One row of the scrollable list.
///
/// **A wrapper around an `Int` exists because `List` requires
/// `Data.Element: Identifiable`, and that requirement is load-bearing rather
/// than stylistic.** A windowed row is not produced at all while it is off
/// screen, so the positional component structural identity would otherwise
/// give it moves every time the window slides. A name replaces a position, so
/// keying on the datum's own `id` is what makes a row that scrolls away and
/// back land on the same `GlobalElementID` — see `List`'s type doc, including
/// what that still does *not* buy (its `StateTable` entry is reaped while it
/// is unbuilt).
struct DemoListRow: Identifiable {
    let id: Int
}

/// How many rows the list holds.
///
/// **500 rather than the 40 this demo used before `List` existed, and the
/// number is the point.** A `for` loop over the rows builds, measures and
/// shapes every one of them every frame, on screen or not. `List` builds only
/// the rows intersecting the viewport, so a frame costs what the viewport's
/// height says and not what this constant says.
///
/// Measured on this exact tree, release, best of 200 warm renders at
/// 920x560: **1.279 ms at 40 rows and 1.273 ms at 500** — flat. The same tree
/// with the `for` loop, at this milestone's base commit, cost **5.366 ms at
/// 40 and 50.498 ms at 500**. The list is the reason the second pair of
/// numbers is not what a human sees.
let demoRowCount = 500

/// The list's data. Built once here rather than inside `demoContent`, which
/// `Window` re-invokes every frame: `List` slices this with
/// `RandomAccessCollection.index(_:offsetBy:)` and touches only the elements
/// it builds, so the array's own construction is the one per-frame cost that
/// would still be O(`demoRowCount`) if it were rebuilt each time.
let demoRows = (0..<demoRowCount).map(DemoListRow.init)

// MARK: - The counter (milestone 3's exit criterion)

/// The three actions this window binds keystrokes to.
///
/// **An `Action` is a type, not a string** (design spec §4.1), which is what
/// lets `onAction(_:_:)` be keyed by `ObjectIdentifier` and lets an action
/// bubble *past* an element that handles a different one. They are empty
/// structs here because none of them carries a payload; one that did would
/// declare stored properties and nothing else would change.
struct Increment: Action {}
struct Decrement: Action {}
/// Moves keyboard focus to the counter. Handled by `Window.onAction` rather
/// than by any element, because the element that would handle it is the one
/// that is not focused yet — with nothing focused the chain is empty and the
/// window's fallback is the only thing left to run (`Window.onAction`).
struct FocusCounter: Action {}
struct ClearFocus: Action {}
struct ToggleTheme: Action {}
struct ToggleModal: Action {}

/// The window, for the two handlers that must reach it — the focus actions.
///
/// **`weak`, and the reason is written at `Window.onAction`'s own doc**: that
/// closure is stored *on* the window, so `window.onAction = { window.… }`
/// closes a retain cycle with no frame drawn and nothing that ever clears it.
/// The keymap handlers below capture this global instead of capturing `window`,
/// and this holding it weakly is what keeps the cycle from re-forming one step
/// further out.
///
/// **No `@MainActor` attribute** for `showModal`'s reason: top-level code in
/// `main.swift` is already main-actor isolated and the compiler rejects an
/// explicit global actor here.
weak var demoWindow: Window?

/// The counter's own `GlobalElementID`, recorded by `CounterPanel` each frame.
///
/// **Focus is moved by id and nothing else can supply one.** `Window.focus(_:)`
/// takes a `GlobalElementID`, an element's identity is *structural* — its path
/// of `.positional(_:)`/`.named(_:)` components — so it is not something a
/// caller outside the tree can construct correctly by hand. The element that
/// has one is the element itself, in its own `requestLayout`, and publishing it
/// here is the demo's way of getting it to the key handler. A framework that
/// wanted focus-by-name would put this behind an API; this file is not that
/// framework.
var counterID: GlobalElementID?

/// Whether the counter has been focused once, at startup.
///
/// **Once, not every frame**, and the distinction is the whole of why this flag
/// exists rather than an unconditional `focus(_:)` call: `Window.focus(_:)`
/// marks the window dirty, so calling it on every frame would keep the display
/// link awake forever — which is milestone 4's exit criterion, sabotaged from
/// this file. (`focus(_:)` does guard on `focusedElement != id` and would be a
/// no-op after the first call anyway; the flag says so at the call site rather
/// than relying on a guard one module away.)
var didFocusCounter = false

/// **A `@State` counter with a `+`, a `-`, hover feedback, a visible focus
/// state and a keymap binding — design spec §12's milestone-3 exit criterion,
/// in one element.**
///
/// **Where it is matters: this is in the main pane and NOT inside the
/// `ScrollView`.** An `onClick` hitbox registers *opaque*, and a wheel event
/// stops at the topmost opaque hitbox and scrolls only if that hitbox is itself
/// a scroller — so a button inside the list would silently stop the list
/// scrolling over its own rect. That is CLAUDE.md's divergence 16, and putting
/// the counter here is the milestone's own mitigation for it rather than a
/// layout preference.
///
/// **`@State` is written on INPUT only.** The two closures below run from
/// `Window`'s input path, between frames; nothing in `requestLayout` writes
/// `count`. A `@State` write marks the window dirty (`StateTable.onWrite`), so
/// an element that wrote its own state every frame would pin the display link
/// awake — the same trap `didFocusCounter` above exists for.
///
/// **The element owns its own id and its own chrome.** Like `List`, this is an
/// `Element` that builds a `Box` in `requestLayout` and forwards the other two
/// phases to it: there is no `body` in this framework, and a composite element
/// is spelled by delegation.
@MainActor
struct CounterPanel: Element {
    @State var count = 0

    /// Named rather than positional, so the counter keeps its count if
    /// anything is ever inserted above it in the main pane. A name replaces a
    /// position (CLAUDE.md's identity bullet) — which also makes `counterID`
    /// above stable across a rebuild of the surrounding tree.
    var elementID: ElementID? { ElementID("counter") }

    /// The panel's chrome: minus, the readout, plus. Left-nested exactly as
    /// `@ElementBuilder`'s `buildPartialBlock` would nest it, because the three
    /// children are assembled by hand below — a builder block cannot close over
    /// the two handlers *and* be written at the point the handlers exist.
    typealias Chrome = Pair<Pair<Box<Text>, Box<Text>>, Box<Text>>

    private var built: Box<Chrome> = CounterPanel.chrome(count: 0, minus: {}, plus: {})

    /// One 36x36 square button.
    ///
    /// `hoverBackground(.accent)` is the hover affordance and `onClick` is what
    /// makes it reachable at all — a `hoverBackground` with no click handler
    /// registers no hitbox and therefore never resolves as hovered
    /// (`StyledElement.hoverBackground(_:)`). The two belong together here even
    /// though the framework keeps them separate.
    static func button(_ label: String,
                       _ handler: @escaping @MainActor () -> Void) -> Box<Text> {
        Box(decoration: Decoration(background: .surfaceSecondary,
                                   cornerRadius: Pixels(8))) {
            Text(label).font(size: 22)
        }
        .width(Pixels(36))
        .height(Pixels(36))
        .alignItems(.center)
        .justifyContent(.center)
        .hoverBackground(.accent)
        .onClick(handler)
    }

    static func chrome(count: Int,
                       minus: @escaping @MainActor () -> Void,
                       plus: @escaping @MainActor () -> Void) -> Box<Chrome> {
        let readout = Box {
            Text("Count \(count)").font(size: 22)
        }
        .width(Pixels(140))
        .height(Pixels(36))
        .alignItems(.center)
        .justifyContent(.center)

        var row = Style()
        row.flexDirection = .row
        row.gap = Axes(both: .pixels(Pixels(12)))
        row.padding = Edges(all: .pixels(Pixels(12)))
        row.alignItems = .center

        return Box(style: row,
                   decoration: Decoration(background: .surface, cornerRadius: Pixels(12)),
                   content: Pair(Pair(button("-", minus), readout), button("+", plus)))
            // **The focus affordance, and the only one this framework has.**
            // `Frame.fill` hard-codes zero border widths, so nothing above the
            // renderer can draw a ring; a token swap is what is reachable.
            // See `StyledElement.focusBackground(_:)`.
            .focusBackground(.surfaceSecondary)
            .focusable()
            // Contributed by this element and read by the keymap's `Counter`
            // predicate below. A context is contributed by any element in the
            // focus chain, focusable or not — this one happens to be both.
            .keyContext("Counter")
            .alignSelf(.flexStart)
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Box<Chrome>.Layout) {
        // Published for the `F` binding, which cannot construct this id itself.
        counterID = id
        // **In `requestLayout` rather than anywhere else, and that is forced
        // rather than chosen**: `id` is a parameter of the phase, an element's
        // identity is structural, and nothing outside the tree can construct
        // one correctly (see `counterID`'s own doc). Calling `focus(_:)` from
        // inside a frame's render is supported — `Window.drawFrameIfNeeded`'s
        // read-back applies the frame's *decision* rather than its value — and
        // it was silently discarded until that guard existed.
        if !didFocusCounter {
            didFocusCounter = true
            demoWindow?.focus(id)
        }

        // `state`, not `self`: `self` is `inout` here and cannot be captured by
        // an escaping closure, and capturing the *wrapper* is what makes the
        // write land in the right place anyway — `State` holds a class box, so
        // a copy of the wrapper writes the same `StateTable` slot the element
        // in the tree was bound to.
        let state = _count
        var box = CounterPanel.chrome(count: state.wrappedValue,
                                      minus: { state.wrappedValue -= 1 },
                                      plus: { state.wrappedValue += 1 })
        // The two keymap actions land here rather than on the buttons: a
        // binding fires against the *focus chain*, and the panel is the
        // focusable thing. Written after `chrome` rather than inside it so the
        // same `state` capture serves the pointer and the keyboard, and the two
        // provably increment the same slot.
        box = box
            .onAction(Increment.self) { _ in state.wrappedValue += 1 }
            .onAction(Decrement.self) { _ in state.wrappedValue -= 1 }
        let result = box.requestLayout(id, pass: &pass)
        built = box
        return result
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Chrome>.Layout,
                                  pass: inout PrepaintPass) -> Chrome.GroupPrepaint {
        built.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Chrome>.Layout,
                               prepaint: inout Chrome.GroupPrepaint,
                               pass: inout PaintPass) {
        built.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

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

                // **Milestone 3's exit criterion**, and it is in the main pane
                // rather than in the `ScrollView` below on purpose — an
                // `onClick` hitbox is opaque and would swallow that scroller's
                // wheel over its own rect (divergence 16). See `CounterPanel`.
                //
                // Four things a human has to look at here, and no assertion in
                // this repo can see any of them: whether clicking feels
                // responsive, whether the hover highlight tracks the pointer,
                // whether the focused panel is visibly distinguishable, and
                // whether **+** / **-** move the count once **F** has focused
                // it. CLAUDE.md records the criterion as open until somebody
                // reports.
                CounterPanel()

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
                // a `ScrollView` over the row list below — the one element in this file
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
                // here, height.
                //
                // **Ruling FS-3 has since landed — both halves of that floor
                // are implemented — and this box is STILL unaffected by it,
                // re-measured for the sizing milestone's own Task 9 rather
                // than assumed.** FS-3's fix is `min(specified size
                // suggestion, content size suggestion)`, and the specified
                // half is read from the item's own `Style.size` (an explicit
                // `.height(_:)`), which `FlexEngine` resolves only when
                // `resolveDimension` finds a definite value there. This box
                // declares no `.height(_:)` at all — only `.flexGrow(1)` and
                // `.flexBasis(Pixels(0))` below, and a flex basis is not a
                // specified size suggestion in `FlexEngine`'s reading of
                // §4.5. So the `min` still reduces to `content` here exactly
                // as it did before FS-3, and removing `.minHeight(Pixels(0))`
                // still silently overrides the box back up to the full height
                // of the stacked rows: **14000pt**, which is `demoRowCount *
                // rowHeight` and so moves with the count above rather than
                // being a constant of this tree. (Re-measured after the list
                // became a 500-row `List`; the figure here read 1120 — 40 x
                // 28 — until then, which was this tree's answer when the list
                // was a `for` loop over 40 rows. `List` declares
                // `count * rowHeight` as a fixed style property whether or
                // not those rows are built, so windowing does not lower it.)
                // Two things fix it, both on the wrapping `Box` alone:
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
                // **Width takes the opposite route, and is a real cost — but
                // NOT the same automatic-minimum gap, and this paragraph used
                // to say it was (CLAUDE.md's own divergence 5 already
                // corrected the same mistake in a report, and it never made
                // it back to this comment).** The viewport's WIDTH is
                // `ScrollView`'s own MAIN axis relative to this wrapping
                // `Box`, and there is no modifier to grow it — but the real
                // blocker, found by mutation, is that `ScrollView` conforms
                // to `Element`, not `StyledElement`, and has no modifier
                // surface at all, so nothing can reach
                // `viewportStyle.flexGrow`: setting `flexGrow = 1` there
                // (inside `ScrollView.requestLayout`) makes the viewport fill
                // at every width, an ordinary main-axis flex fact unconnected
                // to §4.5. `.minWidth(_:)` does exist on `Box` and is not an
                // unused escape either — measured bit-identical to no width
                // spelling at all. Each row below is pinned to a literal
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
                        // root layer, so the rows declared *after* it would
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
                        // differently on the two frames. The `List` below
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
                                    // the load-bearing half — each `Text`
                                    // takes the panel's whole 320pt content
                                    // width instead of shrink-wrapping to its
                                    // own max-content. **That was written to
                                    // deny divergence 8 its input, and that
                                    // reason has expired**: paint now wraps at
                                    // the width layout measured at, so a
                                    // shrink-wrapped label is safe. Kept
                                    // because it is what makes the labels share
                                    // one left edge, which is a look rather
                                    // than a workaround.
                                    .alignItems(.stretch)
                                    .background(.surface)
                                    .cornerRadius(Pixels(16))
                                    // Absorbs its own clicks so the scrim's
                                    // dismiss handler does not fire through
                                    // the panel. It registers AFTER the scrim
                                    // — a container registers before
                                    // descending — and both sit on the same
                                    // hoisted layer, so a registration-index
                                    // tie-break puts this one on top
                                    // (`topmostOpaqueHitbox`). There is no
                                    // chaining, so the scrim never sees a
                                    // click that landed here.
                                    .onClick {}
                                }
                                .position(.absolute)
                                .inset(Pixels(0))
                                .background(.scrim)
                                // **This is what makes the scrim a modal
                                // rather than a wash**, and it is spec exit
                                // criterion 4 made visible: an `onClick`
                                // registers an OPAQUE hitbox, a wheel event
                                // stops at the topmost opaque hitbox and
                                // scrolls only if that hitbox is itself a
                                // scroller, and `Deferred` has hoisted this one
                                // to the root layer over the whole window. So
                                // with the modal up, a wheel over the scrim
                                // moves nothing — the limitation three
                                // milestones recorded, closed. Clicking
                                // dismisses, which is also how a human tells
                                // the hitbox is really there.
                                .onClick { showModal = false }
                            }
                        }

                        // **`List`, not a `for` loop over every row.** A loop
                        // builds an element, measures a `Text` and shapes a
                        // string for every row in the data, whether or not it
                        // is on screen; `List` builds only the rows
                        // intersecting the viewport plus a two-row overscan,
                        // so the cost of a frame is set by the viewport's
                        // height and not by `demoRowCount`. That is why the
                        // count below can be 500 without the frame growing.
                        //
                        // **`rowHeight` is the authority for a row's height
                        // and this builder deliberately declares none.** The
                        // wrapper `Box` `List` puts around each row pins that
                        // height (and removes the automatic minimum that would
                        // otherwise let a tall string grow past it), and the
                        // row below reaches it by ordinary cross-axis stretch.
                        // Writing `.height(Pixels(28))` here as well would be
                        // a second literal that must agree with `rowHeight`
                        // and that nothing checks.
                        List(demoRows, rowHeight: Pixels(28)) { row in
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
                                background: row.id.isMultiple(of: 2) ? .surface : .surfaceSecondary)
                            ) {
                                Text("Row \(row.id + 1) of \(demoRowCount) — a scrollable list item")
                            }
                            .padding(Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(12)),
                                          bottom: .pixels(Pixels(0)), left: .pixels(Pixels(12))))
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
    let window = try app.openWindow(title: "MetalUI — Milestones 1 to 3",
                                    size: Size(width: Pixels(920), height: Pixels(560)),
                                    content: demoContent)

    // **Every key this demo binds goes through the window's keymap**, and the
    // ad-hoc `onInput` switch that used to hold space and M is gone. That is
    // milestone 3's own dogfooding: a keystroke resolves to an `Action` type,
    // the action bubbles the focus chain, and anything nothing in the chain
    // handles arrives at `Window.onAction` below. The old switch on
    // `charactersIgnoringModifiers` still worked and said nothing about the
    // subsystem this milestone built.
    //
    // **The comment this replaces claimed "there is no hit-testing in the
    // framework yet", and that is now false in three separate ways**: the frame
    // owns one hitbox list, wheel routing and click dispatch both rank against
    // it, and the counter above registers a click target on it.
    //
    // Two independent ways to see the theme switch remain, because they fail
    // separately. The system path (§7.9) is the real one — toggle Appearance in
    // System Settings or Control Center and the window follows
    // `NSApp.effectiveAppearance`. **Space** below sets `window.theme` directly,
    // so a human can compare the two variants without leaving the app; a later
    // system change overwrites it, which is the correct precedence and not a bug
    // to chase.
    //
    // Both paths are covered by tests up to the point where the scene is handed
    // to the renderer. What the demo adds, and no test can, is that the frame
    // reaches a drawable someone is looking at — `MetalLayerSurface` vends
    // drawables just as happily into an orphaned layer.
    //
    // **`=` and `-` carry `context: "Counter"`, and that is design spec §4.3
    // rather than decoration.** The predicate is matched against the contexts
    // contributed by the *focus chain*, and `CounterPanel` is the only element
    // contributing `Counter` — so the two counter bindings exist only while the
    // counter is focused, and the same keys are free for anything else the rest
    // of the time. Unfocus with **Escape** and press `=`: nothing happens, and
    // nothing swallows the keystroke either (an action nobody handles falls
    // through to `onKey` and then to `onInput`).
    //
    // `shift-+` is bound alongside `=` because `charactersIgnoringModifiers`
    // folds shift in: the same physical key reports `"="` with no modifiers and
    // `"+"` with shift, and `Keystroke.matches` compares the modifier set
    // exactly rather than by containment, so one spelling cannot cover both.
    window.keymap = Keymap {
        Binding("=", Increment(), context: "Counter")
        Binding("shift-+", Increment(), context: "Counter")
        Binding("-", Decrement(), context: "Counter")
        Binding("f", FocusCounter())
        Binding("escape", ClearFocus())
        Binding("space", ToggleTheme())
        Binding("m", ToggleModal())
    }

    // **The window's fallback, which is what makes a binding work with nothing
    // focused.** `Increment` and `Decrement` never reach here — `CounterPanel`
    // registers handlers for both and the chain runs first — so the four cases
    // below are exactly the actions no element owns.
    //
    // `[weak window]`, because this closure is stored **on** the window:
    // `window.onAction = { window.… }` closes a retain cycle immediately, with
    // no frame drawn and nothing that ever clears it (`Window.onAction`'s own
    // doc comment).
    window.onAction = { [weak window] action in
        guard let window else { return false }
        switch action {
        case is ToggleTheme:
            window.theme = window.theme == .dark ? .light : .dark
            return true
        case is ToggleModal:
            showModal.toggle()
            return true
        case is FocusCounter:
            // `counterID` is `nil` only before the first frame has been laid
            // out, and `focus(nil)` is the correct answer then rather than an
            // error: there is nothing to focus yet.
            window.focus(counterID)
            return true
        case is ClearFocus:
            window.focus(nil)
            return true
        default:
            return false
        }
    }

    // Published for `CounterPanel`, which focuses itself once on its first
    // layout so `=` and `-` work without a human having to press **F** first.
    // Assigned before `app.run()` for that reason — the first frame is drawn by
    // the display link, which does not start until then.
    //
    // **That sentence was false for the whole milestone**, and the fix is in
    // `Window`, not here: `drawFrameIfNeeded` read `focusedElement` back from
    // the frame unconditionally, overwriting a `focus(_:)` call made *during*
    // that render with the value the frame had been handed. The counter was
    // never focused at launch. The read-back is guarded now — see its comment,
    // and `focusingFromInsideAFrameSurvivesThatFrame`.
    demoWindow = window

    app.run()
}

try runDemo()

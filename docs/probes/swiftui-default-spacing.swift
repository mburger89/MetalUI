// SwiftUI probe: DEFAULT stack and grid spacing — the rule behind divergences 51
// (a VStack's text edges) and 65 (a Grid's text rows), and the bare-Spacer
// reading behind row 89. Plan R4-2 PR A (docs/superpowers/2026-11-03-default-
// spacing-decisions.md, ruling prefix DS-; record 202).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-default-spacing.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols. Run it from the repository root (the DS2 arms register the
// fonts of Tests/Fonts by a path relative to this file).
//
// NO ARM READS PIXELS. Every figure comes from layout: `NSHostingView` +
// `layoutSubtreeIfNeeded`, never `ImageRenderer` (the instrument behind row 89's
// K1/K4, whose suspicion this file tests) and never a window capture, so the
// probe runs in a locked session (see `appkit-screen-lock-state.swift`).
//
// THREE INSTRUMENTS PER PAIR, which must agree (plan section 1). A pair is
// printed as `v a=… b=… c=…  | h a=… b=… c=…` (v: a VStack, h: an HStack):
// - a  size(stack{x; y}) - size(x) - size(y) on the main axis, each size taken
//      by `Probe` (a one-child Layout) at a nil proposal, so no wrapper changes
//      the view kinds whose spacing is measured (S, in swiftui-stack-algorithms);
// - b  the gap between the PLACED rects of two background leaves (`Mark`), one
//      behind each of x and y (GS7's pattern, swiftui-grid.swift);
// - c  `subviews[0].spacing.distance(to: subviews[1].spacing, along: axis)` in a
//      custom `Layout` (`Edge`): SwiftUI's own answer to "what spacing goes
//      between these two", with no text-height rounding in it.
// A pair whose instruments differ by more than 0.02 prints `DISAGREE` and
// counts in the last lines. The mod argument (`Mod`) wraps every measured tree
// at its OUTERMOST point only (single sizes, stacks and `Edge` alike).
//
// Text is `Text("Hi")` unless a figure says otherwise (the recorded S arms use
// it). A font size `s` is `.font(.system(size: s))`.
//
// WHAT IS NOT MEASURED HERE (stated, not omitted): a real backing scale other
// than 1 (the only screen reads scale 1.0; DS3 sets the `displayScale`
// ENVIRONMENT VALUE, which is not the same thing), any pixel-level fact, and
// any arm that needs a window on a second display.
//
// RECORDED 2026-11-03 by R4-2 PR A on macOS 27.2 (26B123), `/usr/bin/swift` =
// Apple Swift 6.4.2, screen LOCKED (CGSSessionScreenIsLocked = 1,
// preflightScreenCaptureAccess false; no arm needs pixels). Exit 0. Run twice;
// the two outputs are byte-identical (`cmp` empty, 1239 lines) and are kept in
// docs/probes/swiftui-default-spacing-run.txt. `=== instruments: 922 pairs, 0
// DISAGREE`. Two instrument limits, both found by the first run and now
// handled in the harness rather than hidden: instrument a is INVALID for a
// flexible neighbour (a `Spacer`, a horizontal `Divider`: its solo size is not
// what the stack adds up), so `rep(…, flexible: true)` prints `a=n/a` and b
// and c must still agree; and an `Edge` of two `Spacer`s is never asked, so c
// prints `unread`.
//
// RE-RUN RECIPE. `/usr/bin/swift` JIT-fails with `___isPlatformVersionAtLeast`
// if this file spells `View.tag(_:)` (a macOS 26 availability check): the
// `Picker` in DS7 uses `ForEach` for that reason. Do not add a `.tag`.
//
// READING (each claim names its arms; all at the default 8 pt horizontal gap
// unless said otherwise, all in a VStack).
// - DS0 reproduces the records: every S, K0/K1b/K1/K1c, K3, K3a, SP8 and GS7
//   line MATCHES (S prints 4.742 and 8.151 where the record rounded to 4.74 and
//   8.15; the comparison is at two decimals). The three instruments agree to
//   the printed 0.001 on every pair of the file.
// - THE HORIZONTAL GAP IS 8 BESIDE EVERY NEIGHBOUR AT EVERY FONT AND SIZE
//   (DS1, DS1b, DS2 to DS13 `h` columns).
// - THE VERTICAL TEXT EDGES ARE A FUNCTION OF THE RESOLVED FONT'S METRICS, not
//   a constant (DS1, DS1b, DS2; 107 font-size rows over 12 families and sizes 6
//   to 200 including fractions). With a = ascent, d = descent, c = capHeight,
//   l = leading (CTFontGet…, NSFont's ascender/-descender/capHeight/leading;
//   `ceil` is `.up`):
//     rect|text   = d + ceil((a + d) / 10)                   max residual 0.0000
//     text|rect   = rect|text + (a - c)                      max residual 0.0010
//                   (0.001 is the probe's 3-decimal print, not a misfit)
//     text|text   = ceil(l of the LOWER text)                max residual 0.0000
//   13 pt SF: 2.742 + 2 = 4.742; + (12.568 - 9.16) = 8.151; leading 0 -> 0.
//   The step ceil((a + d) / 10) is not `ceil(a / 8)` or `floor(a / 8) + 1`
//   (both fail at s = 16.9, 24.9, 25, 200 and Geneva 48): 0 misses of 107 only
//   for `a + d` over 10. Rejected: a constant (H0: up to 110 pt off), a
//   proportional gap (H1: up to 11.3 pt), `rect|text = d + 2` (22 pt), no cap
//   height for text|rect (up to 9.3 pt). The Tests/Fonts faces fit with their
//   `hhea` metrics (NotoSans hhea 1069/-293/0 at 13 pt: 13.897, 3.809; Source
//   Sans 3 1000/-326/0: 13, 4.238), so the portable system's metrics give the
//   same figures; its `TextFontMetrics` has no cap height.
// - text|text IS THE FONT'S LEADING, so it is 0 for `.system(size:)`, a custom
//   face with leading 0 and an unset font, and a whole point for a text STYLE
//   (DS4, DS4b): `.body` 1, `.title` 1, `.title2` 2, `.title3` 3, `.headline` 1,
//   `.subheadline` 2, `.callout` 1, `.footnote` 2, `.caption`/`.caption2` 2,
//   `.largeTitle` 2 (NSFont.preferredFont's leading 0.689, 0.09, 1.979, 2.334,
//   0.689, 1.045, 0.867, 1.223, 1.379 ceil'd), and 1/1/3/2 for ArialMT,
//   Futura-Medium, DINCondensed-Bold, Geneva at 13 pt (0.425, 0.387, 2.6,
//   1.085). Unequal fonts use the LOWER text's leading (DS5: .body|.largeTitle
//   2, .largeTitle|.body 1, DIN|Arial 1, Arial|DIN 3). `.body.leading(.tight)`
//   is -1 and `.loose` 3 (-2/+2 around the style's). A style font's rect gaps
//   equal the same-size `.system` font's (DS4b `.body` 4.742/8.151).
// - What leaves the figures alone: `displayScale` as an ENVIRONMENT value 1, 2
//   and 3 (DS3), `dynamicTypeSize` through accessibility5 (DS4: the default
//   font does not scale on macOS), bold and italic (same a, d, c at 13 pt),
//   `lineSpacing`, `baselineOffset`, `kerning`, `tracking`, a second line (DS6).
//   `controlSize` acts only through the default font it selects (mini is 9 pt:
//   3.898/6.258, the DS1 9 pt row). Not measured: a real backing scale.
// - DS6: an empty `Text("")` has no vertical edges (0 beside a rect either
//   side); `Text + Text` takes the LARGER font's edges in either order
//   (mixedSum and mixedSumReversed both 9.484/16.302); a 26 pt attributed run
//   takes its own (9.484/16.302).
// - EDGES BY NEIGHBOUR KIND (DS7, DS7b, DS2 control): standard (8 against a
//   rect, a bitmap `Image`, `Color`, `Divider`, `TextField`, `Slider`, `Picker`,
//   `Stepper`, default `Button`, `.switch` Toggle, `ScrollView`, `Grid` of
//   rects, `ProgressView`; and against text the TEXT's figure above); a
//   `.plain` `Button` with a text label and a `Label` are TEXT edges (0 beside
//   text, 4.742/8.151 beside a rect); a checkbox `Toggle` is 6 beside a rect,
//   a toggle and (text's figure) text; an SF Symbol `Image` is neither (DS7b):
//   against a rect 2 above and 3 below at the default font (9 pt 1/2, 26 pt
//   3/4, 48 pt 6/7) and 0 against text and itself. DS10: a font on the STACK is
//   inherited by its Texts and changes nothing else (rect|rect 8, Button 8,
//   Toggle 6); `.system(size: 26)` on the stack gives 0 text|text and
//   `.largeTitle` 2.
// - WRAPPERS (DS8): `.padding(0)`, `.padding(.horizontal)`, a flexible frame,
//   `background`, `overlay`, `fixedSize`, `layoutPriority`, `offset`,
//   `opacity`, `border`, a `ZStack`/`Pass{}` of the text, all carry the text
//   edges. A FIXED `.frame(width:height:)` and non-zero padding give a standard
//   (8) edge on the edge they affect: `.padding(4)` 8 on all four,
//   `.padding(.top, 4)` only the top (8.151 after a text, 8 after a rect),
//   `.padding(.bottom, 4)` only the bottom.
// - MERGING (DS9, DS6): a composite's edge is the first child's (leading) and
//   the last child's (trailing) along its own axis (nested VStack, DS12 Grid
//   rows); across it, a TEXT edge wins over a standard one (HStack{rect; text}
//   beside a rect is 4.742/8.151, as FM0's 4.74 row shows) and among text edges
//   the LARGER font's wins in either order (HStack{13; 26} is the 26's
//   9.484/16.302; ZStack too). Leading in a union: the larger of two styles' (DS9: as the LOWER
//   view HStack{.body; .largeTitle} gives 2; as the upper view above a .body
//   it gives 1, the lower's).
// - SPACER (DS11): `Spacer()`'s nil minimum is a constant 8 at 9, 13 and 48 pt
//   (VStack{T; Spacer(); T} is 2 lines + 8, 13x40 at 13 pt) and no default
//   spacing is inserted beside it (b = c = 0 for text|Spacer, Spacer|text,
//   rect|Spacer).
// - GRID (DS12): the row gap is the stack rule (text/text 0, rect/text 4.742,
//   text/rect 8.151 at 13; 0, 9.484, 16.302 at 26), a mixed-cell row takes the
//   largest pair over its cells ({text,rect}/{rect,text} 8.151 at 13, 16.302 at
//   26), a spanning cell over texts gives 0, the column gap is 8 at 13 and 26,
//   explicit spacing is verbatim; as a stack child a Grid's edges are its first
//   and last ROW's (text-over-standard union within a row).
// - LAZY AND SCROLLING (DS13): `LazyVStack` and `LazyVGrid` (one column) follow
//   the text-edge rule exactly as `VStack` does (rect/text 4.742, text/text 0,
//   text/rect 8.151); `LazyHStack` and a two-column `LazyVGrid` gap are 8; a
//   `ScrollView`'s implicit stack follows it; a `ScrollView` AS A CHILD has a
//   standard edge (scroll|text is 4.742, the standard-above-text figure). MetalUI's lazy containers use one
//   constant.
// - ROW 89 (DS14), by `NSHostingView` layout, no `ImageRenderer`. The `Where`
//   replay reproduces K1 and K4 exactly (text 16 / 48 / 96 tall at frames 60 /
//   100 / 200; K1's 15.5 / 47.5 / 96 are the same lines at the renderer's
//   half-point grid): `VStack(0){para; Where{Spacer()}}`, `…Where{Spacer(minLength:
//   0)}` and `VStack(0){Where{para}; Where{Spacer()}}` (the equal-share model).
//   The BARE stack is not that: `VStack(0){para; Spacer()}` gives the text 48,
//   80 and 96 tall (3, 5, 6 lines; default spacing the same), and with
//   `Spacer(minLength: 0)` 48, 96, 96 (3, 6, 6): the spacer takes only its
//   minimum, as SP8 and MetalUI say. `Where` around ONLY THE TEXT leaves a bare
//   spacer's 48 / 80 / 96. A spacer behind `Pass{}`, `.padding(0)`, or replaced
//   by `Color.clear` is an ordinary flexible child (16 / 48 / 96). So row 89's
//   1 and 3 lines belonged to the wrapper around the spacer. Horizontally
//   (HStack(0), 300 tall) a text and a bare spacer: 60 wide text 208 tall (a
//   narrow text), 100 wide 112 tall; with `minLength: 0` 144 and 96; the
//   `Where` spacer 288 and 208.
// - NOT MEASURED HERE: a real backing scale; the portable system's own figures
//   (no SwiftUI there); text in a `Menu`, `List` row or toolbar; a locale whose
//   fonts have other metrics; fonts of fractional leading mixed in the same
//   stack beyond the arms listed; `TextField`'s own text edges (DS7 reads a
//   field beside text as a standard edge).

import AppKit
import SwiftUI
import CoreText

// ---------------- formatting ----------------
func g(_ v: CGFloat) -> String {
    if v == .infinity { return "inf" }
    let r = (Double(v) * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(r)
}
/// Two decimals, as the recorded S lines print.
func g2(_ v: CGFloat) -> String {
    let r = (Double(v) * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r)) : String(format: "%.2f", r)
}
func fmt(_ s: CGSize) -> String { "\(g(s.width))x\(g(s.height))" }
func fmt(_ r: CGRect) -> String { "(\(g(r.minX)), \(g(r.minY))) \(g(r.width))x\(g(r.height))" }
func fmt(_ p: ProposedViewSize) -> String {
    func one(_ x: CGFloat?) -> String { x.map { g($0) } ?? "nil" }
    return "\(one(p.width))x\(one(p.height))"
}
func p(_ w: CGFloat?, _ h: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: w, height: h) }
let none = ProposedViewSize(width: nil, height: nil)

// ---------------- harness ----------------
nonisolated(unsafe) var lastSize: CGSize = .zero
nonisolated(unsafe) var rects: [String: CGRect] = [:]
nonisolated(unsafe) var edgeV: CGFloat = -999
nonisolated(unsafe) var edgeH: CGFloat = -999
nonisolated(unsafe) var disagreements = 0
nonisolated(unsafe) var pairs = 0

struct Probe: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        lastSize = size
        return size
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}

/// A leaf answering `proposal ?? 10` per axis (finite only); records its last placed rect.
struct Mark: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        func f(_ x: CGFloat?) -> CGFloat { guard let x, x.isFinite else { return 10 }; return x }
        return CGSize(width: f(proposal.width), height: f(proposal.height))
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        rects[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
func mark(_ n: String) -> some View { Mark(name: n) { SwiftUI.Color.clear } }

/// Records the bounds its parent places it in (row 89's `Where`, K1 in swiftui-text-in-stacks.swift).
struct Where: Layout {
    let key: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        rects[key] = bounds
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

/// A custom layout that overrides nothing but the two required methods.
struct Pass: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.reduce(CGSize.zero) { size, subview in
            let s = subview.sizeThatFits(proposal)
            return CGSize(width: max(size.width, s.width), height: max(size.height, s.height))
        }
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, anchor: .topLeading, proposal: proposal) }
    }
}

/// Instrument c: reads the spacing preference between its first two subviews on both axes.
struct Edge: Layout {
    func read(_ subviews: Subviews) {
        guard subviews.count == 2 else { edgeV = -888; edgeH = -888; return }
        edgeV = subviews[0].spacing.distance(to: subviews[1].spacing, along: .vertical)
        edgeH = subviews[0].spacing.distance(to: subviews[1].spacing, along: .horizontal)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        read(subviews)
        return CGSize(width: 10, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        read(subviews)
        for s in subviews { s.place(at: bounds.origin, anchor: .topLeading, proposal: p(10, 10)) }
    }
}

/// A struct and not a function type, so a trailing closure never binds to it.
struct Mod { let f: (AnyView) -> AnyView
    init(_ f: @escaping (AnyView) -> AnyView) { self.f = f }
    func callAsFunction(_ v: AnyView) -> AnyView { f(v) } }
let ident = Mod { $0 }

@MainActor func host<V: View>(_ proposal: ProposedViewSize, _ view: V) -> CGSize {
    lastSize = CGSize(width: -1, height: -1)
    rects = [:]; edgeV = -999; edgeH = -999
    let h = NSHostingView(rootView: Probe(proposal: proposal) { view })
    h.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    h.layoutSubtreeIfNeeded()
    return lastSize
}
@MainActor func measure<V: View>(_ proposal: ProposedViewSize = none, _ mod: Mod = ident, @ViewBuilder _ view: () -> V) -> CGSize {
    host(proposal, mod(AnyView(view())))
}

struct Trio { var a: CGFloat, b: CGFloat, c: CGFloat
    /// Spread over the instruments that count: c is unread when it still holds
    /// the reset value (SwiftUI never asked an `Edge` of two spacers), a is
    /// set aside for a flexible neighbour (see `rep`'s `flexible`).
    func spread(skipA: Bool) -> CGFloat {
        let v = (skipA ? [b] : [a, b]) + (c == -999 ? [] : [c])
        return v.max()! - v.min()!
    }
    func text(skipA: Bool) -> String { "a=\(skipA ? "n/a" : g(a)) b=\(g(b)) c=\(c == -999 ? "unread" : g(c))" }
}
struct Gaps { var v: Trio, h: Trio }

@MainActor func gaps<A: View, B: View>(_ mod: Mod, @ViewBuilder _ x: () -> A, @ViewBuilder _ y: () -> B) -> Gaps {
    let sa = measure(none, mod) { x() }, sb = measure(none, mod) { y() }
    let sv = measure(none, mod) { VStack { x(); y() } }
    let sh = measure(none, mod) { HStack { x(); y() } }
    let av = sv.height - sa.height - sb.height, ah = sh.width - sa.width - sb.width
    _ = host(none, mod(AnyView(VStack { x().background(mark("x")); y().background(mark("y")) })))
    let rv = (rects["x"], rects["y"])
    let bv = (rv.1?.minY ?? -999) - (rv.0?.maxY ?? 0)
    _ = host(none, mod(AnyView(HStack { x().background(mark("x")); y().background(mark("y")) })))
    let rh = (rects["x"], rects["y"])
    let bh = (rh.1?.minX ?? -999) - (rh.0?.maxX ?? 0)
    _ = host(none, mod(AnyView(Edge { x(); y() })))
    return Gaps(v: Trio(a: av, b: bv, c: edgeV), h: Trio(a: ah, b: bh, c: edgeH))
}

/// Prints one pair and returns it.
@discardableResult
@MainActor func rep<A: View, B: View>(_ label: String, mod: Mod = ident, flexible: Bool = false,
                                      @ViewBuilder _ x: () -> A, @ViewBuilder _ y: () -> B) -> Gaps {
    // `flexible`: a neighbour that expands (a Spacer, a horizontal Divider) has no
    // solo size at a nil proposal that the stack's own answer adds up to, so
    // instrument a (size difference) is INVALID for it and is set aside, printed
    // `a=n/a`; b and c still have to agree.
    let r = gaps(mod, x, y)
    pairs += 1
    let bad = r.v.spread(skipA: flexible) > 0.02 || r.h.spread(skipA: flexible) > 0.02
    if bad { disagreements += 1 }
    print("\(label) | v \(r.v.text(skipA: flexible)) | h \(r.h.text(skipA: flexible))\(bad ? "  DISAGREE" : "")")
    fflush(stdout)
    return r
}

/// A stand-alone size line.
@MainActor func size<V: View>(_ label: String, _ proposal: ProposedViewSize = none, mod: Mod = ident, @ViewBuilder _ v: () -> V) {
    print("\(label) @\(fmt(proposal)): size \(fmt(measure(proposal, mod, v)))")
    fflush(stdout)
}

func R() -> some View { Rectangle().frame(width: 20, height: 20) }
func T(_ s: CGFloat) -> some View { Text("Hi").font(.system(size: s)) }

func section(_ t: String) { print("=== \(t)"); fflush(stdout) }

// ---------------- fonts ----------------
let fontDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fonts")
func registerFonts() {
    for f in ["NotoSans-Regular.ttf", "SourceSans3-Regular.otf"] {
        var err: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(fontDir.appendingPathComponent(f) as CFURL, .process, &err)
        if !ok { print("font register failed \(f): \(String(describing: err?.takeRetainedValue()))") }
    }
}

struct FC { let name: String; let font: Font; let ns: NSFont? }
func sysDesign(_ d: NSFontDescriptor.SystemDesign, _ s: CGFloat) -> NSFont? {
    NSFont.systemFont(ofSize: s).fontDescriptor.withDesign(d).flatMap { NSFont(descriptor: $0, size: s) }
}
func fontCases(_ s: CGFloat) -> [FC] {
    [FC(name: "SF", font: .system(size: s), ns: NSFont.systemFont(ofSize: s)),
     FC(name: "serif", font: .system(size: s, design: .serif), ns: sysDesign(.serif, s)),
     FC(name: "mono", font: .system(size: s, design: .monospaced), ns: sysDesign(.monospaced, s)),
     FC(name: "rounded", font: .system(size: s, design: .rounded), ns: sysDesign(.rounded, s)),
     FC(name: "Georgia", font: .custom("Georgia", size: s), ns: NSFont(name: "Georgia", size: s)),
     FC(name: "Menlo", font: .custom("Menlo-Regular", size: s), ns: NSFont(name: "Menlo-Regular", size: s)),
     FC(name: "NotoSans", font: .custom("NotoSans-Regular", size: s), ns: NSFont(name: "NotoSans-Regular", size: s)),
     FC(name: "SourceSans3", font: .custom("SourceSans3-Regular", size: s), ns: NSFont(name: "SourceSans3-Regular", size: s)),
     // Faces with a non-zero `leading` (13 pt: 0.425, 0.387, 2.6, 1.085), to see whether leading enters.
     FC(name: "ArialMT", font: .custom("ArialMT", size: s), ns: NSFont(name: "ArialMT", size: s)),
     FC(name: "Futura-Medium", font: .custom("Futura-Medium", size: s), ns: NSFont(name: "Futura-Medium", size: s)),
     FC(name: "DINCondensed-Bold", font: .custom("DINCondensed-Bold", size: s), ns: NSFont(name: "DINCondensed-Bold", size: s)),
     FC(name: "Geneva", font: .custom("Geneva", size: s), ns: NSFont(name: "Geneva", size: s))]
}
func metrics(_ f: NSFont?) -> String {
    guard let f else { return "asc=? desc=? lead=? cap=? xh=?" }
    return "asc=\(g(f.ascender)) desc=\(g(f.descender)) lead=\(g(f.leading)) cap=\(g(f.capHeight)) xh=\(g(f.xHeight))"
}

// ---------------- DS0: replays of the recorded controls ----------------
@MainActor func ds0() {
    section("DS0: replay of S, K0/K1/K3, SP8, GS7 (expected = the recorded figure; MATCH or DIFF)")
    // S, in swiftui-stack-algorithms.swift. Expected vstack/hstack figures are the recorded ones.
    func s<A: View, B: View>(_ n: String, _ exp: String, @ViewBuilder _ x: () -> A, @ViewBuilder _ y: () -> B) {
        let sa = measure { x() }, sb = measure { y() }
        let h = measure { HStack { x(); y() } }, v = measure { VStack { x(); y() } }
        let got = "hstack \(g2(h.width - sa.width - sb.width))  vstack \(g2(v.height - sa.height - sb.height))"
        print("DS0 S \(n): \(got)  \(got == exp ? "MATCH" : "DIFF (recorded \(exp))")")
    }
    func btn() -> some View { Button("B") {} }
    func tog() -> some View { Toggle("T", isOn: .constant(true)) }
    let leafV = { Mark(name: "L") { SwiftUI.Color.clear }.frame(width: 20, height: 20) }
    do {
        let r = measure { R() }
        let h0 = measure { HStack(spacing: 0) { R(); R() } }, h20 = measure { HStack(spacing: 20) { R(); R() } }
        let v20 = measure { VStack(spacing: 20) { R(); R() } }
        let got = "hstack(0) \(g(h0.width - 2 * r.width)) hstack(20) \(g(h20.width - 2 * r.width)) vstack(20) \(g(v20.height - 2 * r.height))"
        print("DS0 S control explicit: \(got)  \(got == "hstack(0) 0 hstack(20) 20 vstack(20) 20" ? "MATCH" : "DIFF")")
    }
    s("rect|rect", "hstack 8  vstack 8") { R() } _: { R() }
    s("color|color", "hstack 8  vstack 8") { SwiftUI.Color.red.frame(width: 20, height: 20) } _: { SwiftUI.Color.red.frame(width: 20, height: 20) }
    s("leaf|leaf", "hstack 8  vstack 8") { leafV() } _: { leafV() }
    s("text|text", "hstack 8  vstack 0") { Text("Hi") } _: { Text("Hi") }
    s("rect|text", "hstack 8  vstack 4.74") { R() } _: { Text("Hi") }
    s("text|rect", "hstack 8  vstack 8.15") { Text("Hi") } _: { R() }
    s("leaf|text", "hstack 8  vstack 4.74") { leafV() } _: { Text("Hi") }
    s("image|image", "hstack 8  vstack 0") { Image(systemName: "star") } _: { Image(systemName: "star") }
    s("image|text", "hstack 8  vstack 0") { Image(systemName: "star") } _: { Text("Hi") }
    s("hstack|rect", "hstack 8  vstack 8") { HStack { R() } } _: { R() }
    s("hstack|text", "hstack 8  vstack 4.74") { HStack { R() } } _: { Text("Hi") }
    s("button|button", "hstack 8  vstack 8") { btn() } _: { btn() }
    s("text|button", "hstack 8  vstack 8.15") { Text("Hi") } _: { btn() }
    s("paddedText|paddedText", "hstack 8  vstack 8") { Text("Hi").padding(4) } _: { Text("Hi").padding(4) }
    s("paddedText|rect", "hstack 8  vstack 8") { Text("Hi").padding(4) } _: { R() }
    s("toggle|toggle", "hstack 8  vstack 6") { tog() } _: { tog() }
    s("text|toggle", "hstack 8  vstack 8.15") { Text("Hi") } _: { tog() }
    do {
        let z = measure { ZStack { Text("Hi") } }, t = measure { Text("Hi") }
        let h = measure { HStack { ZStack { Text("Hi") }; Text("Hi") } }, v = measure { VStack { ZStack { Text("Hi") }; Text("Hi") } }
        let got = "hstack \(g2(h.width - z.width - t.width)) vstack \(g2(v.height - z.height - t.height))"
        print("DS0 S zstack(text)|text: \(got)  \(got == "hstack 8 vstack 0" ? "MATCH" : "DIFF")")
    }
    func k(_ n: String, _ exp: String, _ v: CGSize) {
        print("DS0 \(n): size \(fmt(v))  \(fmt(v) == exp ? "MATCH" : "DIFF (recorded \(exp))")")
    }
    k("K0 VStack(0){text; text}", "13x32", measure { VStack(spacing: 0) { Text("Hi"); Text("Hi") } })
    k("K1b VStack{text; text}", "13x32", measure { VStack { Text("Hi"); Text("Hi") } })
    k("K1 VStack{text; Spacer(); text}", "13x40", measure { VStack { Text("Hi"); Spacer(); Text("Hi") } })
    k("K1c VStack(0){text; Spacer(); text}", "13x40", measure { VStack(spacing: 0) { Text("Hi"); Spacer(); Text("Hi") } })
    k("K3 control HStack{a20; b20}", "48x20", measure { HStack { R(); R() } })
    k("K3a HStack{a20; Spacer(minLength: 0).padding(0); b20}", "40x20", measure { HStack { R(); Spacer(minLength: 0).padding(0); R() } })
    k("SP8 HStack(0){a20; Spacer(); b20} @200x50", "200x20", measure(p(200, 50)) { HStack(spacing: 0) { R(); Spacer(); R() } })
    // GS7 (swiftui-grid.swift): Grid of four Texts, each behind a background leaf.
    _ = host(none, Grid { GridRow { Text("Hi").background(mark("t1")); Text("Yo").background(mark("t2")) }
                          GridRow { Text("A").background(mark("t3")); Text("B").background(mark("t4")) } })
    let gsz = lastSize
    let got = "size \(fmt(gsz)) | " + ["t4", "t3", "t2", "t1"].map { "\($0) \(rects[$0].map(fmt) ?? "-")" }.joined(separator: " | ")
    let exp = "size 36x32 | t4 (24, 16) 9x16 | t3 (2, 16) 9x16 | t2 (21, 0) 15x16 | t1 (0, 0) 13x16"
    print("DS0 GS7 Texts [Hi, Yo] [A, B] (bg leaves): \(got)  \(got == exp ? "MATCH" : "DIFF (recorded \(exp))")")
}

// ---------------- DS1: font size sweep ----------------
let sizes: [CGFloat] = [9, 10, 11, 12, 13, 14, 15, 16, 17, 20, 24, 26, 28, 34, 48, 64, 96]
@MainActor func ds1() {
    section("DS1 (separating arm): text|text, rect|text, text|rect at every size; CoreText metrics beside the answered height")
    rep("DS1 control rect|rect") { R() } _: { R() }
    do {
        let d = measure { Text("Hi") }, s13 = measure { T(13) }
        print("DS1 control default-font Text \(fmt(d)) vs .system(size: 13) \(fmt(s13)); NSFont.systemFontSize \(g(NSFont.systemFontSize)) \(metrics(NSFont.systemFont(ofSize: NSFont.systemFontSize)))")
    }
    for s in sizes {
        let f = NSFont.systemFont(ofSize: s)
        let h = measure { T(s) }
        print("DS1 s=\(g(s)) \(metrics(f)) lineHeight(asc-desc+lead)=\(g(f.ascender - f.descender + f.leading)) height=\(g(h.height)) width=\(g(h.width))")
        rep("DS1 s=\(g(s)) text|text") { T(s) } _: { T(s) }
        rep("DS1 s=\(g(s)) rect|text") { R() } _: { T(s) }
        rep("DS1 s=\(g(s)) text|rect") { T(s) } _: { R() }
    }
}

/// DS1b: a dense sweep including fractional sizes, to separate the candidate step functions.
@MainActor func ds1b() {
    section("DS1b: every integer size 6...40 and fractional sizes (the metrics line then the three pairs, as DS1)")
    let dense: [CGFloat] = (6...40).map { CGFloat($0) } + [8.5, 12.5, 13.5, 15.9, 16.1, 16.2, 16.5, 16.9, 24.5, 24.9, 25, 25.5, 32, 32.5, 40.5, 56, 72, 128, 200]
    for s in dense {
        let f = NSFont.systemFont(ofSize: s)
        let h = measure { T(s) }
        print("DS1b s=\(g(s)) \(metrics(f)) lineHeight(asc-desc+lead)=\(g(f.ascender - f.descender + f.leading)) height=\(g(h.height)) width=\(g(h.width))")
        rep("DS1b s=\(g(s)) text|text") { T(s) } _: { T(s) }
        rep("DS1b s=\(g(s)) rect|text") { R() } _: { T(s) }
        rep("DS1b s=\(g(s)) text|rect") { T(s) } _: { R() }
    }
}

// ---------------- DS2: font families ----------------
@MainActor func ds2() {
    section("DS2: font families at 13, 26, 48 (SF, serif, mono, rounded, Georgia, Menlo, NotoSans, SourceSans3 from Tests/Fonts, and four faces with a non-zero leading)")
    for s: CGFloat in [13, 26, 48] {
        for c in fontCases(s) {
            let h = measure { Text("Hi").font(c.font) }
            print("DS2 \(c.name) s=\(g(s)) \(metrics(c.ns)) height=\(g(h.height)) width=\(g(h.width))")
            rep("DS2 \(c.name) s=\(g(s)) text|text") { Text("Hi").font(c.font) } _: { Text("Hi").font(c.font) }
            rep("DS2 \(c.name) s=\(g(s)) rect|text") { R() } _: { Text("Hi").font(c.font) }
            rep("DS2 \(c.name) s=\(g(s)) text|rect") { Text("Hi").font(c.font) } _: { R() }
        }
    }
}

// ---------------- DS3: display scale ----------------
@MainActor func ds3() {
    section("DS3: the displayScale ENVIRONMENT VALUE 1, 2, 3 (not a real backing scale; the one screen reads 1.0)")
    for sc: CGFloat in [1, 2, 3] {
        let m = Mod { AnyView($0.environment(\.displayScale, sc)) }
        for s: CGFloat in [13, 26] {
            rep("DS3 scale=\(g(sc)) s=\(g(s)) text|text", mod: m) { T(s) } _: { T(s) }
            rep("DS3 scale=\(g(sc)) s=\(g(s)) rect|text", mod: m) { R() } _: { T(s) }
            rep("DS3 scale=\(g(sc)) s=\(g(s)) text|rect", mod: m) { T(s) } _: { R() }
        }
    }
}

// ---------------- DS4: styles, dynamic type, control size, bold, italic ----------------
@MainActor func ds4() {
    section("DS4: text styles, dynamicTypeSize, controlSize, bold, italic")
    let styles: [(String, Font, NSFont.TextStyle)] = [("largeTitle", .largeTitle, .largeTitle), ("title", .title, .title1), ("title2", .title2, .title2), ("title3", .title3, .title3),
        ("headline", .headline, .headline), ("subheadline", .subheadline, .subheadline), ("body", .body, .body), ("callout", .callout, .callout),
        ("footnote", .footnote, .footnote), ("caption", .caption, .caption1), ("caption2", .caption2, .caption2)]
    for (n, f, ns) in styles {
        let h = measure { Text("Hi").font(f) }
        let pf = NSFont.preferredFont(forTextStyle: ns)
        print("DS4 style \(n) s=\(g(pf.pointSize)) \(metrics(pf)) height=\(g(h.height)) (.system(size:) of the same point size: \(g(measure { T(pf.pointSize) }.height)))")
        rep("DS4 style \(n) text|text") { Text("Hi").font(f) } _: { Text("Hi").font(f) }
        rep("DS4 style \(n) rect|text") { R() } _: { Text("Hi").font(f) }
        rep("DS4 style \(n) text|rect") { Text("Hi").font(f) } _: { R() }
    }
    for (n, d) in [("xSmall", DynamicTypeSize.xSmall), ("large", .large), ("xxxLarge", .xxxLarge), ("accessibility5", .accessibility5)] {
        let m = Mod { AnyView($0.dynamicTypeSize(d)) }
        let h = measure(none, m) { Text("Hi") }
        print("DS4 dynamicTypeSize \(n) default-font height=\(g(h.height))")
        rep("DS4 dynamicTypeSize \(n) text|text", mod: m) { Text("Hi") } _: { Text("Hi") }
        rep("DS4 dynamicTypeSize \(n) rect|text", mod: m) { R() } _: { Text("Hi") }
        rep("DS4 dynamicTypeSize \(n) text|rect", mod: m) { Text("Hi") } _: { R() }
    }
    for (n, c) in [("mini", ControlSize.mini), ("small", .small), ("regular", .regular), ("large", .large)] {
        let m = Mod { AnyView($0.controlSize(c)) }
        let h = measure(none, m) { Text("Hi") }
        print("DS4 controlSize \(n) default-font height=\(g(h.height))")
        rep("DS4 controlSize \(n) text|text", mod: m) { Text("Hi") } _: { Text("Hi") }
        rep("DS4 controlSize \(n) rect|text", mod: m) { R() } _: { Text("Hi") }
        rep("DS4 controlSize \(n) text|rect", mod: m) { Text("Hi") } _: { R() }
    }
    print("DS4 bold SF 13 \(metrics(NSFont.boldSystemFont(ofSize: 13))) height=\(g(measure { Text("Hi").bold() }.height))")
    print("DS4 italic SF 13 \(metrics(NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask))) height=\(g(measure { Text("Hi").italic() }.height))")
    rep("DS4 bold text|text") { Text("Hi").bold() } _: { Text("Hi").bold() }
    rep("DS4 bold rect|text") { R() } _: { Text("Hi").bold() }
    rep("DS4 bold text|rect") { Text("Hi").bold() } _: { R() }
    rep("DS4 italic text|text") { Text("Hi").italic() } _: { Text("Hi").italic() }
    rep("DS4 italic rect|text") { R() } _: { Text("Hi").italic() }
    rep("DS4 italic text|rect") { Text("Hi").italic() } _: { R() }
}

/// DS4b: text|text is NOT always 0. A text-STYLE font gives a whole-point gap
/// (1, 2 or 3) where `.system(size:)` and no font at all give 0. Which fonts, and what is the figure a function of?
@MainActor func ds4b() {
    section("DS4b: what makes text|text non-zero (text-style fonts), by spelling of the same 13 pt and 26 pt fonts")
    func arm(_ n: String, _ f: Font?) {
        let t = measure { Text("Hi").font(f) }
        print("DS4b \(n): height \(g(t.height))")
        rep("DS4b \(n) text|text") { Text("Hi").font(f) } _: { Text("Hi").font(f) }
        rep("DS4b \(n) rect|text") { R() } _: { Text("Hi").font(f) }
        rep("DS4b \(n) text|rect") { Text("Hi").font(f) } _: { R() }
    }
    arm("no font (nil)", nil)
    arm(".body", .body)
    arm(".system(.body)", .system(.body))
    arm(".system(.body, design: .default)", .system(.body, design: .default))
    arm(".system(.body, design: .serif)", .system(.body, design: .serif))
    arm(".body.weight(.regular)", Font.body.weight(.regular))
    arm(".body.bold()", Font.body.bold())
    arm(".body.leading(.tight)", Font.body.leading(.tight))
    arm(".body.leading(.loose)", Font.body.leading(.loose))
    arm(".system(size: 13)", .system(size: 13))
    arm(".system(size: 13, weight: .regular)", .system(size: 13, weight: .regular))
    arm(".system(size: 13, weight: .bold)", .system(size: 13, weight: .bold))
    arm("Font(NSFont.preferredFont(.body))", Font(NSFont.preferredFont(forTextStyle: .body)))
    arm("Font(NSFont.systemFont(ofSize: 13))", Font(NSFont.systemFont(ofSize: 13)))
    arm(".custom(Georgia, size: 13, relativeTo: .body)", .custom("Georgia", size: 13, relativeTo: .body))
    arm(".custom(Georgia, fixedSize: 13)", .custom("Georgia", fixedSize: 13))
    arm(".largeTitle", .largeTitle)
    arm(".largeTitle.leading(.tight)", Font.largeTitle.leading(.tight))
    arm(".largeTitle.leading(.loose)", Font.largeTitle.leading(.loose))
    arm(".system(size: 26)", .system(size: 26))
    arm(".system(.largeTitle)", .system(.largeTitle))
    arm("Font(NSFont.preferredFont(.largeTitle))", Font(NSFont.preferredFont(forTextStyle: .largeTitle)))
    arm(".title3", .title3)
    arm(".system(size: 15)", .system(size: 15))
    // The same pair under a stack-level font (DS10 spells the stack form).
    for n in ["inherit .body", "inherit .title3"] {
        let f: Font = n == "inherit .body" ? .body : .title3
        let m = Mod { AnyView($0.font(f)) }
        rep("DS4b \(n) text|text", mod: m) { Text("Hi") } _: { Text("Hi") }
    }
}

// ---------------- DS5: pairs of different fonts ----------------
@MainActor func ds5() {
    section("DS5: text|text of different fonts, both orders; equal-size different-family pairs")
    rep("DS5 control 13|13") { T(13) } _: { T(13) }
    rep("DS5 13|26") { T(13) } _: { T(26) }
    rep("DS5 26|13") { T(26) } _: { T(13) }
    rep("DS5 26|26") { T(26) } _: { T(26) }
    rep("DS5 13|48") { T(13) } _: { T(48) }
    rep("DS5 48|13") { T(48) } _: { T(13) }
    rep("DS5 13 regular|13 bold") { T(13) } _: { Text("Hi").font(.system(size: 13)).bold() }
    rep("DS5 13 bold|13 regular") { Text("Hi").font(.system(size: 13)).bold() } _: { T(13) }
    rep("DS5 13 SF|13 serif") { T(13) } _: { Text("Hi").font(.system(size: 13, design: .serif)) }
    rep("DS5 13 serif|13 SF") { Text("Hi").font(.system(size: 13, design: .serif)) } _: { T(13) }
    rep("DS5 26 SF|26 Georgia") { T(26) } _: { Text("Hi").font(.custom("Georgia", size: 26)) }
    rep("DS5 26 Georgia|26 SF") { Text("Hi").font(.custom("Georgia", size: 26)) } _: { T(26) }
    // text|text is the font's LEADING (ds4b): which of two different leadings applies?
    let body = Font.body, large = Font.largeTitle, title3 = Font.title3, sys13 = Font.system(size: 13)
    rep("DS5 leading .body(0.689 -> 1)|.largeTitle(1.379 -> 2)") { Text("Hi").font(body) } _: { Text("Hi").font(large) }
    rep("DS5 leading .largeTitle(2)|.body(1)") { Text("Hi").font(large) } _: { Text("Hi").font(body) }
    rep("DS5 leading .body(1)|.system(size: 13)(0)") { Text("Hi").font(body) } _: { Text("Hi").font(sys13) }
    rep("DS5 leading .system(size: 13)(0)|.body(1)") { Text("Hi").font(sys13) } _: { Text("Hi").font(body) }
    rep("DS5 leading .title3(3)|.body(1)") { Text("Hi").font(title3) } _: { Text("Hi").font(body) }
    rep("DS5 leading .body(1)|.title3(3)") { Text("Hi").font(body) } _: { Text("Hi").font(title3) }
    rep("DS5 leading ArialMT 13 (0.425 -> 1)|DINCondensed-Bold 13 (2.6 -> 3)") { Text("Hi").font(.custom("ArialMT", size: 13)) } _: { Text("Hi").font(.custom("DINCondensed-Bold", size: 13)) }
    rep("DS5 leading DINCondensed-Bold 13 (3)|ArialMT 13 (1)") { Text("Hi").font(.custom("DINCondensed-Bold", size: 13)) } _: { Text("Hi").font(.custom("ArialMT", size: 13)) }
    rep("DS5 leading DINCondensed-Bold 13 (3)|Geneva 13 (1.085 -> 2)") { Text("Hi").font(.custom("DINCondensed-Bold", size: 13)) } _: { Text("Hi").font(.custom("Geneva", size: 13)) }
    rep("DS5 13 NotoSans|26 SourceSans3") { Text("Hi").font(.custom("NotoSans-Regular", size: 13)) } _: { Text("Hi").font(.custom("SourceSans3-Regular", size: 26)) }
}

// ---------------- DS6: which metrics enter ----------------
enum K6: String, CaseIterable { case plain, lineSpacing10, baselineOffset8, twoLines, empty, mixedSum, mixedSumReversed, attributed, kerning, tracking }
@MainActor @ViewBuilder func v6(_ k: K6) -> some View {
    switch k {
    case .plain: Text("Hi")
    case .lineSpacing10: Text("Hi").lineSpacing(10)
    case .baselineOffset8: Text("Hi").baselineOffset(8)
    case .twoLines: Text("Hi\nYo").lineSpacing(0)
    case .empty: Text("")
    case .mixedSum: Text("a").font(.system(size: 9)) + Text("B").font(.system(size: 26))
    case .mixedSumReversed: Text("B").font(.system(size: 26)) + Text("a").font(.system(size: 9))
    case .attributed: Text(AttributedString("Hi", attributes: AttributeContainer().font(.system(size: 26))))
    case .kerning: Text("Hi").kerning(5)
    case .tracking: Text("Hi").tracking(5)
    }
}
@MainActor func ds6() {
    section("DS6: lineSpacing, baselineOffset, multi-line, empty, Text+Text, attributed")
    for k in K6.allCases {
        print("DS6 \(k.rawValue) alone: \(fmt(measure { v6(k) }))")
        rep("DS6 \(k.rawValue) X|X") { v6(k) } _: { v6(k) }
        rep("DS6 \(k.rawValue) rect|X") { R() } _: { v6(k) }
        rep("DS6 \(k.rawValue) X|rect") { v6(k) } _: { R() }
        rep("DS6 \(k.rawValue) text|X") { Text("Hi") } _: { v6(k) }
        rep("DS6 \(k.rawValue) X|text") { v6(k) } _: { Text("Hi") }
    }
}

// ---------------- DS7: neighbour kinds beside text ----------------
enum NK: String, CaseIterable { case rect, bitmap, symbol, color, divider, textField, slider, picker, stepper, button, plainButton, checkbox, switchToggle, label, scrollView, grid, progress }
let bitmap: NSImage = { let i = NSImage(size: NSSize(width: 16, height: 16)); i.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); i.unlockFocus(); return i }()
@MainActor @ViewBuilder func nk(_ k: NK) -> some View {
    switch k {
    case .rect: R()
    case .bitmap: Image(nsImage: bitmap)
    case .symbol: Image(systemName: "star")
    case .color: SwiftUI.Color.red
    case .divider: Divider()
    case .textField: TextField("t", text: .constant("x"))
    case .slider: Slider(value: .constant(0.5))
    case .picker: Picker("p", selection: .constant(1)) { ForEach([1, 2], id: \.self) { Text("\($0)") } }
    case .stepper: Stepper("s", value: .constant(1))
    case .button: Button("B") {}
    case .plainButton: Button("B") {}.buttonStyle(.plain)
    case .checkbox: Toggle("T", isOn: .constant(true))
    case .switchToggle: Toggle("T", isOn: .constant(true)).toggleStyle(.switch)
    case .label: Label("L", systemImage: "star")
    case .scrollView: ScrollView { R() }
    case .grid: Grid { GridRow { R() } }
    case .progress: ProgressView(value: 0.5)
    }
}
@MainActor func ds7() {
    section("DS7: neighbour kinds beside text at 13 and 26 (X|X, text|X, X|text)")
    for k in NK.allCases {
        print("DS7 \(k.rawValue) alone: \(fmt(measure(p(200, 200)) { nk(k) }))")
        let flex = k == .divider || k == .color || k == .scrollView || k == .progress || k == .slider || k == .textField
        rep("DS7 \(k.rawValue) X|X", flexible: flex && k == .divider) { nk(k) } _: { nk(k) }
        rep("DS7 \(k.rawValue) X|rect", flexible: flex && k == .divider) { nk(k) } _: { R() }
        rep("DS7 \(k.rawValue) rect|X", flexible: flex && k == .divider) { R() } _: { nk(k) }
        for s: CGFloat in [13, 26] {
            rep("DS7 s=\(g(s)) text|\(k.rawValue)", flexible: k == .divider) { T(s) } _: { nk(k) }
            rep("DS7 s=\(g(s)) \(k.rawValue)|text", flexible: k == .divider) { nk(k) } _: { T(s) }
        }
    }
}

/// DS7b: an SF Symbol image has edges of its own (3 below, 2 above at the default font), not the zero its pairing with text suggested.
@MainActor func ds7b() {
    section("DS7b: Image(systemName:) at several font sizes beside rect, text and itself")
    func sym(_ s: CGFloat) -> some View { Image(systemName: "star").font(.system(size: s)) }
    for s: CGFloat in [9, 13, 26, 48] {
        print("DS7b s=\(g(s)) symbol alone: \(fmt(measure { sym(s) })); text alone: \(fmt(measure { T(s) }))")
        rep("DS7b s=\(g(s)) symbol|rect") { sym(s) } _: { R() }
        rep("DS7b s=\(g(s)) rect|symbol") { R() } _: { sym(s) }
        rep("DS7b s=\(g(s)) symbol|symbol") { sym(s) } _: { sym(s) }
        rep("DS7b s=\(g(s)) symbol|text") { sym(s) } _: { T(s) }
        rep("DS7b s=\(g(s)) text|symbol") { T(s) } _: { sym(s) }
    }
    rep("DS7b default-font symbol|rect") { Image(systemName: "star") } _: { R() }
    rep("DS7b default-font rect|symbol") { R() } _: { Image(systemName: "star") }
}

// ---------------- DS8: wrappers on Text ----------------
enum WK: String, CaseIterable { case bare, padding0, padding4, paddingTop4, paddingBottom4, paddingHorizontal4, fixedFrame, flexFrame, background, overlay, fixedSize, priority, pass, zstack, offset, opacity, border }
@MainActor @ViewBuilder func wk(_ k: WK, _ s: CGFloat = 13) -> some View {
    switch k {
    case .bare: T(s)
    case .padding0: T(s).padding(0)
    case .padding4: T(s).padding(4)
    case .paddingTop4: T(s).padding(.top, 4)
    case .paddingBottom4: T(s).padding(.bottom, 4)
    case .paddingHorizontal4: T(s).padding(.horizontal, 4)
    case .fixedFrame: T(s).frame(width: 40, height: 30)
    case .flexFrame: T(s).frame(maxWidth: .infinity)
    case .background: T(s).background(SwiftUI.Color.red)
    case .overlay: T(s).overlay(SwiftUI.Color.red)
    case .fixedSize: T(s).fixedSize()
    case .priority: T(s).layoutPriority(1)
    case .pass: Pass { T(s) }
    case .zstack: ZStack { T(s) }
    case .offset: T(s).offset(x: 3, y: 3)
    case .opacity: T(s).opacity(0.5)
    case .border: T(s).border(SwiftUI.Color.red)
    }
}
@MainActor func ds8() {
    section("DS8: wrappers on a 13 pt Text, beside a rect and beside text, on both sides")
    for k in WK.allCases {
        rep("DS8 \(k.rawValue) W|W") { wk(k) } _: { wk(k) }
        rep("DS8 \(k.rawValue) W|rect") { wk(k) } _: { R() }
        rep("DS8 \(k.rawValue) rect|W") { R() } _: { wk(k) }
        rep("DS8 \(k.rawValue) W|text") { wk(k) } _: { T(13) }
        rep("DS8 \(k.rawValue) text|W") { T(13) } _: { wk(k) }
    }
    section("DS8b: the same wrappers on a 26 pt Text, beside a rect")
    for k in WK.allCases {
        rep("DS8b s=26 \(k.rawValue) W|rect") { wk(k, 26) } _: { R() }
        rep("DS8b s=26 \(k.rawValue) rect|W") { R() } _: { wk(k, 26) }
    }
}

// ---------------- DS9: merging ----------------
enum MK: String, CaseIterable { case hstackRectText, hstackTextText26, hstackText26Text, zstackRectText, vstackRectText, vstackTextRect, passRectText, vstackText26Text13, vstackText13Text26, zstackText13Text26, zstackText26Text13 }
@MainActor @ViewBuilder func mk(_ k: MK) -> some View {
    switch k {
    case .hstackRectText: HStack { R(); T(13) }
    case .hstackTextText26: HStack { T(13); T(26) }
    case .hstackText26Text: HStack { T(26); T(13) }
    case .zstackRectText: ZStack { R(); T(13) }
    case .vstackRectText: VStack { R(); T(13) }
    case .vstackTextRect: VStack { T(13); R() }
    case .passRectText: Pass { R(); T(13) }
    case .vstackText26Text13: VStack { T(26); T(13) }
    case .vstackText13Text26: VStack { T(13); T(26) }
    case .zstackText13Text26: ZStack { T(13); T(26) }
    case .zstackText26Text13: ZStack { T(26); T(13) }
    }
}
@MainActor func ds9() {
    section("DS9: merging — composite beside rect, beside 13 pt text and beside 26 pt text, on both sides")
    for k in MK.allCases {
        rep("DS9 \(k.rawValue) M|rect") { mk(k) } _: { R() }
        rep("DS9 \(k.rawValue) rect|M") { R() } _: { mk(k) }
        rep("DS9 \(k.rawValue) M|text13") { mk(k) } _: { T(13) }
        rep("DS9 \(k.rawValue) text13|M") { T(13) } _: { mk(k) }
        rep("DS9 \(k.rawValue) M|text26") { mk(k) } _: { T(26) }
        rep("DS9 \(k.rawValue) text26|M") { T(26) } _: { mk(k) }
    }
    // Union of two text edges that differ in LEADING (text|text is the leading): which edge does a composite beside a text carry?
    let bodyT = { Text("Hi").font(Font.body) }, largeT = { Text("Hi").font(Font.largeTitle) }, sysT = { Text("Hi").font(Font.system(size: 13)) }
    rep("DS9 HStack{.body; .largeTitle} | .body") { HStack { bodyT(); largeT() } } _: { bodyT() }
    rep("DS9 HStack{.body; .largeTitle} | .largeTitle") { HStack { bodyT(); largeT() } } _: { largeT() }
    rep("DS9 HStack{.largeTitle; .body} | .body") { HStack { largeT(); bodyT() } } _: { bodyT() }
    rep("DS9 HStack{.body; .system(size: 13)} | .system(size: 13)") { HStack { bodyT(); sysT() } } _: { sysT() }
    rep("DS9 HStack{.system(size: 13); .body} | .system(size: 13)") { HStack { sysT(); bodyT() } } _: { sysT() }
    rep("DS9 .body | HStack{.body; .largeTitle}") { bodyT() } _: { HStack { bodyT(); largeT() } }
    rep("DS9 .system(size: 13) | HStack{.body; .largeTitle}") { sysT() } _: { HStack { bodyT(); largeT() } }
    // FM0 (swiftui-controls-in-stacks.swift): a row of {Text; Slider} below a row of {Toggle; Spacer; Button}.
    rep("DS9 FM0 {Text; Slider}|{Toggle; Spacer; Button}") {
        HStack { Text("Hi"); Slider(value: .constant(0.5)) }
    } _: {
        HStack { Toggle("T", isOn: .constant(true)); Spacer(); Button("B") {} }
    }
}

// ---------------- DS9b: composite beside composite (R4-2 PR B follow-up, DS-G overturned) ----------------
// DS9 measured a composite beside a RECT or a single TEXT. The common shape is a composite beside a composite
// (rows of icon-and-label), which DS9 did not reach. Every pair is read by the same three instruments.
@MainActor func ds9b() {
    section("DS9b: composite beside composite — HStack{rect; text} beside itself, other composites, spacers, ZStack, Pass, and a width-only frame")
    let rt = { (s: CGFloat) in HStack { R(); T(s) } }
    let tt = { (s: CGFloat) in HStack { T(s); T(s) } }
    // beside itself, and unequal fonts
    for s: CGFloat in [13, 26] { rep("DS9b s=\(g(s)) RT|RT") { rt(s) } _: { rt(s) } }
    rep("DS9b RT13|RT26") { rt(13) } _: { rt(26) }
    rep("DS9b RT26|RT13") { rt(26) } _: { rt(13) }
    // beside the other composites, both orders
    for s: CGFloat in [13, 26] {
        rep("DS9b s=\(g(s)) RT|TT") { rt(s) } _: { tt(s) }
        rep("DS9b s=\(g(s)) TT|RT") { tt(s) } _: { rt(s) }
        rep("DS9b s=\(g(s)) RT|RR") { rt(s) } _: { HStack { R(); R() } }
        rep("DS9b s=\(g(s)) RR|RT") { HStack { R(); R() } } _: { rt(s) }
    }
    rep("DS9b RT13|TT26") { rt(13) } _: { tt(26) }
    rep("DS9b TT26|RT13") { tt(26) } _: { rt(13) }
    // images and controls with a label
    let bt = { HStack { Image(nsImage: bitmap); T(13) } }
    rep("DS9b BT|BT") { bt() } _: { bt() }
    rep("DS9b BT|text13") { bt() } _: { T(13) }
    rep("DS9b text13|BT") { T(13) } _: { bt() }
    rep("DS9b BT|rect") { bt() } _: { R() }
    rep("DS9b rect|BT") { R() } _: { bt() }
    let bu = { HStack { Button("B") {}; T(13) } }
    rep("DS9b ButT|ButT") { bu() } _: { bu() }
    rep("DS9b ButT|text13") { bu() } _: { T(13) }
    rep("DS9b text13|ButT") { T(13) } _: { bu() }
    rep("DS9b ButT|rect") { bu() } _: { R() }
    rep("DS9b rect|ButT") { R() } _: { bu() }
    let tg = { HStack { Toggle("T", isOn: .constant(true)); T(13) } }
    rep("DS9b TogT|TogT") { tg() } _: { tg() }
    rep("DS9b TogT|text13") { tg() } _: { T(13) }
    rep("DS9b text13|TogT") { T(13) } _: { tg() }
    rep("DS9b TogT|rect") { tg() } _: { R() }
    rep("DS9b rect|TogT") { R() } _: { tg() }
    // spacers inside a composite
    let ts = { HStack { T(13); Spacer() } }, rst = { HStack { R(); Spacer(); T(13) } }
    rep("DS9b TS|text13", flexible: true) { ts() } _: { T(13) }
    rep("DS9b text13|TS", flexible: true) { T(13) } _: { ts() }
    rep("DS9b TS|TS", flexible: true) { ts() } _: { ts() }
    rep("DS9b TS|rect", flexible: true) { ts() } _: { R() }
    rep("DS9b rect|TS", flexible: true) { R() } _: { ts() }
    rep("DS9b RST|text13", flexible: true) { rst() } _: { T(13) }
    rep("DS9b text13|RST", flexible: true) { T(13) } _: { rst() }
    rep("DS9b RST|RST", flexible: true) { rst() } _: { rst() }
    rep("DS9b RST|rect", flexible: true) { rst() } _: { R() }
    rep("DS9b rect|RST", flexible: true) { R() } _: { rst() }
    rep("DS9b RST|RT", flexible: true) { rst() } _: { rt(13) }
    rep("DS9b RT|RST", flexible: true) { rt(13) } _: { rst() }
    // ZStack and Pass beside HStack
    let zrt = { ZStack { R(); T(13) } }, prt = { Pass { R(); T(13) } }
    rep("DS9b ZRT|RT") { zrt() } _: { rt(13) }
    rep("DS9b RT|ZRT") { rt(13) } _: { zrt() }
    rep("DS9b PRT|RT") { prt() } _: { rt(13) }
    rep("DS9b RT|PRT") { rt(13) } _: { prt() }
    rep("DS9b ZRT|ZRT") { zrt() } _: { zrt() }
    // a width-only fixed frame (DS-G's unmeasured spelling)
    rep("DS9b T.frame(width: 100)|rect") { T(13).frame(width: 100) } _: { R() }
    rep("DS9b rect|T.frame(width: 100)") { R() } _: { T(13).frame(width: 100) }
    rep("DS9b T.frame(width: 100)|text13") { T(13).frame(width: 100) } _: { T(13) }
    rep("DS9b text13|T.frame(width: 100)") { T(13) } _: { T(13).frame(width: 100) }
    rep("DS9b T.frame(height: 30)|rect") { T(13).frame(height: 30) } _: { R() }
    rep("DS9b rect|T.frame(height: 30)") { R() } _: { T(13).frame(height: 30) }
    rep("DS9b T.frame(height: 30)|text13") { T(13).frame(height: 30) } _: { T(13) }
}

// ---------------- DS10: the stack's own environment font ----------------
@MainActor func ds10() {
    section("DS10: a font set on the STACK, not the children (mod wraps singles and stacks alike)")
    let big = Mod { AnyView($0.font(.largeTitle)) }
    rep("DS10 control no mod rect|rect") { R() } _: { R() }
    rep("DS10 control no mod rect|Text") { R() } _: { Text("Hi") }
    rep("DS10 .largeTitle rect|rect", mod: big) { R() } _: { R() }
    rep("DS10 .largeTitle rect|Text (inherits)", mod: big) { R() } _: { Text("Hi") }
    rep("DS10 .largeTitle Text|rect (inherits)", mod: big) { Text("Hi") } _: { R() }
    rep("DS10 .largeTitle Text|Text (inherit)", mod: big) { Text("Hi") } _: { Text("Hi") }
    rep("DS10 .largeTitle rect|Text 13 (own font)", mod: big) { R() } _: { T(13) }
    rep("DS10 .largeTitle Text 13|rect (own font)", mod: big) { T(13) } _: { R() }
    rep("DS10 .largeTitle Text 13|Text 13 (own font)", mod: big) { T(13) } _: { T(13) }
    let sz26 = Mod { AnyView($0.font(.system(size: 26))) }
    rep("DS10 .system(size: 26) rect|Text (inherits)", mod: sz26) { R() } _: { Text("Hi") }
    rep("DS10 .system(size: 26) Text|rect (inherits)", mod: sz26) { Text("Hi") } _: { R() }
    rep("DS10 .system(size: 26) Text|Text (inherit)", mod: sz26) { Text("Hi") } _: { Text("Hi") }
    rep("DS10 .largeTitle rect|Button", mod: big) { R() } _: { Button("B") {} }
    rep("DS10 .largeTitle Button|Button", mod: big) { Button("B") {} } _: { Button("B") {} }
    rep("DS10 .largeTitle Toggle|Toggle", mod: big) { Toggle("T", isOn: .constant(true)) } _: { Toggle("T", isOn: .constant(true)) }
}

// ---------------- DS11: Spacer ----------------
@MainActor func ds11() {
    section("DS11: Spacer() minimum and zero edges between texts at 9, 13, 48")
    for s: CGFloat in [9, 13, 48] {
        let h = measure { T(s) }.height
        let d = measure { VStack { T(s); Spacer(); T(s) } }, z = measure { VStack(spacing: 0) { T(s); Spacer(); T(s) } }
        let m0 = measure { VStack { T(s); Spacer(minLength: 0); T(s) } }, tt = measure { VStack { T(s); T(s) } }
        print("DS11 s=\(g(s)) text height=\(g(h)): VStack{T;Spacer();T} \(fmt(d)) | VStack(0){…} \(fmt(z)) | VStack{T;Spacer(minLength: 0);T} \(fmt(m0)) | VStack{T;T} \(fmt(tt)) | spacer share = \(g(d.height - 2 * h))")
        rep("DS11 s=\(g(s)) text|Spacer", flexible: true) { T(s) } _: { Spacer() }
        rep("DS11 s=\(g(s)) Spacer|text", flexible: true) { Spacer() } _: { T(s) }
        rep("DS11 s=\(g(s)) Spacer|Spacer", flexible: true) { Spacer() } _: { Spacer() }
    }
    rep("DS11 control rect|Spacer", flexible: true) { R() } _: { Spacer() }
}

// ---------------- DS12: Grid ----------------
@MainActor func gridGap<V: View>(_ label: String, _ names: (String, String), _ v: () -> V) {
    let sz = host(none, v())
    let a = rects[names.0], b = rects[names.1]
    let gv = (b?.minY ?? -999) - (a?.maxY ?? 0), gh = (b?.minX ?? -999) - (a?.maxX ?? 0)
    print("\(label): size \(fmt(sz)) | \(names.0) \(a.map(fmt) ?? "-") | \(names.1) \(b.map(fmt) ?? "-") | dy \(g(gv)) dx \(g(gh))")
    fflush(stdout)
}
@MainActor func ds12() {
    section("DS12: Grid. rows: dy is row b minus row a; cols: dx is column b minus column a")
    gridGap("DS12 control rect/rect rows", ("a", "b")) { Grid { GridRow { R().background(mark("a")) }; GridRow { R().background(mark("b")) } } }
    for s: CGFloat in [13, 26] {
        gridGap("DS12 s=\(g(s)) text/text rows", ("a", "b")) { Grid { GridRow { T(s).background(mark("a")) }; GridRow { T(s).background(mark("b")) } } }
        gridGap("DS12 s=\(g(s)) rect/text rows", ("a", "b")) { Grid { GridRow { R().background(mark("a")) }; GridRow { T(s).background(mark("b")) } } }
        gridGap("DS12 s=\(g(s)) text/rect rows", ("a", "b")) { Grid { GridRow { T(s).background(mark("a")) }; GridRow { R().background(mark("b")) } } }
        gridGap("DS12 s=\(g(s)) text|text columns", ("a", "b")) { Grid { GridRow { T(s).background(mark("a")); T(s).background(mark("b")) } } }
        gridGap("DS12 s=\(g(s)) rect|text columns", ("a", "b")) { Grid { GridRow { R().background(mark("a")); T(s).background(mark("b")) } } }
        // Mixed-cell rows (GS1): row 1 {text, rect}, row 2 {rect, text}: the gap is a pair over the cells.
        gridGap("DS12 s=\(g(s)) mixed rows {text,rect}/{rect,text} (a = text of row 1, b = text of row 2)", ("a", "b")) {
            Grid { GridRow { T(s).background(mark("a")); R() }; GridRow { R(); T(s).background(mark("b")) } } }
        gridGap("DS12 s=\(g(s)) mixed rows {text,text}/{rect,rect} (a = row 1 col 1, b = row 2 col 1)", ("a", "b")) {
            Grid { GridRow { T(s).background(mark("a")); T(s) }; GridRow { R().background(mark("b")); R() } } }
        gridGap("DS12 s=\(g(s)) mixed rows {rect,rect}/{text,text} (a = row 1 col 1, b = row 2 col 1)", ("a", "b")) {
            Grid { GridRow { R().background(mark("a")); R() }; GridRow { T(s).background(mark("b")); T(s) } } }
        gridGap("DS12 s=\(g(s)) span: row 1 one text across 2 columns, row 2 two texts", ("a", "b")) {
            Grid { GridRow { T(s).background(mark("a")).gridCellColumns(2) }; GridRow { T(s).background(mark("b")); T(s) } } }
        gridGap("DS12 s=\(g(s)) explicit verticalSpacing 0, text/text rows", ("a", "b")) {
            Grid(verticalSpacing: 0) { GridRow { T(s).background(mark("a")) }; GridRow { T(s).background(mark("b")) } } }
        gridGap("DS12 s=\(g(s)) explicit verticalSpacing 5, text/text rows", ("a", "b")) {
            Grid(verticalSpacing: 5) { GridRow { T(s).background(mark("a")) }; GridRow { T(s).background(mark("b")) } } }
    }
    // The grid as a stack child: its edge is a pair over its rows.
    rep("DS12 Grid{text;text} as a stack child: grid|text") { Grid { GridRow { Text("Hi") }; GridRow { Text("Hi") } } } _: { Text("Hi") }
    rep("DS12 Grid{text;text} as a stack child: text|grid") { Text("Hi") } _: { Grid { GridRow { Text("Hi") }; GridRow { Text("Hi") } } }
    rep("DS12 Grid{rect;text} as a stack child: grid|rect") { Grid { GridRow { R() }; GridRow { Text("Hi") } } } _: { R() }
    rep("DS12 Grid{rect;text} as a stack child: rect|grid") { R() } _: { Grid { GridRow { R() }; GridRow { Text("Hi") } } }
    // A grid ROW of mixed cells as a child: its top and bottom edge are over the row's cells.
    rep("DS12 Grid{ {rect,text} } as a stack child: grid|rect") { Grid { GridRow { R(); Text("Hi") } } } _: { R() }
    rep("DS12 Grid{ {rect,text} } as a stack child: rect|grid") { R() } _: { Grid { GridRow { R(); Text("Hi") } } }
    rep("DS12 Grid{ {text,text} } as a stack child: rect|grid") { R() } _: { Grid { GridRow { Text("Hi"); Text("Hi") } } }
    rep("DS12 Grid{ {text,text} } as a stack child: grid|rect") { Grid { GridRow { Text("Hi"); Text("Hi") } } } _: { R() }
    rep("DS12 Grid{text;rect} as a stack child: text|grid") { Text("Hi") } _: { Grid { GridRow { Text("Hi") }; GridRow { R() } } }
    rep("DS12 Grid{text;rect} as a stack child: grid|text") { Grid { GridRow { Text("Hi") }; GridRow { R() } } } _: { Text("Hi") }
}

// ---------------- DS13: lazy containers and ScrollView ----------------
@MainActor func ds13() {
    section("DS13: lazy containers and ScrollView (instrument b only; c needs a layout parent)")
    func two<V: View>(_ label: String, _ proposal: ProposedViewSize, _ v: () -> V, vertical: Bool = true) {
        _ = host(proposal, v())
        let a = rects["a"], b = rects["b"]
        let gap = vertical ? (b?.minY ?? -999) - (a?.maxY ?? 0) : (b?.minX ?? -999) - (a?.maxX ?? 0)
        print("\(label) @\(fmt(proposal)): a \(a.map(fmt) ?? "-") b \(b.map(fmt) ?? "-") gap \(g(gap))")
        fflush(stdout)
    }
    two("DS13 control VStack rect/text", none) { VStack { R().background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 LazyVStack rect/text", none) { LazyVStack { R().background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 LazyVStack text/text", none) { LazyVStack { Text("Hi").background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 LazyVStack text/rect", none) { LazyVStack { Text("Hi").background(mark("a")); R().background(mark("b")) } }
    two("DS13 LazyHStack rect/text", none, { LazyHStack { R().background(mark("a")); Text("Hi").background(mark("b")) } }, vertical: false)
    two("DS13 LazyVStack(spacing: 0) rect/text", none) { LazyVStack(spacing: 0) { R().background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 control VStack text/text", none) { VStack { Text("Hi").background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 ScrollView{VStack rect/text} 200x200", p(200, 200)) { ScrollView { VStack { R().background(mark("a")); Text("Hi").background(mark("b")) } } }
    two("DS13 ScrollView{VStack text/rect} 200x200", p(200, 200)) { ScrollView { VStack { Text("Hi").background(mark("a")); R().background(mark("b")) } } }
    two("DS13 ScrollView{rect; text} (implicit stack) 200x200", p(200, 200)) { ScrollView { R().background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 ScrollView{text; rect} (implicit stack) 200x200", p(200, 200)) { ScrollView { Text("Hi").background(mark("a")); R().background(mark("b")) } }
    two("DS13 ScrollView{text; text} (implicit stack) 200x200", p(200, 200)) { ScrollView { Text("Hi").background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 LazyVGrid 1 column rect/text 200x200", p(200, 200)) {
        LazyVGrid(columns: [GridItem(.flexible())]) { R().background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 LazyVGrid 1 column text/text 200x200", p(200, 200)) {
        LazyVGrid(columns: [GridItem(.flexible())]) { Text("Hi").background(mark("a")); Text("Hi").background(mark("b")) } }
    two("DS13 LazyVGrid 2 fixed(40) columns text|text 200x200 (gap = dx - 40; 8 expected)", p(200, 200), {
        LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))]) { Text("Hi").background(mark("a")); Text("Hi").background(mark("b")) } }, vertical: false)
    two("DS13 LazyVGrid 2 fixed(40) columns, then a second row: rows rect/text (a = col 1 row 1, b = col 1 row 2)", p(200, 200)) {
        LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))]) { R().background(mark("a")); R(); Text("Hi").background(mark("b")); R() } }
    // As a child of a stack: the lazy container's own edge.
    rep("DS13 LazyVStack{text} as child: lazy|text") { LazyVStack { Text("Hi") } } _: { Text("Hi") }
    rep("DS13 LazyVStack{text} as child: text|lazy") { Text("Hi") } _: { LazyVStack { Text("Hi") } }
    rep("DS13 LazyVStack{rect} as child: lazy|text") { LazyVStack { R() } } _: { Text("Hi") }
    rep("DS13 ScrollView{text} as child: scroll|text") { ScrollView { Text("Hi") } } _: { Text("Hi") }
}

// ---------------- DS14: row 89 ----------------
let para = "The quick brown fox jumps over the lazy dog and keeps on running far away."
@MainActor func ds14() {
    section("DS14 (row 89): text beside a Spacer at a fixed frame, NSHostingView layout only. Reads the text's placed rect (bg leaf t) and each Where's bounds")
    func line(_ label: String, _ keys: [String], _ v: () -> some View) {
        _ = host(none, v())
        print("\(label): " + keys.map { "\($0) \(rects[$0].map { "y=\(g($0.minY)) h=\(g($0.height))" } ?? "-")" }.joined(separator: " | "))
        fflush(stdout)
    }
    // Controls: the paragraph alone, and two paragraphs (K0, K3).
    line("DS14 K0 control paragraph alone, frame width 100", ["t"]) { Text(para).background(mark("t")).frame(width: 100, alignment: .topLeading).fixedSize(horizontal: false, vertical: true) }
    line("DS14 K0w control Where{paragraph} alone, frame width 100", ["w"]) { Where(key: "w") { Text(para) }.frame(width: 100, alignment: .topLeading).fixedSize(horizontal: false, vertical: true) }
    for h: CGFloat in [100, 300] {
        line("DS14 K3 control VStack(0){para; para} h=\(g(h))", ["a", "b"]) {
            VStack(spacing: 0) { Text(para).background(mark("a")); Text(para).background(mark("b")) }.frame(width: 100, height: h) }
    }
    for h: CGFloat in [60, 100, 200] {
        let tag = "h=\(g(h))"
        line("DS14 bare VStack(0){para; Spacer()} \(tag)", ["t"]) { VStack(spacing: 0) { Text(para).background(mark("t")); Spacer() }.frame(width: 100, height: h) }
        line("DS14 bare VStack(0){para; Spacer(minLength: 0)} \(tag)", ["t"]) { VStack(spacing: 0) { Text(para).background(mark("t")); Spacer(minLength: 0) }.frame(width: 100, height: h) }
        line("DS14 VStack{para; Spacer()} default spacing \(tag)", ["t"]) { VStack { Text(para).background(mark("t")); Spacer() }.frame(width: 100, height: h) }
        line("DS14 VStack(0){para; Where{Spacer()}} (K1 replay) \(tag)", ["t", "s"]) {
            VStack(spacing: 0) { Text(para).background(mark("t")); Where(key: "s") { Spacer() } }.frame(width: 100, height: h) }
        line("DS14 VStack(0){para; Where{Spacer(minLength: 0)}} (K4 replay) \(tag)", ["t", "s"]) {
            VStack(spacing: 0) { Text(para).background(mark("t")); Where(key: "s") { Spacer(minLength: 0) } }.frame(width: 100, height: h) }
        line("DS14 VStack(0){Where{para}; Spacer()} (the wrapper on the text) \(tag)", ["t", "s"]) {
            VStack(spacing: 0) { Where(key: "t") { Text(para) }; Spacer().background(mark("s")) }.frame(width: 100, height: h) }
        line("DS14 VStack(0){Where{para}; Where{Spacer()}} (K1 exactly) \(tag)", ["t", "s"]) {
            VStack(spacing: 0) { Where(key: "t") { Text(para) }; Where(key: "s") { Spacer() } }.frame(width: 100, height: h) }
        line("DS14 VStack(0){para; Pass{Spacer()}} \(tag)", ["t"]) { VStack(spacing: 0) { Text(para).background(mark("t")); Pass { Spacer() } }.frame(width: 100, height: h) }
        line("DS14 VStack(0){para; Spacer().padding(0)} \(tag)", ["t"]) { VStack(spacing: 0) { Text(para).background(mark("t")); Spacer().padding(0) }.frame(width: 100, height: h) }
        line("DS14 VStack(0){para; Color.clear} (flexible non-spacer control) \(tag)", ["t"]) { VStack(spacing: 0) { Text(para).background(mark("t")); SwiftUI.Color.clear }.frame(width: 100, height: h) }
    }
    for w: CGFloat in [60, 100, 200] {
        line("DS14 HStack(0){para; Spacer()} w=\(g(w)) (horizontal, tight)", ["t"]) { HStack(spacing: 0) { Text(para).background(mark("t")); Spacer() }.frame(width: w, height: 300) }
        line("DS14 HStack(0){para; Spacer(minLength: 0)} w=\(g(w))", ["t"]) { HStack(spacing: 0) { Text(para).background(mark("t")); Spacer(minLength: 0) }.frame(width: w, height: 300) }
        line("DS14 HStack(0){para; Where{Spacer()}} w=\(g(w))", ["t", "s"]) { HStack(spacing: 0) { Text(para).background(mark("t")); Where(key: "s") { Spacer() } }.frame(width: w, height: 300) }
    }
}

// ---------------- main ----------------
@MainActor func probes() {
    registerFonts()
    ds0(); ds1(); ds1b(); ds2(); ds3(); ds4(); ds4b(); ds5(); ds6(); ds7(); ds7b(); ds8(); ds9(); ds9b(); ds10(); ds11(); ds12(); ds13(); ds14()
    print("=== instruments: \(pairs) pairs, \(disagreements) DISAGREE")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }
print("DONE")

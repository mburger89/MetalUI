// SwiftUI probe: two-axis ScrollView and how a wheel event is routed between nested scrollers, for Alloy gap G5
// (rulings `XS-A`.. in docs/superpowers/2026-11-07-two-axis-scroll-decisions.md).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-two-axis-scroll.swift
//   xcrun swiftc -O docs/probes/swiftui-two-axis-scroll.swift -o /tmp/xs && /tmp/xs
//
// METHOD. A borderless NSWindow at the screen ORIGIN (0, 0), 300x300 unless stated, hosts the view; the instruments are
// every NSScrollView under the host (`S0` the outer, `S1` the inner): `contentView.bounds.origin` is the offset,
// `documentView.frame.size` the content, `vp` the viewport. EVENTS go through the window: `CGEvent(scrollWheelEvent2Source:
// units: .pixel)` with `.location` set to the screen point, `scrollWheelEventScrollPhase` / `MomentumPhase` /
// `IsContinuous` set, then `NSEvent(cgEvent:)` and `window.sendEvent`. `NSEvent(cgEvent:)` has `window == nil` and a SCREEN
// `locationInWindow`, so the window sits at the screen origin where the two coincide (first tries at (100, 200) delivered
// nothing: D0). Deltas are the CG wheel values: NEGATIVE moves the offset toward the end. D0 is the method control: the
// same event through `sendEvent` and through `contentView.hitTest(p).scrollWheel(with:)` must agree, phaseless
// (isContinuous 0 and 1) and phased: they do (offset 100 in all four, 100 for a 4x-25 gesture).
//
// RECORDED 2026-11-07 by the two-axis session (Alloy gap G5), macOS 27.2, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9),
// compiled (`xcrun swiftc -O`), run twice: the two stdouts are byte-identical apart from the window number (`winWN`,
// normalised below). 111 lines.
//
// THE READING (each line names the arm).
// 1. THE WHEEL GOES WHOLE TO ONE AXIS, THE DOMINANT ONE, EVEN WITHOUT A GESTURE. SwiftUI's ScrollView is an NSScrollView with
//    `usesPredominantAxisScrolling` true. A3: a phaseless diagonal (-30,-40) on a two-axis scroller moves y 40, x 0 (both
//    isContinuous values); A3b (-40,-30) moves x 40, y 0; a tie goes to y (A3d (-30,-30): y 30; A7). A phaseless event is
//    decided by itself (A3c: three x-dominant events, x 120, y 0).
// 2. A PHASED GESTURE LOCKS TO THE AXIS OF ITS FIRST EVENT. A4 y-dominant 5x(-6,-8): y 40, x 0; A4b x 40, y 0; A4c (-1,-8)
//    then 4x(-8,-1): y 12 only (the later x-dominant events are dropped); A5 y-only 3x then x-only 3x: y 30, x 0 (the lock
//    persists even when the first stage had only one component); A5b the mirror. Momentum arms (A6, A6b, N10, M0) are
//    UNREADABLE: synthetic momentum events moved nothing even on a plain scroller (M0: 40 -> 80 for two gestures, the momentum
//    adds 0), so "the lock persists through momentum" is carried from the real-device behaviour, not measured.
// 3. THE LOCK APPLIES TO ONE-AXIS SCROLLERS. A8: a vertical-only scroller under an x-dominant phased gesture (-8,-6) does not
//    move (y 0), A8b the horizontal one under a y-dominant gesture does not move, A8c phaseless (-40,-30) on a vertical
//    scroller: y 0. A one-axis scroller ignores the non-dominant component instead of reading its own.
// 4. NESTING FOLLOWS CAPABILITY, NOT TYPE (N1-N7). Outer vertical over a horizontal inner: dy over the inner moves the outer
//    (N1, 40/0), dx the inner (N2), a diagonal goes WHOLE to the dominant axis (N3: outer y 40, inner 0, NOT split; N3b inner
//    x 40, outer 0), a y-dominant gesture with x jitter all to the outer (N4 75/0), x-dominant all to the inner (N5, N5b). A
//    horizontal inner whose content fits passes dy (N6) and nothing moves on dx (N6a). A SAME-AXIS inner whose content fits
//    passes the wheel up (N6b 40/0, N6b2 phased); an overflowing one keeps it (N6c: outer 0, inner 40). The mirror (N7).
// 5. EDGE CHAINING: A ONE-AXIS SCROLLER AT ITS END PASSES THE WHEEL UP (N8). Inner vertical parked at the bottom (400): a phased
//    gesture that starts there moves the OUTER (N8a, 75), one that reaches the edge mid-gesture gives the outer the rest (N8b:
//    inner 370 -> 400, outer 45 = 75 - 30), phaseless the same (N8c both isContinuous), a second gesture too (N8d), horizontal
//    pair too (N8h); at the TOP an upward gesture moves nothing when the outer is at 0 (N8e). An x-dominant gesture over a
//    vertical inner at its end moves nothing (N8i: nobody scrolls x).
// 6. A TWO-AXIS INNER DOES NOT CHAIN AT ITS EDGE (N9c, N9d, N9e, N9f): parked at the bottom (900) or 30 short of it, a
//    vertical wheel never reaches the vertical outer (outer 0 throughout); while it has room it keeps the wheel (N9, N9b:
//    inner y 40, a diagonal goes to y too). The capability that decides is the scroller's, and a two-axis scroller swallows.
// 7. SCROLLVIEWREADER (T). `scrollTo` anchors per axis: .topLeading (500,500), .center (400,400), .top -> x CENTRED (400, 500;
//    `UnitPoint.top` has x 0.5), .leading y centred (500, 400), .bottomTrailing (300,300). anchor nil is least distance per
//    axis: target 9,9 -> (700,700); a target visible on x only leaves x (T5: 0, 300; T5b 300, 0). withAnimation ends at the same
//    offsets (T6). T7: a target inside a nested horizontal inner whose row is below the outer's fold moves ONLY the inner
//    (x 700) and NOT the outer (y 0) -- the nearest scroller only, in both the nil and .topLeading forms. (Carried to PR 2/3.)
// 8. DEFAULTSCROLLANCHOR (S). .bottomTrailing starts at (700,700), .bottom centres x (350,700), .trailing centres y (700,350).
//    Growth follows per axis (S4 900,900). THE PIN IS RELEASED PER AXIS: S5 a phased wheel away on x only (580,700) then growth
//    -> (580, 900): y keeps following; S5b the mirror (900, 580); phaseless S5c the same (660, 900).
// 9. SCROLLPOSITION(ID:) (P1) on row ids tracks the vertical axis: nil at rest, 2 after dy 250 (offset 250), UNCHANGED by a
//    dx-only wheel (2), 5 after the next dy (offset 500).
// 10. RIGHT-TO-LEFT (R1): the two-axis content opens at x 700 (the right edge, cell 0 at 200..300 of the viewport), dx -50
//    moves nothing there (it would be past the start), dx +50 moves to 650: the sign is mirrored, as for one axis (`LD-E`).
//    A following phaseless dy -50 left y at 0.0 in this window although the document is 1000 tall: UNEXPLAINED, recorded as read
//    (the x facts are what PR 2 needs; y in a right-to-left two-axis scroller is to be re-measured there).
// 11. LAYOUT (L). In THIS harness (an NSHostingView, real NSScrollViews) a two-axis viewport answers the proposal on both axes
//    (L1a 500x500 in 100x100: viewport 100x100, document 500x500; L2a 50x500 and L2b 500x50 in 300x300: viewport 300x300) while a
//    single axis shrinks the other: vertical 50x30 -> viewport 50x100, horizontal -> 100x30 (L1c, L1d, L2c, L2d). SMALL content in
//    a two-axis viewport is NOT centred here: it sits at (0,0) (L1b: content frame (0,0), document origin (0,0)), which
//    DISAGREES with `swiftui-stack-algorithms.swift` SCG2 ("both" centres at (25, 35)): the two harnesses differ (SCG2 measures
//    the SwiftUI layout, this the AppKit-backed scroller), so the centring is not ruled from this probe. L3 ScrollView([]):
//    still one NSScrollView, 300x300 document, content proposed the viewport (300x300), wheels move nothing. L4 a LazyVStack of
//    800-wide rows in a two-axis scroller is 800 x 20000 (width = the rows'), 15 rows appear at rest and a dx and a dy
//    add none (the harness's onAppear count is not a window: the stack realised 15 in 300 and, after dy 400, still 15 --
//    onAppear is not re-fired for a window move that stays in the realised set; unreadable for windowing). L5 the same on x.
// 12. SCROLLERS (A9): this machine's scrollers are the legacy style (`scrollerStyle` 1, always visible, alpha 1.0), so
//    whether both thumbs flash after a y-only gesture is UNREADABLE here; the nested pair shows the outer with a vertical
//    scroller only and the inner with a horizontal one only (A9b).
//
// WHOLE STDOUT:
//
//   === D0: delivery control (one vertical 300x300 scroller over 1000, dy -100)
//   D0 window cont=false: before S0[x=0.0 y=0.0 doc=300.0x1000.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=false vS=true pred=true elastH=1 elastV=2 frame=300.0x300.0] | ev.window==win:false evWN=0 winWN=N loc=(150.0,150.0) | after S0[x=0.0 y=100.0 doc=300.0x1000.0 vp=300.0x300.0]
//   D0 direct cont=false: before S0[x=0.0 y=0.0 doc=300.0x1000.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=false vS=true pred=true elastH=1 elastV=2 frame=300.0x300.0] | ev.window==win:false evWN=0 winWN=N loc=(150.0,150.0) | after S0[x=0.0 y=100.0 doc=300.0x1000.0 vp=300.0x300.0]
//   D0 window cont=true: before S0[x=0.0 y=0.0 doc=300.0x1000.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=false vS=true pred=true elastH=1 elastV=2 frame=300.0x300.0] | ev.window==win:false evWN=0 winWN=N loc=(150.0,150.0) | after S0[x=0.0 y=100.0 doc=300.0x1000.0 vp=300.0x300.0]
//   D0 direct cont=true: before S0[x=0.0 y=0.0 doc=300.0x1000.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=false vS=true pred=true elastH=1 elastV=2 frame=300.0x300.0] | ev.window==win:false evWN=0 winWN=N loc=(150.0,150.0) | after S0[x=0.0 y=100.0 doc=300.0x1000.0 vp=300.0x300.0]
//   D0 phased window: after phased 4x-25 S0[x=0.0 y=100.0 doc=300.0x1000.0 vp=300.0x300.0]
//   D0 phased direct: after phased 4x-25 S0[x=0.0 y=100.0 doc=300.0x1000.0 vp=300.0x300.0]
//   === A: two-axis basics (300x300 over 1000x1000)
//   A1 phaseless dx -50/c0: S0[x=50.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=true vS=true pred=true elastH=2 elastV=2 frame=300.0x300.0]
//   A2 phaseless dy -50/c0: S0[x=0.0 y=50.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A3 phaseless diagonal (-30,-40)/c0: S0[x=0.0 y=40.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A3b phaseless x-dominant (-40,-30)/c0: S0[x=40.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A3c phaseless x-dominant 3x(-40,-30) separate events/c0: S0[x=120.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A1 phaseless dx -50/c1: S0[x=50.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=true vS=true pred=true elastH=2 elastV=2 frame=300.0x300.0]
//   A2 phaseless dy -50/c1: S0[x=0.0 y=50.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A3 phaseless diagonal (-30,-40)/c1: S0[x=0.0 y=40.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A3b phaseless x-dominant (-40,-30)/c1: S0[x=40.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A3c phaseless x-dominant 3x(-40,-30) separate events/c1: S0[x=120.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A4 phased y-dominant 5x(-6,-8): S0[x=0.0 y=40.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A4b phased x-dominant 5x(-8,-6): S0[x=40.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A4c phased, first event y-dominant then x-dominant: (-1,-8) then 4x(-8,-1): S0[x=0.0 y=12.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A5 one gesture y-only 3x(0,-10) then x-only 3x(-10,0): S0[x=0.0 y=30.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A5b one gesture x-only 3x(-10,0) then y-only 3x(0,-10): S0[x=30.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A6 A4 then diagonal momentum 3x(-6,-8): S0[x=0.0 y=40.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A6b A4 then x-dominant momentum 3x(-8,-6): S0[x=0.0 y=40.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A7 overscroll 20x(-100,-100) phased, settled 1s: S0[x=0.0 y=700.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A7b reverse overscroll 5x(100,100) from origin, settled: S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   A3d phaseless tie (-30,-30): S0[x=0.0 y=30.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   M0 momentum control: vertical-only, phased 4x(0,-10) then momentum 3x(0,-10): gesture only S0[x=0.0 y=40.0 doc=300.0x1000.0 vp=300.0x300.0] | second gesture with momentum S0[x=0.0 y=80.0 doc=300.0x1000.0 vp=300.0x300.0]
//   A8 vertical-only scroller, x-dominant phased 5x(-8,-6): S0[x=0.0 y=0.0 doc=300.0x1000.0 vp=300.0x300.0]
//   A8b horizontal-only scroller, y-dominant phased 5x(-6,-8): S0[x=0.0 y=0.0 doc=1000.0x300.0 vp=300.0x300.0]
//   A8c vertical-only scroller, phaseless (-40,-30): S0[x=0.0 y=0.0 doc=300.0x1000.0 vp=300.0x300.0]
//   A9 thumbs at ~0.1 s after a y-only phased gesture (two-axis): rest S0(style=1 v:a=1.0 hid=false h:a=1.0 hid=false) | 0.1s S0(style=1 v:a=1.0 hid=false h:a=1.0 hid=false) | 1.6s S0(style=1 v:a=1.0 hid=false h:a=1.0 hid=false)
//   A9b thumbs at ~0.1 s after a y-only phased gesture (nested: outer v, inner h): 0.1s S0(style=1 v:a=1.0 hid=false h:a=-1.0 hid=true) S1(style=1 v:a=-1.0 hid=true h:a=1.0 hid=false)
//   === L: layout and lazy
//   L1a both 500x500 in 100x100: content frame in viewport (0.0,0.0) 500.0x500.0 | S0[x=0.0 y=0.0 doc=500.0x500.0 vp=100.0x100.0 docOrigin=(0.0,0.0) hS=true vS=true pred=true elastH=2 elastV=2 frame=100.0x100.0]
//   L1b both 50x30 in 100x100: content frame in viewport (0.0,0.0) 50.0x30.0 | S0[x=0.0 y=0.0 doc=50.0x30.0 vp=100.0x100.0 docOrigin=(0.0,0.0) hS=true vS=true pred=true elastH=2 elastV=2 frame=100.0x100.0]
//   L1c vertical 50x30 in 100x100: content frame in viewport (0.0,0.0) 50.0x30.0 | S0[x=0.0 y=0.0 doc=50.0x30.0 vp=50.0x100.0 docOrigin=(0.0,0.0) hS=false vS=true pred=true elastH=1 elastV=2 frame=50.0x100.0]
//   L1d horizontal 50x30 in 100x100: content frame in viewport (0.0,0.0) 50.0x30.0 | S0[x=0.0 y=0.0 doc=50.0x30.0 vp=100.0x30.0 docOrigin=(0.0,0.0) hS=true vS=false pred=true elastH=2 elastV=1 frame=100.0x30.0]
//   L2a both 50x500 in 300x300: content frame in viewport (0.0,0.0) 50.0x500.0 | S0[x=0.0 y=0.0 doc=50.0x500.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=true vS=true pred=true elastH=2 elastV=2 frame=300.0x300.0]
//   L2b both 500x50 in 300x300: content frame in viewport (0.0,0.0) 500.0x50.0 | S0[x=0.0 y=0.0 doc=500.0x50.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=true vS=true pred=true elastH=2 elastV=2 frame=300.0x300.0]
//   L2c vertical 50x500 in 300x300: content frame in viewport (0.0,0.0) 50.0x500.0 | S0[x=0.0 y=0.0 doc=50.0x500.0 vp=50.0x300.0 docOrigin=(0.0,0.0) hS=false vS=true pred=true elastH=1 elastV=2 frame=50.0x300.0]
//   L2d horizontal 500x50 in 300x300: content frame in viewport (0.0,0.0) 500.0x50.0 | S0[x=0.0 y=0.0 doc=500.0x50.0 vp=300.0x50.0 docOrigin=(0.0,0.0) hS=true vS=false pred=true elastH=2 elastV=1 frame=300.0x50.0]
//   L3 ScrollView([]) 500x500 in 300x300: scrollers=1 content (0.0,0.0) 300.0x300.0 S0[x=0.0 y=0.0 doc=300.0x300.0 vp=300.0x300.0 docOrigin=(0.0,0.0) hS=false vS=false pred=true elastH=1 elastV=1 frame=300.0x300.0] | after phaseless (-50,-50): content (0.0,0.0) 300.0x300.0 S0[x=0.0 y=0.0 doc=300.0x300.0 vp=300.0x300.0] | after phased: content (0.0,0.0) 300.0x300.0 S0[x=0.0 y=0.0 doc=300.0x300.0 vp=300.0x300.0]
//   L4 LazyVStack 1000 rows 20x800 in two-axis: rest appear=15 stack 800.0x20000.0 row0 w=800.0 | after dx -200: appear=15 stack 800.0x20000.0 row0 w=800.0 S0[x=200.0 y=0.0 doc=800.0x20000.0 vp=300.0x300.0] | after dy -400: appear=15 stack 800.0x20000.0 row0 w=800.0 S0[x=200.0 y=0.0 doc=800.0x20000.0 vp=300.0x300.0]
//   L5 LazyHStack 1000 cols 20x800 in two-axis: rest appear=15 stack 20000.0x800.0 | after dy -200: appear=15 stack 20000.0x800.0 S0[x=0.0 y=200.0 doc=20000.0x800.0 vp=300.0x300.0] | after dx -400: appear=15 stack 20000.0x800.0 S0[x=0.0 y=200.0 doc=20000.0x800.0 vp=300.0x300.0]
//   === N: nesting (outer 300x300 over 1500; inner 300x100 at content y 200..300; events at y=205)
//   N1 outer v, inner h: phaseless dy -40/c0: S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N2 phaseless dx -40/c0: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=40.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N3 phaseless diagonal (-30,-40)/c0: S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N3b phaseless x-dominant (-40,-30)/c0: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=40.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N3c phaseless (-30,-40) x2 separate events/c0: S0[x=0.0 y=80.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N1 outer v, inner h: phaseless dy -40/c1: S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N2 phaseless dx -40/c1: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=40.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N3 phaseless diagonal (-30,-40)/c1: S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N3b phaseless x-dominant (-40,-30)/c1: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=40.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N3c phaseless (-30,-40) x2 separate events/c1: S0[x=0.0 y=80.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N4 phased y-dominant with x jitter 5x(-2,-15): S0[x=0.0 y=75.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N5 phased x-dominant with y jitter 5x(-16,-2): S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=80.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N5b phased x-only 5x(-16,0): S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=80.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   N6 inner h content fits (200 wide): phaseless dy -40: S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=200.0x100.0 vp=300.0x100.0]
//   N6a same, phaseless dx -40: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=200.0x100.0 vp=300.0x100.0]
//   N6a2 same, phaseless diagonal (-30,-40): S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=200.0x100.0 vp=300.0x100.0]
//   N6a3 same, phased dx-dominant 5x(-16,-2): S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=200.0x100.0 vp=300.0x100.0]
//   N6b outer v, inner v whose content fits (50 in 100): phaseless dy -40: S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=300.0x50.0 vp=300.0x100.0]
//   N6b2 same, phased 5x(0,-8): S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=300.0x50.0 vp=300.0x100.0]
//   N6c control outer v, inner v overflowing (500 in 100): phaseless dy -40: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=40.0 doc=300.0x500.0 vp=300.0x100.0]
//   N7 outer h, inner v (dx -40 at x=205): dx: S0[x=40.0 y=0.0 doc=1500.0x300.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=100.0x1000.0 vp=100.0x300.0]
//   N7b outer h, inner v (dy -40 at x=205): dy: S0[x=0.0 y=0.0 doc=1500.0x300.0 vp=300.0x300.0] S1[x=0.0 y=40.0 doc=100.0x1000.0 vp=100.0x300.0]
//   N7c outer h, inner v, phased x-dominant 5x(-16,-2): S0[x=80.0 y=0.0 doc=1500.0x300.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=100.0x1000.0 vp=100.0x300.0]
//   N8a inner parked at bottom; phased gesture starts there 5x(0,-15): parked S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0] | S0[x=0.0 y=75.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0]
//   N8b inner parked 30 short; phased gesture reaches the edge mid-gesture 5x(0,-15): parked S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=370.0 doc=300.0x500.0 vp=300.0x100.0] | S0[x=0.0 y=45.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0]
//   N8c inner parked at bottom; phaseless dy -40/c0: parked S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0] | S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0]
//   N8c inner parked at bottom; phaseless dy -40/c1: parked S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0] | S0[x=0.0 y=40.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0]
//   N8d inner at bottom; gesture ends, then a SECOND phased gesture starts there 3x(0,-15): first S0[x=0.0 y=45.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0] | second S0[x=0.0 y=90.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0]
//   N8e inner parked at TOP (0), gesture upward (dy +) 5x(0,15) with the outer at 0: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=300.0x500.0 vp=300.0x100.0]
//   N9 two-axis inner in vertical outer: phaseless dy -40: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=40.0 doc=1000.0x1000.0 vp=300.0x100.0]
//   N9b same, phaseless diagonal (-30,-40): S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=40.0 doc=1000.0x1000.0 vp=300.0x100.0]
//   N9c same, inner parked at bottom (900), phaseless dy -40: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=900.0 doc=1000.0x1000.0 vp=300.0x100.0]
//   N9d two-axis inner parked at bottom (900): phased 5x(0,-15): S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=900.0 doc=1000.0x1000.0 vp=300.0x100.0]
//   N9e two-axis inner parked 30 short of the bottom (870): phased 5x(0,-15): S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=900.0 doc=1000.0x1000.0 vp=300.0x100.0]
//   N9f two-axis inner parked at bottom (900): phaseless dy -40 repeated x3: S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=900.0 doc=1000.0x1000.0 vp=300.0x100.0]
//   N8h outer h, inner h (500 in 100) parked at the right edge (400): phaseless dx -40 at x=205: parked S0[x=0.0 y=0.0 doc=1500.0x300.0 vp=300.0x300.0] S1[x=400.0 y=0.0 doc=500.0x300.0 vp=100.0x300.0] | S0[x=40.0 y=0.0 doc=1500.0x300.0 vp=300.0x300.0] S1[x=400.0 y=0.0 doc=500.0x300.0 vp=100.0x300.0]
//   N8i outer v, inner v parked at bottom: x-dominant phased 5x(-15,-2) (the inner ignores x, outer v too): S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=400.0 doc=300.0x500.0 vp=300.0x100.0]
//   N10 N4 then momentum 3x(-1,-5): S0[x=0.0 y=75.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   === T: ScrollViewReader scrollTo
//   T1 .topLeading: before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(5,5, (0.0,0.0)) S0[x=500.0 y=500.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T2 .center: before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(5,5, (0.5,0.5)) S0[x=400.0 y=400.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T3 .top: before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(5,5, (0.5,0.0)) S0[x=400.0 y=500.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T3b .leading: before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(5,5, (0.0,0.5)) S0[x=500.0 y=400.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T3c .bottomTrailing: before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(5,5, (1.0,1.0)) S0[x=300.0 y=300.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T4 nil, target 9,9: before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(9,9, nil) S0[x=700.0 y=700.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T5 nil, target 5,1 (visible on x only: x 100..200): before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(5,1, nil) S0[x=0.0 y=300.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T5b nil, target 1,5 (visible on y only): before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(1,5, nil) S0[x=300.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T6 withAnimation .topLeading: before S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] | after scrollTo(5,5, (0.0,0.0)) S0[x=500.0 y=500.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   T7 target inside nested inner horizontal (outer v: inner at content y 500), scrollTo(i,9, anchor nil): before S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=0.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0] | after nil S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=700.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   T7b same with anchor .topLeading: after .topLeading S0[x=0.0 y=0.0 doc=300.0x1500.0 vp=300.0x300.0] S1[x=700.0 y=0.0 doc=1000.0x100.0 vp=300.0x100.0]
//   === S: defaultScrollAnchor in two-axis (300x300 over 1000x1000)
//   S1 .bottomTrailing: S0[x=700.0 y=700.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   S2 .bottom: S0[x=350.0 y=700.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   S3 .trailing: S0[x=700.0 y=350.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   S0 .topLeading: S0[x=0.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   S4 .bottomTrailing, grow 1000->1200 on both: initial S0[x=700.0 y=700.0 doc=1000.0x1000.0 vp=300.0x300.0] | grown both S0[x=900.0 y=900.0 doc=1200.0x1200.0 vp=300.0x300.0]
//   S5 .bottomTrailing, wheel away on x only (dx +40), then grow both: initial S0[x=700.0 y=700.0 doc=1000.0x1000.0 vp=300.0x300.0] | after x wheel S0[x=580.0 y=700.0 doc=1000.0x1000.0 vp=300.0x300.0] | grown both S0[x=580.0 y=900.0 doc=1200.0x1200.0 vp=300.0x300.0]
//   S5b .bottomTrailing, wheel away on y only (dy +40), then grow both: after y wheel S0[x=700.0 y=580.0 doc=1000.0x1000.0 vp=300.0x300.0] | grown both S0[x=900.0 y=580.0 doc=1200.0x1200.0 vp=300.0x300.0]
//   S5c .bottomTrailing, phaseless wheel away on x (dx +40), then grow both: after x wheel S0[x=660.0 y=700.0 doc=1000.0x1000.0 vp=300.0x300.0] | grown both S0[x=660.0 y=900.0 doc=1200.0x1200.0 vp=300.0x300.0]
//   === P: scrollPosition(id:) in two-axis (rows 100 tall, ids 0..9)
//   P1 binding after dy -250, dx -250, dy -250: rest pos=nil | dy: pos=Optional(2) S0[x=0.0 y=250.0 doc=1000.0x1000.0 vp=300.0x300.0] | dx only: pos=Optional(2) S0[x=0.0 y=250.0 doc=1000.0x1000.0 vp=300.0x300.0] | dy: pos=Optional(5) S0[x=0.0 y=500.0 doc=1000.0x1000.0 vp=300.0x300.0]
//   === R: right-to-left two-axis
//   R1 RTL two-axis 1000x1000: initial S0[x=700.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] cell0 frame x=200.0 w=100.0 | after dx -50: S0[x=700.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] cell0 frame x=200.0 w=100.0 | after dx +50: S0[x=650.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] cell0 frame x=250.0 w=100.0 | after dy -50: S0[x=650.0 y=0.0 doc=1000.0x1000.0 vp=300.0x300.0] cell0 frame x=250.0 w=100.0
//   DONE


import SwiftUI
import AppKit

func spin(_ s: TimeInterval) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }
func f(_ v: CGFloat) -> String { String(format: "%.1f", Double(v)) }

final class Box: ObservableObject {
    @Published var w: CGFloat = 1000
    @Published var h: CGFloat = 1000
    var appear = 0
    var proxy: ScrollViewProxy?
    var pos: Int?
    var frames: [String: CGRect] = [:]
}

extension View {
    func cap(_ box: Box, _ key: String) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("vp")) }) { box.frames[key] = $0 }
    }
}

@MainActor func scrollViews(in view: NSView) -> [NSScrollView] {
    var found: [NSScrollView] = []
    if let s = view as? NSScrollView { found.append(s) }
    for sub in view.subviews { found += scrollViews(in: sub) }
    return found
}

@MainActor func host<V: View>(_ v: V, size: CGSize) -> (NSWindow, NSHostingView<V>) {
    let h = NSHostingView(rootView: v)
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    win.contentView = h
    win.orderFrontRegardless()
    spin(0.5)
    return (win, h)
}

/// One line per scroller: content-view origin (the offset), document size, viewport size.
@MainActor func rd(_ h: NSView, detail: Bool = false) -> String {
    let all = scrollViews(in: h)
    if all.isEmpty { return "(no NSScrollView)" }
    return all.enumerated().map { i, s in
        let o = s.contentView.bounds.origin
        let d = s.documentView?.frame.size ?? .zero
        var t = "S\(i)[x=\(f(o.x)) y=\(f(o.y)) doc=\(f(d.width))x\(f(d.height)) vp=\(f(s.contentView.bounds.width))x\(f(s.contentView.bounds.height))"
        if detail {
            t += " docOrigin=(\(f(s.documentView?.frame.origin.x ?? 0)),\(f(s.documentView?.frame.origin.y ?? 0)))"
            t += " hS=\(s.hasHorizontalScroller) vS=\(s.hasVerticalScroller) pred=\(s.usesPredominantAxisScrolling) elastH=\(s.horizontalScrollElasticity.rawValue) elastV=\(s.verticalScrollElasticity.rawValue) frame=\(f(s.frame.width))x\(f(s.frame.height))"
        }
        return t + "]"
    }.joined(separator: " ")
}

@MainActor func park(_ h: NSView, scroller i: Int, x: CGFloat = 0, y: CGFloat = 0) {
    let all = scrollViews(in: h)
    guard i < all.count else { return }
    all[i].contentView.scroll(to: NSPoint(x: x, y: y))
    all[i].reflectScrolledClipView(all[i].contentView)
    spin(0.3)
}

@MainActor func thumbs(_ h: NSView) -> String {
    scrollViews(in: h).enumerated().map { i, s in
        let v = s.verticalScroller, hh = s.horizontalScroller
        return "S\(i)(style=\(s.scrollerStyle.rawValue) v:a=\(f(v?.alphaValue ?? -1)) hid=\(v?.isHidden ?? true) h:a=\(f(hh?.alphaValue ?? -1)) hid=\(hh?.isHidden ?? true))"
    }.joined(separator: " ")
}

enum Deliver { case window, direct }

/// View point (top-left origin inside the content view) -> CG global (top-left of the main display).
@MainActor func cgPoint(_ win: NSWindow, _ p: CGPoint) -> CGPoint {
    let ch = win.contentView!.bounds.height
    let scr = win.convertPoint(toScreen: NSPoint(x: p.x, y: ch - p.y))
    return CGPoint(x: scr.x, y: NSScreen.screens[0].frame.height - scr.y)
}

@MainActor func cgEvent(_ win: NSWindow, at p: CGPoint, dx: Int32, dy: Int32, phase: Int64, momentum: Int64, continuous: Bool) -> CGEvent? {
    guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return nil }
    cg.location = cgPoint(win, p)
    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
    return cg
}

/// `NSEvent(cgEvent:)` has `window == nil` and a SCREEN-based `locationInWindow` (the window server never saw the
/// event), so the borderless window sits at the screen origin (0,0): screen and window coordinates then coincide
/// and `NSWindow.sendEvent` hit-tests the right point (D0 checks that this is true, against `hitTest` delivery).
@MainActor func event(_ win: NSWindow, at p: CGPoint, dx: Int32, dy: Int32, phase: Int64, momentum: Int64, continuous: Bool) -> NSEvent? {
    guard let cg = cgEvent(win, at: p, dx: dx, dy: dy, phase: phase, momentum: momentum, continuous: continuous) else { return nil }
    return NSEvent(cgEvent: cg)
}

@MainActor func send(_ win: NSWindow, _ ev: NSEvent, at p: CGPoint, how: Deliver) {
    switch how {
    case .window: win.sendEvent(ev)
    case .direct:
        let ch = win.contentView!.bounds.height
        win.contentView!.hitTest(NSPoint(x: p.x, y: ch - p.y))?.scrollWheel(with: ev)
    }
}

/// Phaseless events: one per step, scrollPhase 0 / momentumPhase 0. Phased: began(1) with the first step,
/// changed(2), then ended(4) with zero delta; optional momentum (begin 1, continue 2, end 3 with zero).
/// Deltas are CG wheel values: NEGATIVE moves the offset up (content scrolls toward the end).
@MainActor func gesture(_ win: NSWindow, at p: CGPoint, steps: [(Int32, Int32)], phased: Bool, momentum: [(Int32, Int32)] = [],
                        continuous: Bool = true, how: Deliver = .window, tail: TimeInterval = 0.5) {
    if !phased {
        for s in steps { if let e = event(win, at: p, dx: s.0, dy: s.1, phase: 0, momentum: 0, continuous: continuous) { send(win, e, at: p, how: how) }; spin(0.03) }
    } else {
        for (i, s) in steps.enumerated() {
            if let e = event(win, at: p, dx: s.0, dy: s.1, phase: i == 0 ? 1 : 2, momentum: 0, continuous: true) { send(win, e, at: p, how: how) }
            spin(0.03)
        }
        if let e = event(win, at: p, dx: 0, dy: 0, phase: 4, momentum: 0, continuous: true) { send(win, e, at: p, how: how) }
        spin(0.03)
        for (i, s) in momentum.enumerated() {
            if let e = event(win, at: p, dx: s.0, dy: s.1, phase: 0, momentum: i == 0 ? 1 : 2, continuous: true) { send(win, e, at: p, how: how) }
            spin(0.03)
        }
        if !momentum.isEmpty, let e = event(win, at: p, dx: 0, dy: 0, phase: 0, momentum: 3, continuous: true) { send(win, e, at: p, how: how) }
    }
    spin(tail)
}

@MainActor func arm<V: View>(_ name: String, size: CGSize = CGSize(width: 300, height: 300), view: V, _ body: (NSWindow, NSView, inout [String]) -> Void) {
    let (w, h) = host(view, size: size)
    var parts: [String] = []
    body(w, h, &parts)
    print("\(name): " + parts.joined(separator: " | "))
    fflush(stdout)
    w.orderOut(nil); w.contentView = nil; spin(0.05)
}

let P = CGPoint(x: 150, y: 150)
let B: Axis.Set = [.horizontal, .vertical]

func twoAxis(_ box: Box? = nil, w: CGFloat = 1000, h: CGFloat = 1000) -> some View {
    ScrollView([.horizontal, .vertical]) { Color.blue.frame(width: w, height: h) }
}
func gridView() -> some View {
    VStack(spacing: 0) {
        ForEach(0..<10, id: \.self) { r in
            HStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { c in
                    Color(hue: Double(r * 10 + c) / 100, saturation: 0.5, brightness: 0.9).frame(width: 100, height: 100).id("\(r),\(c)")
                }
            }
        }
    }
}
/// Outer vertical, inner placed at content y 200..300 (point y=205 stays on it while the outer moves < 95).
func nestedV<I: View>(_ inner: I) -> some View {
    ScrollView(.vertical) {
        VStack(spacing: 0) {
            Color.gray.frame(height: 200)
            inner.frame(height: 100)
            Color.green.frame(height: 1200)
        }
    }
}
func nestedH<I: View>(_ inner: I) -> some View {
    ScrollView(.horizontal) {
        HStack(spacing: 0) {
            Color.gray.frame(width: 200)
            inner.frame(width: 100)
            Color.green.frame(width: 1200)
        }
    }
}
let innerH = ScrollView(.horizontal) { Color.blue.frame(width: 1000, height: 100) }
let PN = CGPoint(x: 150, y: 205)
let PN7 = CGPoint(x: 205, y: 150)

@MainActor func probes() {
    // ---------------- D0 method control
    print("=== D0: delivery control (one vertical 300x300 scroller over 1000, dy -100)")
    for cont in [false, true] {
        for how in [Deliver.window, .direct] {
            arm("D0 \(how) cont=\(cont)", view: ScrollView(.vertical) { Color.blue.frame(width: 300, height: 1000) }) { w, h, p in
                p.append("before \(rd(h, detail: true))")
                if let e = event(w, at: P, dx: 0, dy: -100, phase: 0, momentum: 0, continuous: cont) {
                    p.append("ev.window==win:\(e.window === w) evWN=\(e.windowNumber) winWN=\(w.windowNumber) loc=(\(f(e.locationInWindow.x)),\(f(e.locationInWindow.y)))")
                    send(w, e, at: P, how: how)
                }
                spin(0.5); p.append("after \(rd(h))")
            }
        }
    }
    arm("D0 phased window", view: ScrollView(.vertical) { Color.blue.frame(width: 300, height: 1000) }) { w, h, p in
        gesture(w, at: P, steps: [(0, -25), (0, -25), (0, -25), (0, -25)], phased: true)
        p.append("after phased 4x-25 \(rd(h))")
    }
    arm("D0 phased direct", view: ScrollView(.vertical) { Color.blue.frame(width: 300, height: 1000) }) { w, h, p in
        gesture(w, at: P, steps: [(0, -25), (0, -25), (0, -25), (0, -25)], phased: true, how: .direct)
        p.append("after phased 4x-25 \(rd(h))")
    }

    // ---------------- A: two-axis basics
    print("=== A: two-axis basics (300x300 over 1000x1000)")
    for cont in [false, true] {
        let c = "/c\(cont ? 1 : 0)"
        arm("A1 phaseless dx -50\(c)", view: twoAxis()) { w, h, p in gesture(w, at: P, steps: [(-50, 0)], phased: false, continuous: cont); p.append(rd(h, detail: true)) }
        arm("A2 phaseless dy -50\(c)", view: twoAxis()) { w, h, p in gesture(w, at: P, steps: [(0, -50)], phased: false, continuous: cont); p.append(rd(h)) }
        arm("A3 phaseless diagonal (-30,-40)\(c)", view: twoAxis()) { w, h, p in gesture(w, at: P, steps: [(-30, -40)], phased: false, continuous: cont); p.append(rd(h)) }
        arm("A3b phaseless x-dominant (-40,-30)\(c)", view: twoAxis()) { w, h, p in gesture(w, at: P, steps: [(-40, -30)], phased: false, continuous: cont); p.append(rd(h)) }
        arm("A3c phaseless x-dominant 3x(-40,-30) separate events\(c)", view: twoAxis()) { w, h, p in gesture(w, at: P, steps: [(-40, -30), (-40, -30), (-40, -30)], phased: false, continuous: cont); p.append(rd(h)) }
    }
    arm("A4 phased y-dominant 5x(-6,-8)", view: twoAxis()) { w, h, p in gesture(w, at: P, steps: Array(repeating: (-6, -8), count: 5), phased: true); p.append(rd(h)) }
    arm("A4b phased x-dominant 5x(-8,-6)", view: twoAxis()) { w, h, p in gesture(w, at: P, steps: Array(repeating: (-8, -6), count: 5), phased: true); p.append(rd(h)) }
    arm("A4c phased, first event y-dominant then x-dominant: (-1,-8) then 4x(-8,-1)", view: twoAxis()) { w, h, p in
        gesture(w, at: P, steps: [(-1, -8)] + Array(repeating: (-8, -1), count: 4), phased: true); p.append(rd(h)) }
    arm("A5 one gesture y-only 3x(0,-10) then x-only 3x(-10,0)", view: twoAxis()) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (0, -10), count: 3) + Array(repeating: (-10, 0), count: 3), phased: true); p.append(rd(h)) }
    arm("A5b one gesture x-only 3x(-10,0) then y-only 3x(0,-10)", view: twoAxis()) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (-10, 0), count: 3) + Array(repeating: (0, -10), count: 3), phased: true); p.append(rd(h)) }
    arm("A6 A4 then diagonal momentum 3x(-6,-8)", view: twoAxis()) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (-6, -8), count: 5), phased: true, momentum: Array(repeating: (-6, -8), count: 3)); p.append(rd(h)) }
    arm("A6b A4 then x-dominant momentum 3x(-8,-6)", view: twoAxis()) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (-6, -8), count: 5), phased: true, momentum: Array(repeating: (-8, -6), count: 3)); p.append(rd(h)) }
    arm("A7 overscroll 20x(-100,-100) phased, settled 1s", view: twoAxis()) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (-100, -100), count: 20), phased: true, tail: 1.2); p.append(rd(h)) }
    arm("A7b reverse overscroll 5x(100,100) from origin, settled", view: twoAxis()) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (100, 100), count: 5), phased: true, tail: 1.2); p.append(rd(h)) }
    arm("A3d phaseless tie (-30,-30)", view: twoAxis()) { w, h, p in gesture(w, at: P, steps: [(-30, -30)], phased: false); p.append(rd(h)) }
    arm("M0 momentum control: vertical-only, phased 4x(0,-10) then momentum 3x(0,-10)", view: ScrollView(.vertical) { Color.blue.frame(width: 300, height: 1000) }) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (0, -10), count: 4), phased: true); p.append("gesture only \(rd(h))")
        gesture(w, at: P, steps: Array(repeating: (0, -10), count: 4), phased: true, momentum: Array(repeating: (0, -10), count: 3)); p.append("second gesture with momentum \(rd(h))") }
    arm("A8 vertical-only scroller, x-dominant phased 5x(-8,-6)", view: ScrollView(.vertical) { Color.blue.frame(width: 300, height: 1000) }) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (-8, -6), count: 5), phased: true); p.append(rd(h)) }
    arm("A8b horizontal-only scroller, y-dominant phased 5x(-6,-8)", view: ScrollView(.horizontal) { Color.blue.frame(width: 1000, height: 300) }) { w, h, p in
        gesture(w, at: P, steps: Array(repeating: (-6, -8), count: 5), phased: true); p.append(rd(h)) }
    arm("A8c vertical-only scroller, phaseless (-40,-30)", view: ScrollView(.vertical) { Color.blue.frame(width: 300, height: 1000) }) { w, h, p in
        gesture(w, at: P, steps: [(-40, -30)], phased: false); p.append(rd(h)) }
    arm("A9 thumbs at ~0.1 s after a y-only phased gesture (two-axis)", view: twoAxis()) { w, h, p in
        p.append("rest \(thumbs(h))")
        gesture(w, at: P, steps: Array(repeating: (0, -10), count: 3), phased: true, tail: 0.1); p.append("0.1s \(thumbs(h))")
        spin(1.5); p.append("1.6s \(thumbs(h))")
    }
    arm("A9b thumbs at ~0.1 s after a y-only phased gesture (nested: outer v, inner h)", view: nestedV(innerH)) { w, h, p in
        gesture(w, at: PN, steps: Array(repeating: (0, -10), count: 3), phased: true, tail: 0.1); p.append("0.1s \(thumbs(h))") }

    // ---------------- L: layout and lazy
    print("=== L: layout and lazy")
    for (nm, size, cw, ch, axes) in [("L1a both 500x500 in 100x100", CGSize(width: 100, height: 100), CGFloat(500), CGFloat(500), B),
                                      ("L1b both 50x30 in 100x100", CGSize(width: 100, height: 100), 50, 30, B),
                                      ("L1c vertical 50x30 in 100x100", CGSize(width: 100, height: 100), 50, 30, [.vertical]),
                                      ("L1d horizontal 50x30 in 100x100", CGSize(width: 100, height: 100), 50, 30, [.horizontal]),
                                      ("L2a both 50x500 in 300x300", CGSize(width: 300, height: 300), 50, 500, B),
                                      ("L2b both 500x50 in 300x300", CGSize(width: 300, height: 300), 500, 50, B),
                                      ("L2c vertical 50x500 in 300x300", CGSize(width: 300, height: 300), 50, 500, [.vertical]),
                                      ("L2d horizontal 500x50 in 300x300", CGSize(width: 300, height: 300), 500, 50, [.horizontal])] {
        let box = Box()
        arm(nm, size: size, view: ScrollView(axes) { Color.blue.frame(width: cw, height: ch).cap(box, "c") }.coordinateSpace(.named("vp"))) { w, h, p in
            let r = box.frames["c"] ?? .zero
            p.append("content frame in viewport (\(f(r.minX)),\(f(r.minY))) \(f(r.width))x\(f(r.height))")
            p.append(rd(h, detail: true))
        }
    }
    do {
        let box = Box()
        arm("L3 ScrollView([]) 500x500 in 300x300", view: ScrollView([]) { Color.blue.frame(width: 500, height: 500).cap(box, "c") }.coordinateSpace(.named("vp"))) { w, h, p in
            func fr() -> String { let r = box.frames["c"] ?? .zero; return "content (\(f(r.minX)),\(f(r.minY))) \(f(r.width))x\(f(r.height))" }
            p.append("scrollers=\(scrollViews(in: h).count) \(fr()) \(rd(h, detail: true))")
            gesture(w, at: P, steps: [(-50, -50)], phased: false); p.append("after phaseless (-50,-50): \(fr()) \(rd(h))")
            gesture(w, at: P, steps: Array(repeating: (-10, -10), count: 3), phased: true); p.append("after phased: \(fr()) \(rd(h))")
        }
    }
    do {
        let box = Box()
        func lazyV() -> some View {
            ScrollView(B) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<1000, id: \.self) { i in Color.blue.frame(width: 800, height: 20).onAppear { box.appear += 1 }.cap(box, i == 0 ? "r0" : "x") }
                }.cap(box, "stack")
            }.coordinateSpace(.named("vp"))
        }
        arm("L4 LazyVStack 1000 rows 20x800 in two-axis", view: lazyV()) { w, h, p in
            func st() -> String { let s = box.frames["stack"] ?? .zero, r = box.frames["r0"] ?? .zero; return "appear=\(box.appear) stack \(f(s.width))x\(f(s.height)) row0 w=\(f(r.width))" }
            p.append("rest \(st())")
            gesture(w, at: P, steps: [(-200, 0)], phased: false); p.append("after dx -200: \(st()) \(rd(h))")
            gesture(w, at: P, steps: [(0, -400)], phased: false); p.append("after dy -400: \(st()) \(rd(h))")
        }
    }
    do {
        let box = Box()
        func lazyH() -> some View {
            ScrollView(B) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<1000, id: \.self) { i in Color.blue.frame(width: 20, height: 800).onAppear { box.appear += 1 } }
                }.cap(box, "stack")
            }.coordinateSpace(.named("vp"))
        }
        arm("L5 LazyHStack 1000 cols 20x800 in two-axis", view: lazyH()) { w, h, p in
            func st() -> String { let s = box.frames["stack"] ?? .zero; return "appear=\(box.appear) stack \(f(s.width))x\(f(s.height))" }
            p.append("rest \(st())")
            gesture(w, at: P, steps: [(0, -200)], phased: false); p.append("after dy -200: \(st()) \(rd(h))")
            gesture(w, at: P, steps: [(-400, 0)], phased: false); p.append("after dx -400: \(st()) \(rd(h))")
        }
    }

    // ---------------- N: nesting
    print("=== N: nesting (outer 300x300 over 1500; inner 300x100 at content y 200..300; events at y=205)")
    for cont in [false, true] {
        let c = "/c\(cont ? 1 : 0)"
        arm("N1 outer v, inner h: phaseless dy -40\(c)", view: nestedV(innerH)) { w, h, p in gesture(w, at: PN, steps: [(0, -40)], phased: false, continuous: cont); p.append(rd(h)) }
        arm("N2 phaseless dx -40\(c)", view: nestedV(innerH)) { w, h, p in gesture(w, at: PN, steps: [(-40, 0)], phased: false, continuous: cont); p.append(rd(h)) }
        arm("N3 phaseless diagonal (-30,-40)\(c)", view: nestedV(innerH)) { w, h, p in gesture(w, at: PN, steps: [(-30, -40)], phased: false, continuous: cont); p.append(rd(h)) }
        arm("N3b phaseless x-dominant (-40,-30)\(c)", view: nestedV(innerH)) { w, h, p in gesture(w, at: PN, steps: [(-40, -30)], phased: false, continuous: cont); p.append(rd(h)) }
        arm("N3c phaseless (-30,-40) x2 separate events\(c)", view: nestedV(innerH)) { w, h, p in gesture(w, at: PN, steps: [(-30, -40), (-30, -40)], phased: false, continuous: cont); p.append(rd(h)) }
    }
    arm("N4 phased y-dominant with x jitter 5x(-2,-15)", view: nestedV(innerH)) { w, h, p in gesture(w, at: PN, steps: Array(repeating: (-2, -15), count: 5), phased: true); p.append(rd(h)) }
    arm("N5 phased x-dominant with y jitter 5x(-16,-2)", view: nestedV(innerH)) { w, h, p in gesture(w, at: PN, steps: Array(repeating: (-16, -2), count: 5), phased: true); p.append(rd(h)) }
    arm("N5b phased x-only 5x(-16,0)", view: nestedV(innerH)) { w, h, p in gesture(w, at: PN, steps: Array(repeating: (-16, 0), count: 5), phased: true); p.append(rd(h)) }
    let innerFit = ScrollView(.horizontal) { Color.blue.frame(width: 200, height: 100) }
    arm("N6 inner h content fits (200 wide): phaseless dy -40", view: nestedV(innerFit)) { w, h, p in gesture(w, at: PN, steps: [(0, -40)], phased: false); p.append(rd(h)) }
    arm("N6a same, phaseless dx -40", view: nestedV(innerFit)) { w, h, p in gesture(w, at: PN, steps: [(-40, 0)], phased: false); p.append(rd(h)) }
    arm("N6a2 same, phaseless diagonal (-30,-40)", view: nestedV(innerFit)) { w, h, p in gesture(w, at: PN, steps: [(-30, -40)], phased: false); p.append(rd(h)) }
    arm("N6a3 same, phased dx-dominant 5x(-16,-2)", view: nestedV(innerFit)) { w, h, p in gesture(w, at: PN, steps: Array(repeating: (-16, -2), count: 5), phased: true); p.append(rd(h)) }
    let innerVfit = ScrollView(.vertical) { Color.blue.frame(width: 300, height: 50) }
    arm("N6b outer v, inner v whose content fits (50 in 100): phaseless dy -40", view: nestedV(innerVfit)) { w, h, p in gesture(w, at: PN, steps: [(0, -40)], phased: false); p.append(rd(h)) }
    arm("N6b2 same, phased 5x(0,-8)", view: nestedV(innerVfit)) { w, h, p in gesture(w, at: PN, steps: Array(repeating: (0, -8), count: 5), phased: true); p.append(rd(h)) }
    let innerVfull = ScrollView(.vertical) { Color.blue.frame(width: 300, height: 500) }
    arm("N6c control outer v, inner v overflowing (500 in 100): phaseless dy -40", view: nestedV(innerVfull)) { w, h, p in gesture(w, at: PN, steps: [(0, -40)], phased: false); p.append(rd(h)) }
    arm("N7 outer h, inner v (dx -40 at x=205)", view: nestedH(ScrollView(.vertical) { Color.blue.frame(width: 100, height: 1000) })) { w, h, p in
        gesture(w, at: PN7, steps: [(-40, 0)], phased: false); p.append("dx: \(rd(h))") }
    arm("N7b outer h, inner v (dy -40 at x=205)", view: nestedH(ScrollView(.vertical) { Color.blue.frame(width: 100, height: 1000) })) { w, h, p in
        gesture(w, at: PN7, steps: [(0, -40)], phased: false); p.append("dy: \(rd(h))") }
    arm("N7c outer h, inner v, phased x-dominant 5x(-16,-2)", view: nestedH(ScrollView(.vertical) { Color.blue.frame(width: 100, height: 1000) })) { w, h, p in
        gesture(w, at: PN7, steps: Array(repeating: (-16, -2), count: 5), phased: true); p.append(rd(h)) }
    // N8: same-axis edge chaining. inner vertical 100 over 500 parked at the bottom (400) / 30 short of it (370).
    arm("N8a inner parked at bottom; phased gesture starts there 5x(0,-15)", view: nestedV(innerVfull)) { w, h, p in
        park(h, scroller: 1, y: 400); p.append("parked \(rd(h))")
        gesture(w, at: PN, steps: Array(repeating: (0, -15), count: 5), phased: true); p.append(rd(h)) }
    arm("N8b inner parked 30 short; phased gesture reaches the edge mid-gesture 5x(0,-15)", view: nestedV(innerVfull)) { w, h, p in
        park(h, scroller: 1, y: 370); p.append("parked \(rd(h))")
        gesture(w, at: PN, steps: Array(repeating: (0, -15), count: 5), phased: true); p.append(rd(h)) }
    for cont in [false, true] {
        arm("N8c inner parked at bottom; phaseless dy -40/c\(cont ? 1 : 0)", view: nestedV(innerVfull)) { w, h, p in
            park(h, scroller: 1, y: 400); p.append("parked \(rd(h))")
            gesture(w, at: PN, steps: [(0, -40)], phased: false, continuous: cont); p.append(rd(h)) }
    }
    arm("N8d inner at bottom; gesture ends, then a SECOND phased gesture starts there 3x(0,-15)", view: nestedV(innerVfull)) { w, h, p in
        park(h, scroller: 1, y: 400)
        gesture(w, at: PN, steps: Array(repeating: (0, -15), count: 3), phased: true); p.append("first \(rd(h))")
        gesture(w, at: PN, steps: Array(repeating: (0, -15), count: 3), phased: true); p.append("second \(rd(h))") }
    arm("N8e inner parked at TOP (0), gesture upward (dy +) 5x(0,15) with the outer at 0", view: nestedV(innerVfull)) { w, h, p in
        gesture(w, at: PN, steps: Array(repeating: (0, 15), count: 5), phased: true); p.append(rd(h)) }
    let inner2 = ScrollView([.horizontal, .vertical]) { Color.blue.frame(width: 1000, height: 1000) }
    arm("N9 two-axis inner in vertical outer: phaseless dy -40", view: nestedV(inner2)) { w, h, p in gesture(w, at: PN, steps: [(0, -40)], phased: false); p.append(rd(h)) }
    arm("N9b same, phaseless diagonal (-30,-40)", view: nestedV(inner2)) { w, h, p in gesture(w, at: PN, steps: [(-30, -40)], phased: false); p.append(rd(h)) }
    arm("N9c same, inner parked at bottom (900), phaseless dy -40", view: nestedV(inner2)) { w, h, p in
        park(h, scroller: 1, y: 900); gesture(w, at: PN, steps: [(0, -40)], phased: false); p.append(rd(h)) }
    arm("N9d two-axis inner parked at bottom (900): phased 5x(0,-15)", view: nestedV(inner2)) { w, h, p in
        park(h, scroller: 1, y: 900); gesture(w, at: PN, steps: Array(repeating: (0, -15), count: 5), phased: true); p.append(rd(h)) }
    arm("N9e two-axis inner parked 30 short of the bottom (870): phased 5x(0,-15)", view: nestedV(inner2)) { w, h, p in
        park(h, scroller: 1, y: 870); gesture(w, at: PN, steps: Array(repeating: (0, -15), count: 5), phased: true); p.append(rd(h)) }
    arm("N9f two-axis inner parked at bottom (900): phaseless dy -40 repeated x3", view: nestedV(inner2)) { w, h, p in
        park(h, scroller: 1, y: 900); gesture(w, at: PN, steps: [(0, -40), (0, -40)], phased: false); p.append(rd(h)) }
    let innerHfull = ScrollView(.horizontal) { Color.blue.frame(width: 500, height: 300) }
    arm("N8h outer h, inner h (500 in 100) parked at the right edge (400): phaseless dx -40 at x=205", view: nestedH(innerHfull)) { w, h, p in
        park(h, scroller: 1, x: 400); p.append("parked \(rd(h))")
        gesture(w, at: PN7, steps: [(-40, 0)], phased: false); p.append(rd(h)) }
    arm("N8i outer v, inner v parked at bottom: x-dominant phased 5x(-15,-2) (the inner ignores x, outer v too)", view: nestedV(innerVfull)) { w, h, p in
        park(h, scroller: 1, y: 400); gesture(w, at: PN, steps: Array(repeating: (-15, -2), count: 5), phased: true); p.append(rd(h)) }
    arm("N10 N4 then momentum 3x(-1,-5)", view: nestedV(innerH)) { w, h, p in
        gesture(w, at: PN, steps: Array(repeating: (-2, -15), count: 5), phased: true, momentum: Array(repeating: (-1, -5), count: 3)); p.append(rd(h)) }

    // ---------------- T: ScrollViewReader
    print("=== T: ScrollViewReader scrollTo")
    func tArm(_ name: String, anchor: UnitPoint?, target: String = "5,5", animated: Bool = false) {
        let box = Box()
        arm(name, view: ScrollViewReader { proxy in
            ScrollView(B) { gridView() }.onAppear { box.proxy = proxy }
        }) { w, h, p in
            p.append("before \(rd(h))")
            if animated { withAnimation(.linear(duration: 0.2)) { box.proxy?.scrollTo(target, anchor: anchor) } } else { box.proxy?.scrollTo(target, anchor: anchor) }
            spin(0.8); p.append("after scrollTo(\(target), \(anchor.map { "(\($0.x),\($0.y))" } ?? "nil")) \(rd(h))")
        }
    }
    tArm("T1 .topLeading", anchor: .topLeading)
    tArm("T2 .center", anchor: .center)
    tArm("T3 .top", anchor: .top)
    tArm("T3b .leading", anchor: .leading)
    tArm("T3c .bottomTrailing", anchor: .bottomTrailing)
    tArm("T4 nil, target 9,9", anchor: nil, target: "9,9")
    tArm("T5 nil, target 5,1 (visible on x only: x 100..200)", anchor: nil, target: "5,1")
    tArm("T5b nil, target 1,5 (visible on y only)", anchor: nil, target: "1,5")
    tArm("T6 withAnimation .topLeading", anchor: .topLeading, animated: true)
    do {
        let box = Box()
        let inner = ScrollView(.horizontal) { HStack(spacing: 0) { ForEach(0..<10, id: \.self) { c in Color.red.opacity(0.3 + Double(c) / 20).frame(width: 100, height: 100).id("i,\(c)") } } }
        arm("T7 target inside nested inner horizontal (outer v: inner at content y 500), scrollTo(i,9, anchor nil)", view: ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) { Color.gray.frame(height: 500); inner.frame(height: 100); Color.green.frame(height: 900) }
            }.onAppear { box.proxy = proxy }
        }) { w, h, p in
            p.append("before \(rd(h))")
            box.proxy?.scrollTo("i,9", anchor: nil); spin(0.8); p.append("after nil \(rd(h))")
        }
        arm("T7b same with anchor .topLeading", view: ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) { Color.gray.frame(height: 500); inner.frame(height: 100); Color.green.frame(height: 900) }
            }.onAppear { box.proxy = proxy }
        }) { w, h, p in
            box.proxy?.scrollTo("i,9", anchor: .topLeading); spin(0.8); p.append("after .topLeading \(rd(h))")
        }
    }

    // ---------------- S: defaultScrollAnchor
    print("=== S: defaultScrollAnchor in two-axis (300x300 over 1000x1000)")
    for (nm, a) in [("S1 .bottomTrailing", UnitPoint.bottomTrailing), ("S2 .bottom", .bottom), ("S3 .trailing", .trailing), ("S0 .topLeading", .topLeading)] {
        arm(nm, view: twoAxis().defaultScrollAnchor(a)) { w, h, p in p.append(rd(h)) }
    }
    struct Grow: View {
        @ObservedObject var m: Box
        var body: some View { ScrollView([.horizontal, .vertical]) { Color.blue.frame(width: m.w, height: m.h) }.defaultScrollAnchor(.bottomTrailing) }
    }
    do {
        let m = Box()
        arm("S4 .bottomTrailing, grow 1000->1200 on both", view: Grow(m: m)) { w, h, p in
            p.append("initial \(rd(h))"); m.w = 1200; m.h = 1200; spin(0.5); p.append("grown both \(rd(h))") }
        let m2 = Box()
        arm("S5 .bottomTrailing, wheel away on x only (dx +40), then grow both", view: Grow(m: m2)) { w, h, p in
            p.append("initial \(rd(h))")
            gesture(w, at: P, steps: [(40, 0), (40, 0), (40, 0)], phased: true); p.append("after x wheel \(rd(h))")
            m2.w = 1200; m2.h = 1200; spin(0.5); p.append("grown both \(rd(h))") }
        let m3 = Box()
        arm("S5b .bottomTrailing, wheel away on y only (dy +40), then grow both", view: Grow(m: m3)) { w, h, p in
            gesture(w, at: P, steps: [(0, 40), (0, 40), (0, 40)], phased: true); p.append("after y wheel \(rd(h))")
            m3.w = 1200; m3.h = 1200; spin(0.5); p.append("grown both \(rd(h))") }
        let m4 = Box()
        arm("S5c .bottomTrailing, phaseless wheel away on x (dx +40), then grow both", view: Grow(m: m4)) { w, h, p in
            gesture(w, at: P, steps: [(40, 0)], phased: false); p.append("after x wheel \(rd(h))")
            m4.w = 1200; m4.h = 1200; spin(0.5); p.append("grown both \(rd(h))") }
    }

    // ---------------- P: scrollPosition(id:)
    print("=== P: scrollPosition(id:) in two-axis (rows 100 tall, ids 0..9)")
    do {
        let box = Box()
        let b = Binding<Int?>(get: { box.pos }, set: { box.pos = $0 })
        let v = ScrollView(B) {
            VStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { r in HStack(spacing: 0) { ForEach(0..<10, id: \.self) { c in Color(hue: Double(c) / 10, saturation: 0.5, brightness: 0.9).frame(width: 100, height: 100) } }.id(r) }
            }.scrollTargetLayout()
        }.scrollPosition(id: b)
        arm("P1 binding after dy -250, dx -250, dy -250", view: v) { w, h, p in
            p.append("rest pos=\(String(describing: box.pos))")
            gesture(w, at: P, steps: [(0, -250)], phased: false); p.append("dy: pos=\(String(describing: box.pos)) \(rd(h))")
            gesture(w, at: P, steps: [(-250, 0)], phased: false); p.append("dx only: pos=\(String(describing: box.pos)) \(rd(h))")
            gesture(w, at: P, steps: [(0, -250)], phased: false); p.append("dy: pos=\(String(describing: box.pos)) \(rd(h))")
        }
    }

    // ---------------- R: right-to-left
    print("=== R: right-to-left two-axis")
    do {
        let box = Box()
        let v = ScrollView(B) {
            HStack(spacing: 0) { ForEach(0..<10, id: \.self) { c in (c == 0 ? Color.red : Color.blue).frame(width: 100, height: 1000).cap(box, c == 0 ? "c0" : "cx") } }
        }.coordinateSpace(.named("vp")).environment(\.layoutDirection, .rightToLeft)
        arm("R1 RTL two-axis 1000x1000", view: v) { w, h, p in
            func st() -> String { let r = box.frames["c0"] ?? .zero; return "cell0 frame x=\(f(r.minX)) w=\(f(r.width))" }
            p.append("initial \(rd(h)) \(st())")
            gesture(w, at: P, steps: [(-50, 0)], phased: false); p.append("after dx -50: \(rd(h)) \(st())")
            gesture(w, at: P, steps: [(50, 0)], phased: false); p.append("after dx +50: \(rd(h)) \(st())")
            gesture(w, at: P, steps: [(0, -50)], phased: false); p.append("after dy -50: \(rd(h)) \(st())")
        }
    }
    print("DONE")
    fflush(stdout)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }

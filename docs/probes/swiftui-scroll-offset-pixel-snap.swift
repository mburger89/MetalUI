// SwiftUI probe (SA-O), record 425, plan `docs/superpowers/plans/2026-11-25-exact-redo-and-movable-records.md` Piece 3(b): does SwiftUI snap
// the **drawn** scroll position to device pixels, and does it snap the **reported** `contentOffset`? MetalUI's scroller paints at a fractional
// device-pixel offset, every paint record under it is then refused (`fractionalTranslation`, `inexactTranslation`), and the retained path pays a
// redo. Cure (1), snap like SwiftUI, is a fidelity fix; cure (2), recompute the moved leaves (`FS-W`), is a cost fix. This probe is the evidence
// for choosing.
//
// HOW TO RUN (macOS, the machine's own display; it opens eighteen borderless 300 x 300 windows one after the other, each for under a second,
// closes each, and exits by itself; it posts no events and takes no focus for long; it needs no permission):
//
//   /usr/bin/swift docs/probes/swiftui-scroll-offset-pixel-snap.swift 2>&1 \
//     | grep -v 'warning:\|^ *[0-9]* |\|^ *|\|note:\|WARNING: Application performed a reentrant\|Connection\]'
//
//   xcrun swiftc -O docs/probes/swiftui-scroll-offset-pixel-snap.swift -o /tmp/pixelsnap && /tmp/pixelsnap 2>&1 | grep -v '...same filter...'
//
// Both ways were run twice on 2026-11-26 (macOS 27.x, Apple's toolchain); the four outputs are line-for-line identical, and the recording below is
// the interpreter's.
//
// THE 2x METHOD (the author's only display is a 1x 1920 x 1080 monitor, and its settings must not change). The window is real and 1x
// (`backingScaleFactor=1.0`). A "2x" pass makes two changes: the root view gets `.environment(\.displayScale, 2)`, and the view is drawn into an
// `NSBitmapImageRep` of twice its point size in pixels (`rep.size` stays in points) with `cacheDisplay(in:to:)`; the hairline's ink is read back at
// pixel resolution. Positive controls, both passes (arm C0, four 1 pt black hairlines at y = 10, 30.25, 50.5, 70.3, 90.75 with `.offset`): the
// readback sees 2 pixel rows per hairline at 2x and 1 at 1x, whole rows (crisp) every time, so SwiftUI **does** snap a drawn leaf's origin
// to the pixel grid of the injected scale (30.25 draws at 30.0 at 1x and at 30.5 at 2x: nearest pixel, ties up), and the injection does reach layout
// (F1: `contentSize` 399.5 at 2x, 400 at 1x, 12 rows of 33.3 pt). The negative control is F4b/F5: a clip origin AppKit was given at a fraction
// (`clip.scroll(to: 0.15)`, bypassing SwiftUI) draws **blended** (0.85/0.15 at 1x, 0.70/0.30 at 2x), so the readback can see an unsnapped edge.
//
// WHAT IT CANNOT SHOW. The window's backing scale stays 1. AppKit's own pixel alignment of the clip view (`NSClipView`, the wheel's accumulation) uses the
// window's backing, not SwiftUI's environment, so everything below that is AppKit's at 2x is unmeasured: a real Retina wheel scroll, and
// `scrollPosition(y:)`'s grid at 2x (F4a: 100.3 -> 100.0 and 100.7 -> 101.0 at **both** passes, so the grid it snaps to follows the real backing
// scale or is whole points; a device-pixel grid at 2x would give 100.5). A wheel event with a fractional delta cannot be built offscreen:
// `NSEvent(cgEvent:)` truncates 0.3 and 0.7 to `scrollingDeltaY = 0` and scales whole values by 8 (F4c). `cacheDisplay` renders the layer tree
// through Core Animation's software path, not the display's Metal compositor.
//
// ARMS (F0-F6 are the plan's; C0 and F4c were added):
//   C0  control, above.        F0  40 pt rows, scrolled by 100 (AppKit `scroll(to:)`).
//   F1  33.3 pt rows, `.defaultScrollAnchor(.bottom)`, append a row twice.
//   F2  a wrapping text row growing word by word under the bottom anchor.
//   F3  `ScrollViewReader.scrollTo(last, anchor: .bottom)`, then an append without scrolling, then scrollTo again.
//   F4a `scrollPosition(y:)` set to 0.3, 100.3, 100.7, 100.8.   F4b `NSClipView.scroll(to:)` 0.15, 0.3, 0.45, 100.15.
//   F4c a pixel-unit wheel event sent to the scroll view (not posted).   F5 `contentMargins(12.25)`, then clip.scroll(+100) onto 87.75.
//   F6 `.padding(0.3)` around the stack.
// Each line: pass, arm, step, the NSScrollView clip `bounds.origin.y` (`clip`), `onScrollGeometryChange` `contentOffset.y` (`offset`) and
// `contentSize.height` (`size`), then per row `sv` = `frame(in: .scrollView).minY`, `gl` = `frame(in: .global).minY` and the readback
// `px<first row>..=<ink of each pixel row, from one above the row the hairline top falls in>` and crisp (every value 0 or 1), blend, blank or
// off (above the window).
//
// RECORDED (macOS 27, 1x display, `/usr/bin/swift`; lines cut at 240 characters):
//
//   backingScaleFactor=1.0 injected displayScale=1 screen=
//   1x C0 control y=10.0 hair px9..=0.00,1.00,0.00 crisp
//   1x C0 control y=30.25 hair px29..=0.00,1.00,0.00 crisp
//   1x C0 control y=50.5 hair px49..=0.00,0.00,1.00 crisp
//   1x C0 control y=70.3 hair px69..=0.00,1.00,0.00 crisp
//   1x C0 control y=90.75 hair px89..=0.00,0.00,1.00 crisp
//   1x F0 initial clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px39..=0.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px79..=0.00,1.00,0.00 crisp
//   1x F0 clip.scroll(+100) clip=100.000 offset=100.000 size=480.000 | r2 sv=-20.000 gl=-20.000 off | r3 sv=20.000 gl=20.000 px19..=0.00,1.00,0.00 crisp | r4 sv=60.000 gl=60.000 px59..=0.00,1.00,0.00 crisp
//   1x F1 initial clip=100.000 offset=100.000 size=400.000 | r10 sv=233.000 gl=233.000 px232..=0.00,1.00,0.00 crisp | r11 sv=266.300 gl=266.300 px265..=0.00,1.00,0.00 crisp
//   1x F1 append1 clip=133.000 offset=133.000 size=433.000 | r11 sv=233.300 gl=233.300 px232..=0.00,1.00,0.00 crisp | r12 sv=266.600 gl=266.600 px265..=0.00,0.00,1.00 crisp
//   1x F1 append2 clip=166.000 offset=166.000 size=466.000 | r12 sv=233.600 gl=233.600 px232..=0.00,0.00,1.00 crisp | r13 sv=266.900 gl=266.900 px265..=0.00,0.00,1.00 crisp
//   1x F2 words3 clip=53.000 offset=53.000 size=353.000 | r9 sv=246.700 gl=246.700 px245..=0.00,0.00,1.00 crisp | r10 sv=280.000 gl=280.000 px279..=0.00,1.00,0.00 crisp
//   1x F2 words4 clip=53.000 offset=53.000 size=353.000 | r9 sv=246.700 gl=246.700 px245..=0.00,0.00,1.00 crisp | r10 sv=280.000 gl=280.000 px279..=0.00,1.00,0.00 crisp
//   1x F2 words6 clip=53.000 offset=53.000 size=353.000 | r9 sv=246.700 gl=246.700 px245..=0.00,0.00,1.00 crisp | r10 sv=280.000 gl=280.000 px279..=0.00,1.00,0.00 crisp
//   1x F2 words8 clip=53.000 offset=53.000 size=353.000 | r9 sv=246.700 gl=246.700 px245..=0.00,0.00,1.00 crisp | r10 sv=280.000 gl=280.000 px279..=0.00,1.00,0.00 crisp
//   1x F2 words10 clip=69.000 offset=69.000 size=369.000 | r9 sv=230.700 gl=230.700 px229..=0.00,0.00,1.00 crisp | r10 sv=264.000 gl=264.000 px263..=0.00,1.00,0.00 crisp
//   1x F2 words12 clip=69.000 offset=69.000 size=369.000 | r9 sv=230.700 gl=230.700 px229..=0.00,0.00,1.00 crisp | r10 sv=264.000 gl=264.000 px263..=0.00,1.00,0.00 crisp
//   1x F2 words14 clip=69.000 offset=69.000 size=369.000 | r9 sv=230.700 gl=230.700 px229..=0.00,0.00,1.00 crisp | r10 sv=264.000 gl=264.000 px263..=0.00,1.00,0.00 crisp
//   1x F3 scrollTo.bottom clip=100.000 offset=100.000 size=400.000 | r10 sv=233.000 gl=233.000 px232..=0.00,1.00,0.00 crisp | r11 sv=266.300 gl=266.300 px265..=0.00,1.00,0.00 crisp
//   1x F3 append,stay clip=100.000 offset=100.000 size=433.000 | r11 sv=266.300 gl=266.300 px265..=0.00,1.00,0.00 crisp | r12 sv=299.600 gl=299.600 px298..=0.00,0.00 blank
//   1x F3 scrollTo.bottom2 clip=133.000 offset=133.000 size=433.000 | r11 sv=233.300 gl=233.300 px232..=0.00,1.00,0.00 crisp | r12 sv=266.600 gl=266.600 px265..=0.00,0.00,1.00 crisp
//   1x F4a initial clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px39..=0.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px79..=0.00,1.00,0.00 crisp
//   1x F4a scrollPosition.y=0.3 clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px39..=0.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px79..=0.00,1.00,0.00 crisp
//   1x F4a scrollPosition.y=100.3 clip=100.000 offset=100.000 size=480.000 | r2 sv=-20.000 gl=-20.000 off | r3 sv=20.000 gl=20.000 px19..=0.00,1.00,0.00 crisp | r4 sv=60.000 gl=60.000 px59..=0.00,1.00,0.00 crisp
//   1x F4a scrollPosition.y=100.7 clip=101.000 offset=101.000 size=480.000 | r2 sv=-21.000 gl=-21.000 off | r3 sv=19.000 gl=19.000 px18..=0.00,1.00,0.00 crisp | r4 sv=59.000 gl=59.000 px58..=0.00,1.00,0.00 crisp
//   1x F4a scrollPosition.y=100.8 clip=101.000 offset=101.000 size=480.000 | r2 sv=-21.000 gl=-21.000 off | r3 sv=19.000 gl=19.000 px18..=0.00,1.00,0.00 crisp | r4 sv=59.000 gl=59.000 px58..=0.00,1.00,0.00 crisp
//   1x F4b initial clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px39..=0.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px79..=0.00,1.00,0.00 crisp
//   1x F4b clip.scroll(0.15) clip=0.150 offset=0.150 size=480.000 | r0 sv=-0.150 gl=-0.150 px-2..=0.85 blend | r1 sv=39.850 gl=39.850 px38..=0.00,0.15,0.85 blend | r2 sv=79.850 gl=79.850 px78..=0.00,0.15,0.85 blend
//   1x F4b clip.scroll(0.3) clip=0.300 offset=0.300 size=480.000 | r0 sv=-0.300 gl=-0.300 px-2..=0.70 blend | r1 sv=39.700 gl=39.700 px38..=0.00,0.30,0.70 blend | r2 sv=79.700 gl=79.700 px78..=0.00,0.30,0.70 blend
//   1x F4b clip.scroll(0.45) clip=0.450 offset=0.450 size=480.000 | r0 sv=-0.450 gl=-0.450 px-2..=0.55 blend | r1 sv=39.550 gl=39.550 px38..=0.00,0.45,0.55 blend | r2 sv=79.550 gl=79.550 px78..=0.00,0.45,0.55 blend
//   1x F4b clip.scroll(100.15) clip=100.150 offset=100.150 size=480.000 | r2 sv=-20.150 gl=-20.150 off | r3 sv=19.850 gl=19.850 px18..=0.00,0.15,0.85 blend | r4 sv=59.850 gl=59.850 px58..=0.00,0.15,0.85 blend
//   1x F4c initial clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px39..=0.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px79..=0.00,1.00,0.00 crisp
//      event scrollingDeltaY=0.0 precise=true
//   1x F4c wheel(-0.3) clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px39..=0.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px79..=0.00,1.00,0.00 crisp | r3 sv=120.000 gl=120.000 px119
//      event scrollingDeltaY=0.0 precise=true
//   1x F4c wheel(-0.7) clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px39..=0.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px79..=0.00,1.00,0.00 crisp | r3 sv=120.000 gl=120.000 px119
//      event scrollingDeltaY=-8.0 precise=true
//   1x F4c wheel(-1.0) clip=8.000 offset=8.000 size=480.000 | r0 sv=-8.000 gl=-8.000 off | r1 sv=32.000 gl=32.000 px31..=0.00,1.00,0.00 crisp | r2 sv=72.000 gl=72.000 px71..=0.00,1.00,0.00 crisp | r3 sv=112.000 gl=112.000 px111..=0.00,1.00,0.00
//      event scrollingDeltaY=-80.0 precise=true
//   1x F4c wheel(-10.0) clip=88.000 offset=88.000 size=480.000 | r0 sv=-88.000 gl=-88.000 off | r1 sv=-48.000 gl=-48.000 off | r2 sv=-8.000 gl=-8.000 off | r3 sv=32.000 gl=32.000 px31..=0.00,1.00,0.00 crisp | r4 sv=72.000 gl=72.000 px71..=0.00,
//      event scrollingDeltaY=-80.0 precise=true
//   1x F4c wheel(-10.6) clip=168.000 offset=168.000 size=480.000 | r0 sv=-168.000 gl=-168.000 off | r1 sv=-128.000 gl=-128.000 off | r2 sv=-88.000 gl=-88.000 off | r3 sv=-48.000 gl=-48.000 off | r4 sv=-8.000 gl=-8.000 off
//   1x F5 initial clip=-12.000 offset=-12.000 size=480.000 | r0 sv=0.000 gl=12.250 px11..=0.00,1.00,0.00 crisp | r1 sv=40.000 gl=52.250 px51..=0.00,1.00,0.00 crisp | r2 sv=80.000 gl=92.250 px91..=0.00,1.00,0.00 crisp
//   1x F5 clip.scroll(+100) clip=87.750 offset=87.750 size=480.000 | r2 sv=-19.750 gl=-7.500 off | r3 sv=20.250 gl=32.500 px31..=0.00,0.75,0.25 blend | r4 sv=60.250 gl=72.500 px71..=0.00,0.75,0.25 blend
//   1x F6 initial clip=0.000 offset=0.000 size=481.000 | r0 sv=0.300 gl=0.300 px-1..=1.00,0.00 crisp | r1 sv=40.300 gl=40.300 px39..=0.00,1.00,0.00 crisp | r2 sv=80.300 gl=80.300 px79..=0.00,1.00,0.00 crisp
//   1x F6 clip.scroll(+100) clip=100.000 offset=100.000 size=481.000 | r2 sv=-19.700 gl=-19.700 off | r3 sv=20.300 gl=20.300 px19..=0.00,1.00,0.00 crisp | r4 sv=60.300 gl=60.300 px59..=0.00,1.00,0.00 crisp
//   backingScaleFactor=1.0 injected displayScale=2 screen=
//   2x C0 control y=10.0 hair px19..=0.00,1.00,1.00,0.00 crisp
//   2x C0 control y=30.25 hair px59..=0.00,0.00,1.00,1.00 crisp
//   2x C0 control y=50.5 hair px100..=0.00,1.00,1.00,0.00 crisp
//   2x C0 control y=70.3 hair px139..=0.00,0.00,1.00,1.00 crisp
//   2x C0 control y=90.75 hair px180..=0.00,0.00,1.00,1.00 crisp
//   2x F0 initial clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px79..=0.00,1.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px159..=0.00,1.00,1.00,0.00 crisp
//   2x F0 clip.scroll(+100) clip=100.000 offset=100.000 size=480.000 | r2 sv=-20.000 gl=-20.000 off | r3 sv=20.000 gl=20.000 px39..=0.00,1.00,1.00,0.00 crisp | r4 sv=60.000 gl=60.000 px119..=0.00,1.00,1.00,0.00 crisp
//   2x F1 initial clip=99.000 offset=99.000 size=399.500 | r10 sv=234.000 gl=234.000 px467..=0.00,1.00,1.00,0.00 crisp | r11 sv=267.300 gl=267.300 px533..=0.00,0.00,1.00,1.00 crisp
//   2x F1 append1 clip=133.000 offset=133.000 size=433.000 | r11 sv=233.300 gl=233.300 px465..=0.00,0.00,1.00,1.00 crisp | r12 sv=266.600 gl=266.600 px532..=0.00,1.00,1.00,0.00 crisp
//   2x F1 append2 clip=166.000 offset=166.000 size=466.000 | r12 sv=233.600 gl=233.600 px466..=0.00,1.00,1.00,0.00 crisp | r13 sv=266.900 gl=266.900 px532..=0.00,0.00,1.00,1.00 crisp
//   2x F2 words3 clip=53.000 offset=53.000 size=353.000 | r9 sv=246.700 gl=246.700 px492..=0.00,1.00,1.00,0.00 crisp | r10 sv=280.000 gl=280.000 px559..=0.00,1.00,1.00,0.00 crisp
//   2x F2 words4 clip=53.000 offset=53.000 size=353.000 | r9 sv=246.700 gl=246.700 px492..=0.00,1.00,1.00,0.00 crisp | r10 sv=280.000 gl=280.000 px559..=0.00,1.00,1.00,0.00 crisp
//   2x F2 words6 clip=53.000 offset=53.000 size=353.000 | r9 sv=246.700 gl=246.700 px492..=0.00,1.00,1.00,0.00 crisp | r10 sv=280.000 gl=280.000 px559..=0.00,1.00,1.00,0.00 crisp
//   2x F2 words8 clip=53.000 offset=53.000 size=353.000 | r9 sv=246.700 gl=246.700 px492..=0.00,1.00,1.00,0.00 crisp | r10 sv=280.000 gl=280.000 px559..=0.00,1.00,1.00,0.00 crisp
//   2x F2 words10 clip=69.000 offset=69.000 size=369.000 | r9 sv=230.700 gl=230.700 px460..=0.00,1.00,1.00,0.00 crisp | r10 sv=264.000 gl=264.000 px527..=0.00,1.00,1.00,0.00 crisp
//   2x F2 words12 clip=69.000 offset=69.000 size=369.000 | r9 sv=230.700 gl=230.700 px460..=0.00,1.00,1.00,0.00 crisp | r10 sv=264.000 gl=264.000 px527..=0.00,1.00,1.00,0.00 crisp
//   2x F2 words14 clip=69.000 offset=69.000 size=369.000 | r9 sv=230.700 gl=230.700 px460..=0.00,1.00,1.00,0.00 crisp | r10 sv=264.000 gl=264.000 px527..=0.00,1.00,1.00,0.00 crisp
//   2x F3 scrollTo.bottom clip=99.000 offset=99.000 size=399.500 | r10 sv=234.000 gl=234.000 px467..=0.00,1.00,1.00,0.00 crisp | r11 sv=267.300 gl=267.300 px533..=0.00,0.00,1.00,1.00 crisp
//   2x F3 append,stay clip=99.000 offset=99.000 size=433.000 | r11 sv=267.300 gl=267.300 px533..=0.00,0.00,1.00,1.00 crisp | r12 sv=300.600 gl=300.600 off
//   2x F3 scrollTo.bottom2 clip=133.000 offset=133.000 size=433.000 | r11 sv=233.300 gl=233.300 px465..=0.00,0.00,1.00,1.00 crisp | r12 sv=266.600 gl=266.600 px532..=0.00,1.00,1.00,0.00 crisp
//   2x F4a initial clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px79..=0.00,1.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px159..=0.00,1.00,1.00,0.00 crisp
//   2x F4a scrollPosition.y=0.3 clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px79..=0.00,1.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px159..=0.00,1.00,1.00,0.00 crisp
//   2x F4a scrollPosition.y=100.3 clip=100.000 offset=100.000 size=480.000 | r2 sv=-20.000 gl=-20.000 off | r3 sv=20.000 gl=20.000 px39..=0.00,1.00,1.00,0.00 crisp | r4 sv=60.000 gl=60.000 px119..=0.00,1.00,1.00,0.00 crisp
//   2x F4a scrollPosition.y=100.7 clip=101.000 offset=101.000 size=480.000 | r2 sv=-21.000 gl=-21.000 off | r3 sv=19.000 gl=19.000 px37..=0.00,1.00,1.00,0.00 crisp | r4 sv=59.000 gl=59.000 px117..=0.00,1.00,1.00,0.00 crisp
//   2x F4a scrollPosition.y=100.8 clip=101.000 offset=101.000 size=480.000 | r2 sv=-21.000 gl=-21.000 off | r3 sv=19.000 gl=19.000 px37..=0.00,1.00,1.00,0.00 crisp | r4 sv=59.000 gl=59.000 px117..=0.00,1.00,1.00,0.00 crisp
//   2x F4b initial clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px79..=0.00,1.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px159..=0.00,1.00,1.00,0.00 crisp
//   2x F4b clip.scroll(0.15) clip=0.150 offset=0.150 size=480.000 | r0 sv=-0.150 gl=-0.150 px-2..=1.00,0.70 blend | r1 sv=39.850 gl=39.850 px78..=0.00,0.30,1.00,0.70 blend | r2 sv=79.850 gl=79.850 px158..=0.00,0.30,1.00,0.70 blend
//   2x F4b clip.scroll(0.3) clip=0.300 offset=0.300 size=480.000 | r0 sv=-0.300 gl=-0.300 px-2..=1.00,0.40 blend | r1 sv=39.700 gl=39.700 px78..=0.00,0.60,1.00,0.40 blend | r2 sv=79.700 gl=79.700 px158..=0.00,0.60,1.00,0.40 blend
//   2x F4b clip.scroll(0.45) clip=0.450 offset=0.450 size=480.000 | r0 sv=-0.450 gl=-0.450 px-2..=1.00,0.10 blend | r1 sv=39.550 gl=39.550 px78..=0.00,0.90,1.00,0.10 blend | r2 sv=79.550 gl=79.550 px158..=0.00,0.90,1.00,0.10 blend
//   2x F4b clip.scroll(100.15) clip=100.150 offset=100.150 size=480.000 | r2 sv=-20.150 gl=-20.150 off | r3 sv=19.850 gl=19.850 px38..=0.00,0.30,1.00,0.70 blend | r4 sv=59.850 gl=59.850 px118..=0.00,0.30,1.00,0.70 blend
//   2x F4c initial clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px79..=0.00,1.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px159..=0.00,1.00,1.00,0.00 crisp
//      event scrollingDeltaY=0.0 precise=true
//   2x F4c wheel(-0.3) clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px79..=0.00,1.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px159..=0.00,1.00,1.00,0.00 crisp | r3 sv=120.000 
//      event scrollingDeltaY=0.0 precise=true
//   2x F4c wheel(-0.7) clip=0.000 offset=0.000 size=480.000 | r0 sv=0.000 gl=0.000 px-1..=1.00,1.00,0.00 crisp | r1 sv=40.000 gl=40.000 px79..=0.00,1.00,1.00,0.00 crisp | r2 sv=80.000 gl=80.000 px159..=0.00,1.00,1.00,0.00 crisp | r3 sv=120.000 
//      event scrollingDeltaY=-8.0 precise=true
//   2x F4c wheel(-1.0) clip=8.000 offset=8.000 size=480.000 | r0 sv=-8.000 gl=-8.000 off | r1 sv=32.000 gl=32.000 px63..=0.00,1.00,1.00,0.00 crisp | r2 sv=72.000 gl=72.000 px143..=0.00,1.00,1.00,0.00 crisp | r3 sv=112.000 gl=112.000 px223..=0.0
//      event scrollingDeltaY=-80.0 precise=true
//   2x F4c wheel(-10.0) clip=88.000 offset=88.000 size=480.000 | r0 sv=-88.000 gl=-88.000 off | r1 sv=-48.000 gl=-48.000 off | r2 sv=-8.000 gl=-8.000 off | r3 sv=32.000 gl=32.000 px63..=0.00,1.00,1.00,0.00 crisp | r4 sv=72.000 gl=72.000 px143..
//      event scrollingDeltaY=-80.0 precise=true
//   2x F4c wheel(-10.6) clip=168.000 offset=168.000 size=480.000 | r0 sv=-168.000 gl=-168.000 off | r1 sv=-128.000 gl=-128.000 off | r2 sv=-88.000 gl=-88.000 off | r3 sv=-48.000 gl=-48.000 off | r4 sv=-8.000 gl=-8.000 off
//   2x F5 initial clip=-12.000 offset=-12.000 size=480.000 | r0 sv=0.000 gl=12.250 px23..=0.00,1.00,1.00,0.00 crisp | r1 sv=40.000 gl=52.250 px103..=0.00,1.00,1.00,0.00 crisp | r2 sv=80.000 gl=92.250 px183..=0.00,1.00,1.00,0.00 crisp
//   2x F5 clip.scroll(+100) clip=87.750 offset=87.750 size=480.000 | r2 sv=-19.750 gl=-7.500 off | r3 sv=20.250 gl=32.500 px64..=0.50,1.00,0.50,0.00 blend | r4 sv=60.250 gl=72.500 px144..=0.50,1.00,0.50,0.00 blend
//   2x F6 initial clip=0.000 offset=0.000 size=480.500 | r0 sv=0.300 gl=0.300 px-1..=0.00,1.00,1.00 crisp | r1 sv=40.300 gl=40.300 px79..=0.00,0.00,1.00,1.00 crisp | r2 sv=80.300 gl=80.300 px159..=0.00,0.00,1.00,1.00 crisp
//   2x F6 clip.scroll(+100) clip=100.000 offset=100.000 size=480.500 | r2 sv=-19.700 gl=-19.700 off | r3 sv=20.300 gl=20.300 px39..=0.00,0.00,1.00,1.00 crisp | r4 sv=60.300 gl=60.300 px119..=0.00,0.00,1.00,1.00 crisp
//
// READING. (1) Leaf origins: every SwiftUI-placed hairline at a fractional layout position (C0 30.25 / 70.3 / 90.75; F1 233.3, 266.6; F2
// 246.7; F5 12.25; F6 0.3 padding) is **crisp** at 1x and at 2x: SwiftUI rounds each leaf's origin to the nearest device pixel, so a fractional
// layout position never draws blended. (2) Scroll position: in every arm SwiftUI drives (F1, F2, F3, F4a, F5's initial) the clip origin and the
// reported `contentOffset` are the same number and a whole point (F4a asked for 0.3, 100.3, 100.7, got 0, 100, 101 at both passes; F1 at 2x
// asked for the bottom, 99.5, got 99.0); `contentOffset` is never fractional unless AppKit was handed a fractional bounds directly (F4b, F5's
// scroll). (3) Where a fractional clip origin does exist (F4b, F5) the rows draw **blended**: SwiftUI snaps its own leaf origins and its
// scroll position, not an AppKit clip it did not set. So SwiftUI never presents a half-pixel scroll offset of its own making: the drawn
// position and the reported one are both on a grid (whole points measured at 1x, whole points at 2x offscreen with the grid at a real 2x
// unmeasured). Verdict for cure (1) vs (2): the evidence favours snapping the painted and the reported offset (cure 1).

import AppKit
import SwiftUI

@MainActor final class M: ObservableObject {
    @Published var rows = 12
    @Published var words = 4
    @Published var pos = ScrollPosition(y: 0)
    @Published var proxyTick = 0
    let controlYs: [CGFloat] = [10, 30.25, 50.5, 70.3, 90.75]
    var rects: [Int: (CGRect, CGRect)] = [:]
    var offset = CGPoint.zero
    var size = CGSize.zero
}

let longText = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon"
func words(_ n: Int) -> String { longText.split(separator: " ").prefix(n).joined(separator: " ") }

struct Row: View {
    @ObservedObject var m: M
    let i: Int
    let h: CGFloat?
    var text: String? = nil
    var body: some View {
        Group {
            if let text { Text(text).font(.system(size: 13)).frame(width: 280, alignment: .leading).padding(.vertical, 2) }
            else { Color.white.frame(height: h) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .topLeading) { Color.black.frame(width: 100, height: 1) }
        .onGeometryChange(for: [CGRect].self) { p in [p.frame(in: .scrollView), p.frame(in: .global)] } action: { r in
            m.rects[i] = (r[0], r[1])
        }
    }
}

struct Arm: View {
    @ObservedObject var m: M
    let arm: String
    var scale: CGFloat = 1
    var body: some View {
        let sv = scroll
        return sv
            .onScrollGeometryChange(for: [CGFloat].self) { g in [g.contentOffset.y, g.contentSize.height] } action: { _, n in
                m.offset.y = n[0]; m.size.height = n[1]
            }
            .frame(width: 300, height: 300)
            .background(Color.white)
            .environment(\.displayScale, scale)
    }
    @ViewBuilder var scroll: some View {
        switch arm {
        case "C0": ZStack(alignment: .topLeading) { ForEach(Array(m.controlYs.enumerated()), id: \.offset) { _, y in Color.black.frame(width: 100, height: 1).offset(y: y) } }.frame(width: 300, height: 300, alignment: .topLeading)
        case "F0": ScrollView { VStack(spacing: 0) { ForEach(0..<m.rows, id: \.self) { Row(m: m, i: $0, h: 40) } } }
        case "F1": ScrollView { VStack(spacing: 0) { ForEach(0..<m.rows, id: \.self) { Row(m: m, i: $0, h: 33.3) } } }.defaultScrollAnchor(.bottom)
        case "F2":
            ScrollView { VStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { Row(m: m, i: $0, h: 33.3) }
                Row(m: m, i: 10, h: nil, text: words(m.words))
            } }.defaultScrollAnchor(.bottom)
        case "F3":
            ScrollViewReader { p in
                ScrollView { VStack(spacing: 0) {
                    ForEach(0..<m.rows, id: \.self) { Row(m: m, i: $0, h: 33.3).id($0) }
                } }.onChange(of: m.proxyTick) { _, _ in p.scrollTo(m.rows - 1, anchor: .bottom) }
            }
        case "F4": ScrollView { VStack(spacing: 0) { ForEach(0..<m.rows, id: \.self) { Row(m: m, i: $0, h: 40) } } }.scrollPosition($m.pos)
        case "F5": ScrollView { VStack(spacing: 0) { ForEach(0..<m.rows, id: \.self) { Row(m: m, i: $0, h: 40) } } }.contentMargins(12.25, for: .scrollContent)
        default: ScrollView { VStack(spacing: 0) { ForEach(0..<m.rows, id: \.self) { Row(m: m, i: $0, h: 40) } }.padding(0.3) }
        }
    }
}

func find<T: NSView>(_ v: NSView, _ t: T.Type) -> T? {
    if let x = v as? T { return x }
    for s in v.subviews { if let x = find(s, t) { return x } }
    return nil
}

func f(_ x: CGFloat) -> String { String(format: "%.3f", Double(x)) }

@MainActor func settle(_ s: Double = 0.5) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

/// The view drawn into a bitmap whose pixel size is `scale` times its point size (`rep.size` stays in points), so a 2x raster is
/// made on a 1x display.
@MainActor func snapshot(_ host: NSView, scale: Int) -> NSBitmapImageRep? {
    let w = Int(host.bounds.width) * scale, h = Int(host.bounds.height) * scale
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

/// Ink (1 - red) of the pixel rows around a 1 pt hairline whose top is at `yPt`: `scale + 2` rows from one above the row the top
/// falls in. `crisp` when every value is 0 or 1 (the hairline covers whole pixels), `blend` when any is between, `blank` when the
/// bitmap holds no ink at all.
@MainActor func coverage(_ rep: NSBitmapImageRep?, yPt: CGFloat, scale: Int) -> String {
    guard let rep else { return "norep" }
    let x = 25 * scale   // inside the 100 pt-wide hairline
    let top = Int((yPt * CGFloat(scale)).rounded(.down))
    var vals: [Double] = []
    for py in (top - 1)...(top + scale) where py >= 0 && py < rep.pixelsHigh && x < rep.pixelsWide {
        let c = rep.colorAt(x: x, y: py)?.usingColorSpace(.deviceRGB)
        vals.append(1 - Double(c?.redComponent ?? 1))
    }
    if vals.isEmpty { return "off" }
    let kind = vals.allSatisfy { $0 < 0.02 } ? "blank" : vals.allSatisfy { $0 < 0.02 || $0 > 0.98 } ? "crisp" : "blend"
    return "px\(top - 1)..=" + vals.map { String(format: "%.2f", $0) }.joined(separator: ",") + " " + kind
}

@MainActor func report(_ arm: String, _ step: String, _ m: M, _ host: NSView, _ scale: Int, _ idx: [Int]) {
    let sv = find(host, NSScrollView.self)
    let clip = sv?.contentView.bounds.origin.y ?? .nan
    let rep = snapshot(host, scale: scale)
    var line = "\(scale)x \(arm) \(step) clip=\(f(clip)) offset=\(f(m.offset.y)) size=\(f(m.size.height))"
    for i in idx {
        guard let r = m.rects[i] else { continue }
        line += " | r\(i) sv=\(f(r.0.minY)) gl=\(f(r.1.minY)) \(coverage(rep, yPt: r.1.minY, scale: scale))"
    }
    print(line)
}

@MainActor func wheel(_ sv: NSScrollView, dy: Double) {
    guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0) else { return }
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
    cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
    cg.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: dy)
    if let e = NSEvent(cgEvent: cg) {
        print("   event scrollingDeltaY=\(e.scrollingDeltaY) precise=\(e.hasPreciseScrollingDeltas)")
        sv.scrollWheel(with: e)
    }
}

@MainActor func run(scale: Int) {
    for arm in ["C0", "F0", "F1", "F2", "F3", "F4a", "F4b", "F4c", "F5", "F6"] {
        let m = M()
        if arm == "F2" { m.words = 3 }
        let host = NSHostingView(rootView: Arm(m: m, arm: String(arm.prefix(2)), scale: CGFloat(scale)))
        let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        if arm == "C0" { print("backingScaleFactor=\(win.backingScaleFactor) injected displayScale=\(scale) screen=\(win.screen?.localizedName ?? "none")") }
        settle(0.8)
        let sv = find(host, NSScrollView.self)
        func last(_ k: Int) -> [Int] { Array(max(0, m.rects.count - k)..<m.rects.count) }
        switch arm {
        case "C0":
            let rep = snapshot(host, scale: scale)
            for y in m.controlYs { print("\(scale)x C0 control y=\(y) hair \(coverage(rep, yPt: y, scale: scale))") }
        case "F1":
            report(arm, "initial", m, host, scale, last(2))
            for s in 1...2 { m.rows += 1; settle(); report(arm, "append\(s)", m, host, scale, last(2)) }
        case "F2":
            report(arm, "words3", m, host, scale, [9, 10])
            for n in [4, 6, 8, 10, 12, 14] { m.words = n; settle(); report(arm, "words\(n)", m, host, scale, [9, 10]) }
        case "F3":
            m.proxyTick += 1; settle(); report(arm, "scrollTo.bottom", m, host, scale, last(2))
            m.rows += 1; settle(); report(arm, "append,stay", m, host, scale, last(2))
            m.proxyTick += 1; settle(); report(arm, "scrollTo.bottom2", m, host, scale, last(2))
        case "F4a":
            report(arm, "initial", m, host, scale, [0, 1, 2])
            // 100.3 and 100.7 tell a device-pixel snap (2x: 100.5, 101.0) from a whole-point one (100, 101) from none.
            for y in [0.3, 100.3, 100.7, 100.8] as [CGFloat] {
                m.pos = ScrollPosition(y: y); settle(); report(arm, "scrollPosition.y=\(y)", m, host, scale, y > 50 ? [2, 3, 4] : [0, 1, 2])
            }
        case "F4c":
            // A pixel-unit wheel event with a fractional delta, sent straight to the NSScrollView (not posted: no permission, no focus).
            report(arm, "initial", m, host, scale, [0, 1, 2])
            for d in [-0.3, -0.7, -1.0, -10.0, -10.6] as [Double] {
                if let sv { wheel(sv, dy: d) }
                settle(0.3); report(arm, "wheel(\(d))", m, host, scale, [0, 1, 2, 3, 4])
            }
        case "F4b":
            report(arm, "initial", m, host, scale, [0, 1, 2])
            for y in [0.15, 0.3, 0.45, 100.15] as [CGFloat] {
                if let c = sv?.contentView { c.scroll(to: NSPoint(x: 0, y: y)); sv?.reflectScrolledClipView(c) }
                settle(); report(arm, "clip.scroll(\(y))", m, host, scale, y > 50 ? [2, 3, 4] : [0, 1, 2])
            }
        default:
            report(arm, "initial", m, host, scale, [0, 1, 2])
            if let c = sv?.contentView { c.scroll(to: NSPoint(x: 0, y: (arm == "F5" ? -12.25 : 0) + 100)); sv?.reflectScrolledClipView(c) }
            settle(); report(arm, "clip.scroll(+100)", m, host, scale, [2, 3, 4])
        }
        win.orderOut(nil)
        win.close()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    run(scale: 1)
    run(scale: 2)
}

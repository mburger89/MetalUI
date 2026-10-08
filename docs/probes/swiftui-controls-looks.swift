// SwiftUI probe: controls and looks (C10; rulings LK-* in
// docs/superpowers/2026-10-08-controls-looks-decisions.md, spec
// docs/superpowers/specs/2026-10-08-controls-looks-design.md).
//
// HOW TO RUN (SA-O's compiled form; the JIT form fails to link on macOS 27):
//
//   xcrun swiftc docs/probes/swiftui-controls-looks.swift -o /tmp/lk-probe && /tmp/lk-probe 2>&1 | grep -v 'Connection\]'
//
// GROUPS, INSTRUMENTS AND CONTROLS (output recorded at the end of this header).
//   P  positive controls. P0: a plain `onTapGesture` in a `FirstMouseHost`
//      window reads one tap — the click instrument delivers (the input-APIs
//      probe's instrument). P1: an `ImageRenderer` render of a pure red
//      20×20 square on white reads (255,0,0) inside and white outside — the
//      pixel instrument reads exact colours. P2: a sized `Text` reports its
//      own size through `onGeometryChange` — the size instrument.
//   S  `Slider(value:in:onEditingChanged:)`. Events are queued with
//      `NSApp.postEvent` BEFORE the press is sent, so a control that runs
//      its own tracking loop (an `NSSlider`) dequeues them, and one that does
//      not gets them from the run-loop spin. Every binding write and every
//      editing callback is logged in order.
//   V  `ProgressView`: own size (onGeometryChange), fitting size, the AX
//      tree, and the backing view classes with their layers' running
//      animation keys (`layer.animationKeys()` over the subtree) — the
//      instrument for "is it animating"; V-RM repeats the spinner with the
//      NSWorkspace Reduce Motion getter swizzled in-process (the transactions
//      probe's technique; the system setting is never touched).
//   C  `ColorPicker`: size, AX, a click on the well (does `NSColorPanel`
//      open, does it show alpha), then `NSColorPanel.shared.color` set
//      programmatically while the well is active: what the binding receives
//      (its description, its `NSColor` colour space and components, and
//      `resolve(in:)`'s components).
//   K  `KeyframeTimeline` values (pure function, no window) for the four
//      keyframe kinds, and a window arm (`keyframeAnimator`) logging what the
//      content and the keyframes closure receive across triggers.
//   G  `LinearGradient`/`RadialGradient` pixels at scale 1 (ImageRenderer).
//      G3's separating arm: a diagonal gradient in a 200×100 rect — isolines
//      perpendicular in POINT space give t(100,0)=0.40, t(0,50)=0.10; in
//      UNIT space both read 0.25.
//   B  `.blur(radius:)` pixels: B1 the profile of a blurred edge (fit
//      against a Gaussian of sigma = radius, divergence 105's method); B2
//      separates per-leaf from composited: a blue square drawn over an equal
//      red square, blurred — composited shows no red at the edge, per-leaf
//      shows red bleeding (blue α over red α).
//   M  materials: ImageRenderer AND `cacheDisplay` of a hosted window, over
//      a red/blue striped backdrop, light and dark — what SwiftUI draws.

//
// RECORDED 2026-10-08 by the C10 (controls and looks) designer, macOS 27.0.1
// (26A434), Apple Swift 6.4, screen LOCKED (lock probe: CGSSessionScreenIsLocked
// = 1, displayAsleep main: 1 — the click, AX and animation instruments work
// locked, as the input-APIs and transactions probes found; P0 is the click
// control). Compiled form run twice: stdout byte-identical (160 lines), exit 0,
// stderr empty. RE-RUN 2026-10-08 by the C10 critic (`LK-O`), same screen
// state, compiled form, twice: run 2 byte-identical to the lines below; run 1
// differed on `M1 ... light regular` only, by one level in two samples
// (blue stripe (222, 136, 170), edge (224, 136, 166)) — M1 is not byte-stable.
// M4 (cacheDisplay) keeps the stripes apart: it does not composite the
// material and is a discarded instrument, not an answer. INSTRUMENT HISTORY (discarded runs, not answers): run 1
// queued the drags and the release with `NSApp.postEvent`, which nothing
// dequeues without `NSApp.run` — P0 read "-" and S1 lost its release; runs
// 1-3 read empty AX trees until `AXEnhancedUserInterface` was set on NSApp
// (the accessibility-bridge probe's activation); run 5's repeating animator
// kept logging into later arms until K14 tore its window down.
//
//   --- P: positive controls
//     P0 onTapGesture click: tap
//     P1 red square: (20,20)=(255,0,0) (5,5)=(255,255,255)
//     P2 Text("Go").frame(width: 50, height: 20): own 50x20 fitting 50x20
//   --- S: Slider(value:in:onEditingChanged:) in a 200-wide frame centred in 300x120
//     S1 press x100, drag x120, x140, release x140: editing true | set 0.222 | set 0.333 | set 0.444 | editing false
//     S2 press and release at x220, no drag: editing true | set 0.889 | editing false
//     S3 press x150, a drag that does not move, release: editing true | set 0.500 | editing false
//     S4 ax: .role=AXSlider label=nil value=0.5 min=0 max=1 / ..role=AXValueIndicator label=nil value=nil min=nil max=nil
//     S4 AX increment: editing true | set 0.600 | editing false
//     S4 AX decrement: editing true | set 0.500 | editing false
//     S5 a model write from outside: -
//     S6 backing views: FirstMouseHost 300x120 / .KeyViewProxy 200x16 / ._FocusRingView 200x16
//     S7 disabled slider press/drag/release: -
//   --- V: ProgressView sizes (own; fitting)
//     V0 ProgressView(): own 32x32 fitting 32x32
//     V0 ProgressView().controlSize(.small): own 16x16 fitting 16x16
//     V0 ProgressView().controlSize(.mini): own 10x10 fitting 10x10
//     V0 ProgressView().controlSize(.large): own 32x32 fitting 32x32
//     V1 ProgressView("Loading"): own 48x52 fitting 48x53
//     V2 ProgressView().progressViewStyle(.linear): own 300x20 fitting 0x20
//     V3 ProgressView(value: 0.3): own 300x20 fitting 0x20
//     V3 ProgressView(value: 0.3) in 300x120 .frame(width: 100): own 100x20 fitting 100x20
//     V3 ProgressView(value: 0.3).controlSize(.small): own 300x12 fitting 0x12
//     V4 ProgressView("Loading", value: 0.3): own 300x36 fitting 48x36
//     V4 ProgressView(value: 0.3) { Text("L") } currentValueLabel: { Text("30%") }: own 300x50 fitting 24x50
//     V5 ProgressView(value: 0.3).progressViewStyle(.circular): own 32x32 fitting 32x32
//     V6 ProgressView(value: nil as Double?): own 300x20 fitting 0x20
//   --- V: ProgressView AX and backing views
//     V7 ProgressView(): ax: .role=AXBusyIndicator label=nil value=0 min=nil max=nil
//       views: FirstMouseHost 32x32 anims=["CUIIndeterminateProgressAnimation"] / .AppKitPlatformViewHost 32x32 anims=["CUIIndeterminateProgressAnimation"] / ..NSProgressIndicator 32x32 NSProgressIndicator style=1 indeterminate=true value=0.0 min=0.0 max=1.0 controlSize=0 anims=["CUIIndeterminateProgressAnimation"]
//     V7 ProgressView(value: 0.3): ax: .role=AXProgressIndicator label=nil value=0.3 min=0 max=1
//       views: FirstMouseHost 300x20 / .AppKitPlatformViewHost 300x20 / ..NSProgressIndicator 300x20 NSProgressIndicator style=0 indeterminate=false value=0.3 min=0.0 max=1.0 controlSize=0
//     V7 ProgressView("Loading", value: 0.3): ax: .role=AXProgressIndicator label=Loading value=0.3 min=0 max=1
//       views: FirstMouseHost 300x36 / .AppKitPlatformViewHost 300x20 / ..NSProgressIndicator 300x20 NSProgressIndicator style=0 indeterminate=false value=0.3 min=0.0 max=1.0 controlSize=0
//     V8 ProgressView(value: 1.5, total: 1): ax: .role=AXProgressIndicator label=nil value=1 min=0 max=1
//       views: FirstMouseHost 300x20 / .AppKitPlatformViewHost 300x20 / ..NSProgressIndicator 300x20 NSProgressIndicator style=0 indeterminate=false value=1.0 min=0.0 max=1.0 controlSize=0
//     V8 ProgressView(value: -1, total: 1): ax: .role=AXBusyIndicator label=nil value=0 min=nil max=nil
//       views: FirstMouseHost 300x20 anims=["overallIndeterminateAnimation"] / .AppKitPlatformViewHost 300x20 anims=["overallIndeterminateAnimation"] / ..NSProgressIndicator 300x20 NSProgressIndicator style=0 indeterminate=true value=0.0 min=0.0 max=1.0 controlSize=0 anims=["overallIndeterminateAnimation"]
//     V8 ProgressView(value: 5, total: 10): ax: .role=AXProgressIndicator label=nil value=0.5 min=0 max=1
//       views: FirstMouseHost 300x20 / .AppKitPlatformViewHost 300x20 / ..NSProgressIndicator 300x20 NSProgressIndicator style=0 indeterminate=false value=0.5 min=0.0 max=1.0 controlSize=0
//     V8 ProgressView(value: 0, total: 0): ax: .role=AXBusyIndicator label=nil value=0 min=nil max=nil
//       views: FirstMouseHost 300x20 anims=["overallIndeterminateAnimation"] / .AppKitPlatformViewHost 300x20 anims=["overallIndeterminateAnimation"] / ..NSProgressIndicator 300x20 NSProgressIndicator style=0 indeterminate=true value=0.0 min=0.0 max=1.0 controlSize=0 anims=["overallIndeterminateAnimation"]
//     V9 ImageRenderer determinate bar x10..109: row y=20: 8:(255, 255, 255) 16:(255, 204, 0) 24:(255, 204, 0) 32:(255, 204, 0) 40:(255, 204, 0) 48:(255, 204, 0) 56:(255, 204, 0) 64:(255, 204, 0) 72:(255, 204, 0) 80:(255, 204, 0) 88:(255, 204, 0) 96:(255, 204, 0) 104:(255, 204, 0) 112:(255, 255, 255)
//     V9 column x=20: 10:255 11:255 12:255 13:255 14:255 15:255 16:255 17:255 18:255 19:255 20:255 21:255 22:255 23:255 24:255 25:255 26:255 27:255 28:255 29:255 30:255
//     V12 Text("Loading"): own 48x16 fitting 48x16
//     V12 Text("L"): own 7x16 fitting 7x16
//     V12 Text("30%"): own 28x16 fitting 28x16
//     V12 Text("Tint"): own 23x16 fitting 23x16
//     V12 ColorPicker("A much longer title", selection:): own 170x24 fitting 170x24
//     V12 Text("A much longer title"): own 114x16 fitting 114x16
//     V13 CUIIndeterminateProgressAnimation: CAKeyframeAnimation duration=0.8 repeatCount=3.4028235e+38 speed=1.0 keyPath=contentsRect values=24 calc=discrete
//     V14 cacheDisplay determinate bar (scale 2), column x=20pt: 10:(0, 0, 0) 11:(0, 0, 0) 12:(0, 0, 0) 13:(0, 0, 0) 14:(0, 0, 0) 15:(0, 0, 0) 16:(170, 170, 170) 17:(170, 170, 170) 18:(170, 170, 170) 19:(170, 170, 170) 20:(170, 170, 170) 21:(170, 170, 170) 22:(170, 170, 170) 23:(170, 170, 170) 24:(0, 0, 0) 25:(0, 0, 0) 26:(0, 0, 0) 27:(0, 0, 0) 28:(0, 0, 0) 29:(0, 0, 0) 30:(0, 0, 0)
//     V14 row y=20pt: 8:(0, 0, 0) 16:(170, 170, 170) 24:(170, 170, 170) 32:(170, 170, 170) 40:(20, 20, 20) 48:(20, 20, 20) 56:(20, 20, 20) 64:(20, 20, 20) 72:(20, 20, 20) 80:(20, 20, 20) 88:(20, 20, 20) 96:(20, 20, 20) 104:(20, 20, 20) 112:(0, 0, 0)
//     V10 ProgressView() with Reduce Motion reading true: ax: .role=AXBusyIndicator label=nil value=0 min=nil max=nil
//       views: FirstMouseHost 32x32 anims=["CUIIndeterminateProgressAnimation"] / .AppKitPlatformViewHost 32x32 anims=["CUIIndeterminateProgressAnimation"] / ..NSProgressIndicator 32x32 NSProgressIndicator style=1 indeterminate=true value=0.0 min=0.0 max=1.0 controlSize=0 anims=["CUIIndeterminateProgressAnimation"]
//     V10 control: ProgressView() after the swizzle reads false again: ax: .role=AXBusyIndicator label=nil value=0 min=nil max=nil
//       views: FirstMouseHost 32x32 anims=["CUIIndeterminateProgressAnimation"] / .AppKitPlatformViewHost 32x32 anims=["CUIIndeterminateProgressAnimation"] / ..NSProgressIndicator 32x32 NSProgressIndicator style=1 indeterminate=true value=0.0 min=0.0 max=1.0 controlSize=0 anims=["CUIIndeterminateProgressAnimation"]
//   --- C: ColorPicker
//     C0 ColorPicker("Tint", selection:): own 79x24 fitting 79x24
//     C0 ColorPicker("Tint", selection:).labelsHidden(): own 48x24 fitting 48x24
//     C1 ax: .role=AXStaticText label=nil value=Tint min=nil max=nil / .role=AXColorWell label=nil value=rgb 1 0 0 1 min=nil max=nil
//     C1 views: FirstMouseHost 300x120 / .AppKitPlatformViewHost 48x24 / ..PlatformColorWell 48x24 / ..._NSCoreHostingView 48x24
//     C2 NSColorWell count=1 frame=(0.0, 0.0, 48.0, 24.0) style=0 supportsAlpha=true active=false
//     C2 panel visible before click: false
//     C3 after a click on the well: active=true panelVisible=true showsAlpha=true log=-
//     C4 panel.color = sRGB(0.2,0.4,0.6,0.5): set desc=AppKitPlatformColorProvider(platformColor: sRGB IEC61966-2.1 colorspace hdrm(1) 0.2 0.4 0.6 0.5) ns=sRGB IEC61966-2.1 comps=["0.200", "0.400", "0.600", "0.500"] resolved=(0.200,0.400,0.600,0.500)
//     C5 panel.color = P3(1,0,0,1): set desc=AppKitPlatformColorProvider(platformColor: Display P3 colorspace 1 0 0 1) ns=Display P3 comps=["1.000", "0.000", "0.000", "1.000"] resolved=(1.093,-0.227,-0.150,1.000)
//     C6 panel.color = calibratedWhite 0.5: set desc=AppKitPlatformColorProvider(platformColor: NSCalibratedWhiteColorSpace 0.5 1) ns=Generic Gray comps=["0.500", "1.000"] resolved=(0.572,0.572,0.572,1.000)
//     C7 binding write from outside: well.color=sRGB IEC61966-2.1 (extended) colorspace hdrm(1) 0 1 0 1 panel=sRGB IEC61966-2.1 (extended) colorspace hdrm(1) 0 1 0 1 log=-
//     C8 supportsOpacity:false well.supportsAlpha=false
//     C8 panel showsAlpha=false log=-
//     C8 panel.color = sRGB(0.2,0.4,0.6,0.5) with supportsOpacity false: set desc=AppKitPlatformColorProvider(platformColor: sRGB IEC61966-2.1 colorspace hdrm(1) 0.2 0.4 0.6 1) ns=sRGB IEC61966-2.1 comps=["0.200", "0.400", "0.600", "1.000"] resolved=(0.200,0.400,0.600,1.000) | set desc=AppKitPlatformColorProvider(platformColor: sRGB IEC61966-2.1 colorspace hdrm(1) 0.2 0.4 0.6 1) ns=sRGB IEC61966-2.1 comps=["0.200", "0.400", "0.600", "1.000"] resolved=(0.200,0.400,0.600,1.000) | set desc=AppKitPlatformColorProvider(platformColor: sRGB IEC61966-2.1 colorspace hdrm(1) 0.2 0.4 0.6 1) ns=sRGB IEC61966-2.1 comps=["0.200", "0.400", "0.600", "1.000"] resolved=(0.200,0.400,0.600,1.000)
//   --- K: KeyframeTimeline values (time: value)
//     K1 Linear 0→10 (0.2) →-10 (0.2) →0 (0.2): duration=0.600 -0.100:0.000 0.000:0.000 0.050:2.500 0.100:5.000 0.150:7.500 0.200:10.000 0.250:5.000 0.300:0.000 0.350:-5.000 0.400:-10.000 0.500:-5.000 0.600:-0.000 0.800:0.000 1.000:0.000 1.500:0.000
//     K2 Linear 0→10 (0.4, .easeInOut): duration=0.400 -0.100:0.000 0.000:0.000 0.050:0.311 0.100:1.292 0.150:2.928 0.200:5.000 0.250:7.072 0.300:8.708 0.350:9.689 0.400:10.000 0.500:10.000 0.600:10.000 0.800:10.000 1.000:10.000 1.500:10.000
//     K3 Cubic 0→10→-10→0 (0.2 each): duration=0.600 -0.100:0.000 0.000:0.000 0.050:1.797 0.100:5.625 0.150:9.141 0.200:10.000 0.250:6.406 0.300:0.000 0.350:-6.406 0.400:-10.000 0.500:-5.625 0.600:0.000 0.800:0.000 1.000:0.000 1.500:0.000
//     K3b Cubic 0→10 (0.4) alone: duration=0.400 -0.100:0.000 0.000:0.000 0.050:0.430 0.100:1.562 0.150:3.164 0.200:5.000 0.250:6.836 0.300:8.437 0.350:9.570 0.400:10.000 0.500:10.000 0.600:10.000 0.800:10.000 1.000:10.000 1.500:10.000
//     K4 Spring 0→10 duration 0.4, Spring(duration 0.4, bounce 0): duration=0.400 -0.100:0.000 0.000:0.000 0.050:1.860 0.100:4.656 0.150:6.819 0.200:8.210 0.250:9.029 0.300:9.487 0.350:9.734 0.400:9.864 0.500:9.864 0.600:9.864 0.800:9.864 1.000:9.864 1.500:9.864
//     K4b Spring 0→10 no duration, Spring(duration 0.4, bounce 0.3): duration=1.273 -0.100:0.000 0.000:0.000 0.050:2.105 0.100:5.614 0.150:8.343 0.200:9.841 0.250:10.396 0.300:10.440 0.350:10.298 0.400:10.145 0.500:9.993 0.600:9.982 0.800:10.001 1.000:10.000 1.500:10.000
//     K4c Spring(0.4 spring, keyframe 0.2) then Linear→0 (0.2): duration=0.400 -0.100:0.000 0.000:0.000 0.050:1.860 0.100:4.656 0.150:6.819 0.200:8.210 0.250:6.158 0.300:4.105 0.350:2.053 0.400:0.000 0.500:0.000 0.600:0.000 0.800:0.000 1.000:0.000 1.500:0.000
//     K3c Cubic 0→10 (0.1) →0 (0.3), unequal: duration=0.400 0.025:1.562 0.050:5.000 0.075:8.437 0.100:10.000 0.150:9.259 0.200:7.407 0.250:5.000 0.300:2.593 0.350:0.741
//     K3d Linear→10, Cubic→0, Linear→5 (0.2 each): duration=0.600 0.050:2.500 0.100:5.000 0.150:7.500 0.200:10.000 0.250:9.609 0.300:5.625 0.350:1.328 0.400:0.000 0.500:2.500
//     K3e Cubic 0→10 (0.4) startVelocity 50 endVelocity 0: duration=0.400 0.050:2.344 0.100:4.375 0.200:7.500 0.300:9.375 0.350:9.844
//     K3f Cubic 0→10→30 (0.2 each, monotone): duration=0.400 0.050:0.859 0.100:3.125 0.150:6.328 0.250:15.234 0.300:21.875 0.350:27.578
//     K3g Cubic 0→10 (0.1) →30 (0.3), unequal, monotone: duration=0.400 0.025:1.211 0.050:4.062 0.075:7.383 0.175:16.289 0.250:22.812 0.325:27.930
//     K3h Cubic 0→10→30, then Linear holding 30: duration=0.600 0.250:15.234 0.300:21.875 0.350:27.578
//     K4d Spring(duration: 0.4, bounce: 0.0).settlingDuration = 0.600000; value(target 10, t 0.1) = 4.656
//     K4d Spring(duration: 0.4, bounce: 0.3).settlingDuration = 0.854188; value(target 10, t 0.1) = 5.614
//     K4d Spring(duration: 0.4, bounce: 0.5).settlingDuration = 1.157199; value(target 10, t 0.1) = 6.473
//     K4d Spring(duration: 0.4, bounce: -0.3).settlingDuration = 1.200000; value(target 10, t 0.1) = 3.724
//     K4d Spring(duration: 1.0, bounce: 0.0).settlingDuration = 1.500000; value(target 10, t 0.1) = 1.313
//     K4d Spring(duration: 1.0, bounce: 0.3).settlingDuration = 1.953928; value(target 10, t 0.1) = 1.457
//     K4d Spring(duration: 0.5, bounce: 0.15).settlingDuration = 0.876827; value(target 10, t 0.1) = 3.881
//     K4d Spring(duration: 0.2, bounce: 0.7).settlingDuration = 0.981661; value(target 10, t 0.1) = 13.679
//     K4e Linear→10 (0.2) then Spring→0: does the spring start with the linear's velocity (50/s)? duration=0.600 0.200:10.000 0.250:9.280 0.300:6.384 0.400:2.222 0.600:0.173
//     K5 Linear→10 (0.2), Move -5, Linear→0 (0.2): duration=0.400 -0.100:0.000 0.000:0.000 0.050:2.500 0.100:5.000 0.150:7.500 0.200:10.000 0.250:-3.750 0.300:-2.500 0.350:-1.250 0.400:0.000 0.500:0.000 0.600:0.000 0.800:0.000 1.000:0.000 1.500:0.000
//     K6 two tracks x (0.4 total), s (0.6): duration=0.600 -0.100:(0.000,1.000) 0.000:(0.000,1.000) 0.050:(2.500,1.083) 0.100:(5.000,1.167) 0.150:(7.500,1.250) 0.200:(10.000,1.333) 0.250:(7.500,1.417) 0.300:(5.000,1.500) 0.350:(2.500,1.583) 0.400:(0.000,1.667) 0.500:(0.000,1.833) 0.600:(0.000,2.000) 0.800:(0.000,2.000) 1.000:(0.000,2.000) 1.500:(0.000,2.000)
//     K7 one track of two, initial (3,7): duration=0.200 0.000:(3.000,7.000) 0.100:(6.500,7.000) 0.200:(10.000,7.000) 0.500:(10.000,7.000)
//     K8 a zero-duration keyframe: duration=0.000 0.000:nan 0.100:4.000
//     K9 value(progress:) 0, 0.5, 1, 1.5: ["0.000", "5.000", "10.000", "10.000"]
//   --- K: keyframeAnimator in a window (content value log; keyframes get the start)
//     K10 appear, no trigger change: content 0.000
//     K11 trigger 1, after 0.6 s: first=keyframes(start: 0.000) last=c 20.000
//     K12 first two entries: ["keyframes(start: 0.000)", "c 0.000"]
//     K12 trigger 2 (keyframes receive the previous end, 20): first=keyframes(start: 0.000) last=c 20.000 max=20.000
//     K13 two triggers 0.05 s apart (rounded to whole points; the instant varies): keyframes calls' starts ["0", "5"] last value 25 max 25
//     K14 repeating: keyframes calls ["keyframes(start: 0.000)"] max(rounded)=20
//   --- G: gradients (ImageRenderer, scale 1)
//     G1 red→blue top→bottom 10x101, x5: y0=(254, 9, 8) y1=(251, 19, 21) y25=(197, 74, 109) y50=(141, 82, 162) y75=(82, 72, 209) y99=(9, 13, 254) y100=(2, 5, 254)
//     G2 black→white leading→trailing 101 wide, y2: x0=0 x10=4 x25=34 x50=99 x75=172 x90=220 x100=253
//     G3 black→white topLeading→bottomTrailing 200x100: (100,0)=(73,73,72) (0,50)=(3,3,4) (199,0)=(190,189,189) (0,99)=(23,22,22) (100,50)=(100,100,100) (199,99)=(254,254,253)
//     G4 stops red@0.2 blue@0.8, 101 wide: x0=(255, 0, 0) x10=(255, 0, 0) x20=(253, 8, 9) x35=(198, 73, 110) x50=(140, 83, 162) x65=(81, 72, 209) x80=(2, 4, 254) x90=(0, 0, 255) x100=(0, 0, 255)
//     G4b same stops given in reverse order: x0=(255, 0, 0) x20=(253, 8, 9) x50=(139, 83, 163) x80=(2, 4, 254) x100=(0, 0, 255)
//     G4c two stops at 0.5 (hard edge): x48=(255, 0, 0) x49=(255, 0, 0) x50=(254, 0, 0) x51=(0, 0, 255) x52=(0, 0, 255)
//     G5 clear-red→blue over white (premultiplied or straight?): x0=(254, 254, 255) x25=(190, 191, 255) x50=(127, 128, 255) x75=(66, 62, 255) x100=(1, 1, 255)
//     G6 startPoint == endPoint: (2,10)=(0,0,255) (17,10)=(0,0,255)
//     G7 start 0.25 end 0.75 (pad beyond?): x0=(255, 0, 0) x20=(255, 0, 0) x25=(253, 8, 8) x50=(140, 83, 162) x75=(1, 6, 255) x80=(0, 0, 255) x100=(0, 0, 255)
//     G8 Circle gradient: (20,1)=(0,1,0) (20,20)=(103,103,103) (20,38)=(243,243,242) corner (1,1)=(255,255,255)
//     G9 .background(LinearGradient) on a 60x20 frame, y10: x0=0 x15=35 x30=101 x45=177 x59=252
//     G10 LinearGradient as a view (greedy?) in 300x120: own 300x120 fitting 10x10
//     R1 RadialGradient black→white r0..50 in 101x101, row y50: x0=255 x10=189 x25=100 x40=22 x50=0 x60=21 x75=99 x90=189 x100=255 diag (15,15)=(252,252,252)
//     R2 the same in 201x101 (circular or elliptical?): (100,25)=(100,98,99) (75,50)=(99,98,99) (50,50)=(255,254,255)
//     G11 red→blue midpoint x50: (140, 83, 162) (sRGB-space mix (128,0,128); linear-light mix (188,0,188))
//   --- B: .blur(radius:)
//     B1 black 40x40 at (30,30) blur 4, row y50: 20:253 21:251 22:248 23:242 24:234 25:222 26:207 27:188 28:165 29:140 30:115 31:90 32:67 33:48 34:32 35:21 36:13 37:7 38:4 39:2 40:1 41:0 42:0 43:0 44:0
//     B1b blur 10, row y50: 6:255 8:255 10:252 12:249 14:243 16:237 18:228 20:217 22:203 24:187 26:169 28:148 30:126 32:105 34:85 36:68 38:52 40:39 42:29 44:21 46:14 48:10 50:9 52:11 54:16 56:23
//     B2 blue over red, blurred together, row y50: 26:(207, 168, 216) 28:(165, 107, 197) 30:(115, 52, 192) 32:(67, 18, 206) 34:(32, 4, 227) 50:(0, 0, 255)
//     B2c control: each square blurred alone, row y50: 26:(207, 168, 216) 28:(165, 107, 197) 30:(115, 52, 192) 32:(67, 18, 206) 34:(32, 4, 227) 50:(0, 0, 255)
//     B3 opaque: true, row y50: 26:255 28:255 30:0 32:0 34:0 50:0
//     B4 Text("Go").frame(width: 50, height: 20).blur(radius: 6) (layout unchanged?): own 50x20 fitting 50x20
//     B5 .clipped() after the blur, row y50: 26:255 28:255 30:115 32:67 34:32
//   --- M: materials over red/blue stripes (10 pt), sampled at a red and a blue stripe
//     M1 ImageRenderer light ultraThin: red stripe (213, 73, 119) blue stripe (206, 75, 127) stripe edge (210, 75, 123) outside (255, 0, 0)
//     M1 ImageRenderer light thin: red stripe (221, 102, 142) blue stripe (215, 104, 149) stripe edge (218, 104, 144) outside (255, 0, 0)
//     M1 ImageRenderer light regular: red stripe (227, 134, 164) blue stripe (223, 136, 170) stripe edge (225, 136, 166) outside (255, 0, 0)
//     M1 ImageRenderer light thick: red stripe (234, 165, 189) blue stripe (231, 165, 192) stripe edge (232, 166, 190) outside (255, 0, 0)
//     M1 ImageRenderer light ultraThick: red stripe (231, 199, 213) blue stripe (231, 199, 215) stripe edge (231, 200, 213) outside (255, 0, 0)
//     M1 ImageRenderer light bar: red stripe (242, 204, 217) blue stripe (240, 204, 219) stripe edge (241, 204, 218) outside (255, 0, 0)
//     M1 ImageRenderer dark ultraThin: red stripe (182, 29, 70) blue stripe (172, 29, 80) stripe edge (177, 29, 74) outside (255, 0, 0)
//     M1 ImageRenderer dark thin: red stripe (174, 32, 68) blue stripe (165, 32, 77) stripe edge (169, 32, 72) outside (255, 0, 0)
//     M1 ImageRenderer dark regular: red stripe (159, 36, 64) blue stripe (150, 36, 72) stripe edge (155, 36, 68) outside (255, 0, 0)
//     M1 ImageRenderer dark thick: red stripe (138, 40, 61) blue stripe (130, 40, 68) stripe edge (134, 40, 64) outside (255, 0, 0)
//     M1 ImageRenderer dark ultraThick: red stripe (114, 44, 57) blue stripe (109, 44, 62) stripe edge (111, 44, 59) outside (255, 0, 0)
//     M1 ImageRenderer dark bar: red stripe (72, 37, 49) blue stripe (71, 37, 51) stripe edge (71, 37, 50) outside (255, 0, 0)
//     M5 light ultraThin over uniform white (246, 246, 246) black (111, 111, 110) grey128 (180, 180, 179)
//     M5 light thin over uniform white (242, 242, 242) black (139, 139, 139) grey128 (194, 194, 193)
//     M5 light regular over uniform white (239, 239, 239) black (166, 166, 166) grey128 (206, 206, 206)
//     M5 light thick over uniform white (235, 235, 235) black (191, 191, 190) grey128 (218, 218, 218)
//     M5 light ultraThick over uniform white (231, 231, 231) black (215, 215, 215) grey128 (230, 230, 229)
//     M5 light bar over uniform white (255, 255, 255) black (204, 204, 204) grey128 (230, 230, 230)
//     M5 dark ultraThin over uniform white (155, 155, 155) black (29, 29, 29) grey128 (91, 91, 91)
//     M5 dark thin over uniform white (135, 135, 134) black (32, 32, 32) grey128 (83, 83, 83)
//     M5 dark regular over uniform white (115, 115, 115) black (36, 36, 36) grey128 (74, 74, 74)
//     M5 dark thick over uniform white (96, 96, 96) black (40, 40, 40) grey128 (68, 68, 68)
//     M5 dark ultraThick over uniform white (79, 79, 79) black (44, 44, 44) grey128 (61, 61, 61)
//     M5 dark bar over uniform white (84, 84, 84) black (37, 37, 37) grey128 (61, 61, 61)
//     M2 regular over white (light): (239, 239, 239)
//     M3 .background(.ultraThinMaterial): red stripe (213, 73, 119) blue (206, 75, 127)
//     M4 window cacheDisplay regular light: red stripe (128, 37, 34) blue (28, 28, 127) outside (255, 0, 0); views: FirstMouseHost 100x60

import SwiftUI
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)

// ------------------------------------------------------------------ harness
final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String { defer { lines = [] }; return lines.isEmpty ? "-" : lines.joined(separator: " | ") }
}
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func f3(_ v: Double) -> String { String(format: "%.3f", v) }

nonisolated(unsafe) var windows: [NSWindow] = []
@MainActor func makeWindow<V: View>(_ v: V, w: CGFloat = 300, h: CGFloat = 120) -> (NSWindow, NSView) {
    let win = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: w, height: h), styleMask: [.titled],
                        backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    let host = FirstMouseHost(rootView: v)
    win.contentView = host
    win.makeKeyAndOrderFront(nil)
    host.layoutSubtreeIfNeeded()
    spin(0.5)
    windows.append(win)
    return (win, host)
}
@MainActor func mouseEvent(_ win: NSWindow, _ t: NSEvent.EventType, _ pt: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                       windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                       pressure: t == .leftMouseUp ? 0 : 1)!
}
/// Press at `from`, drag through `through`, release at the last point —
/// each event sent with `NSWindow.sendEvent` and a run-loop spin between
/// (the input-APIs probe's instrument; no SwiftUI control here runs an
/// AppKit tracking loop — S6 prints the backing views).
@MainActor func press(_ win: NSWindow, host: NSView, from: CGPoint, through: [CGPoint]) {
    func w(_ p: CGPoint) -> CGPoint { host.convert(CGPoint(x: p.x, y: host.bounds.height - p.y), to: nil) }
    win.sendEvent(mouseEvent(win, .leftMouseDown, w(from))); spin(0.08)
    for p in through { win.sendEvent(mouseEvent(win, .leftMouseDragged, w(p))); spin(0.08) }
    win.sendEvent(mouseEvent(win, .leftMouseUp, w(through.last ?? from))); spin(0.3)
}
/// A plain `NSHostingView` window for the AX arms (the controls probe's
/// `host`, whose trees read).
@MainActor func plainWindow<V: View>(_ v: V) -> NSView {
    let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 120), styleMask: [.titled],
                       backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    win.contentView = h
    win.orderFrontRegardless()
    win.makeKey()
    h.layoutSubtreeIfNeeded()
    spin(0.4)
    windows.append(win)
    return h
}

// AX walk (the controls probe's).
func kv(_ o: NSObject, _ key: String) -> Any? {
    if o.responds(to: Selector(key)) { return o.value(forKey: key) }
    let names: [String: String] = ["accessibilityRole": "AXRole", "accessibilityLabel": "AXDescription",
                                   "accessibilityValue": "AXValue", "accessibilityChildren": "AXChildren",
                                   "accessibilityMinValue": "AXMinValue", "accessibilityMaxValue": "AXMaxValue"]
    if let name = names[key], o.responds(to: #selector(NSObject.accessibilityAttributeValue(_:))) {
        return o.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: name))
    }
    return nil
}
@MainActor func kids(_ o: NSObject) -> [NSObject] {
    ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject }
}
@MainActor func axLine(_ o: NSObject) -> String {
    func s(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
    return "role=\(s(kv(o, "accessibilityRole"))) label=\(s(kv(o, "accessibilityLabel"))) value=\(s(kv(o, "accessibilityValue"))) min=\(s(kv(o, "accessibilityMinValue"))) max=\(s(kv(o, "accessibilityMaxValue")))"
}
@MainActor func axDump(_ o: NSObject, depth: Int = 0, into out: inout [String]) {
    if depth > 0 { out.append(String(repeating: ".", count: depth) + axLine(o)) }
    if depth < 4 { for k in kids(o) { axDump(k, depth: depth + 1, into: &out) } }
}
@MainActor func find(_ o: NSObject, role: String) -> NSObject? {
    if "\(kv(o, "accessibilityRole") ?? "")" == role { return o }
    for k in kids(o) { if let f = find(k, role: role) { return f } }
    return nil
}
@MainActor func perform(_ e: NSObject, _ sel: String) -> Bool {
    guard e.responds(to: Selector(sel)) else { return false }
    typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(e.method(for: Selector(sel)), to: Fn.self)(e, Selector(sel))
}
/// The backing view tree: class names and running layer animations.
@MainActor func viewTree(_ v: NSView, depth: Int = 0, into out: inout [String]) {
    var keys: [String] = []
    func walk(_ l: CALayer) { keys += (l.animationKeys() ?? []); for s in l.sublayers ?? [] { walk(s) } }
    if let l = v.layer { walk(l) }
    let name = "\(type(of: v))".components(separatedBy: "<").first!
    var extra = ""
    if let p = v as? NSProgressIndicator {
        extra = " NSProgressIndicator style=\(p.style.rawValue) indeterminate=\(p.isIndeterminate) value=\(p.doubleValue) min=\(p.minValue) max=\(p.maxValue) controlSize=\(p.controlSize.rawValue)"
    }
    out.append(String(repeating: ".", count: depth) + name + " \(Int(v.frame.width))x\(Int(v.frame.height))" + extra + (keys.isEmpty ? "" : " anims=\(keys.sorted())"))
    if depth < 6 { for s in v.subviews { viewTree(s, depth: depth + 1, into: &out) } }
}

struct Measured<C: View>: View {
    let content: C
    var body: some View {
        content.onGeometryChange(for: CGSize.self) { $0.size } action: { s in
            Log.add("own \(Int(s.width))x\(Int(s.height))")
        }
    }
}
@MainActor func size<V: View>(_ label: String, _ v: V, w: CGFloat = 300, h: CGFloat = 120) {
    _ = Log.take()
    let (_, host) = makeWindow(Measured(content: v), w: w, h: h)
    print("  \(label): \(Log.take()) fitting \(Int(host.fittingSize.width))x\(Int(host.fittingSize.height))")
}

// Pixels (the paths probe's instrument).
typealias Bitmap = (bytes: [UInt8], w: Int, h: Int)
func bytes(of cg: CGImage) -> Bitmap {
    let w = cg.width, h = cg.height
    var b = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (b, w, h)
}
@MainActor func render(_ v: some View, w: Int, h: Int, scheme: ColorScheme = .light) -> Bitmap {
    let c = ZStack(alignment: .topLeading) { Color.white; v }
        .frame(width: CGFloat(w), height: CGFloat(h), alignment: .topLeading)
        .environment(\.colorScheme, scheme)
    let r = ImageRenderer(content: c)
    r.scale = 1
    return bytes(of: r.cgImage!)
}
func rgb(_ b: Bitmap, _ x: Int, _ y: Int) -> (Int, Int, Int) {
    guard x >= 0, y >= 0, x < b.w, y < b.h else { return (-1, -1, -1) }
    let i = (y * b.w + x) * 4
    return (Int(b.bytes[i]), Int(b.bytes[i + 1]), Int(b.bytes[i + 2]))
}
func px(_ b: Bitmap, _ x: Int, _ y: Int) -> String { let c = rgb(b, x, y); return "(\(x),\(y))=(\(c.0),\(c.1),\(c.2))" }

extension Color {
    static let pr = Color(.sRGB, red: 1, green: 0, blue: 0)
    static let pb = Color(.sRGB, red: 0, green: 0, blue: 1)
    static let pk = Color(.sRGB, red: 0, green: 0, blue: 0)
    static let pw = Color(.sRGB, red: 1, green: 1, blue: 1)
}

final class Model: ObservableObject {
    @Published var v = 0.5
    @Published var color = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
    @Published var trigger = 0
}

// ------------------------------------------------------------------ reduce motion swizzle
nonisolated(unsafe) var forceReduceMotion = false
final class RMSwizzle: NSObject { @objc dynamic var fakeReduceMotion: Bool { forceReduceMotion } }
func installReduceMotionSwizzle() {
    let orig = class_getInstanceMethod(NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion))!
    let repl = class_getInstanceMethod(RMSwizzle.self, #selector(getter: RMSwizzle.fakeReduceMotion))!
    method_setImplementation(orig, method_getImplementation(repl))
}

// ------------------------------------------------------------------ S: slider
struct SliderHost: View {
    @ObservedObject var m: Model
    var disabled = false
    var body: some View {
        Slider(value: Binding(get: { m.v }, set: { Log.add("set \(f3($0))"); m.v = $0 }), in: 0...1) { editing in
            Log.add("editing \(editing)")
        }
        .disabled(disabled)
        .frame(width: 200)
        .frame(width: 300, height: 120)
    }
}

// ------------------------------------------------------------------ C: color picker
struct PickerHost: View {
    @ObservedObject var m: Model
    var opacity = true
    var body: some View {
        ColorPicker("Tint", selection: Binding(get: { m.color }, set: { c in
            let ns = NSColor(c)
            let comps = (0..<ns.numberOfComponents).map { i -> String in
                var a = [CGFloat](repeating: 0, count: ns.numberOfComponents); ns.getComponents(&a); return f3(Double(a[i]))
            }
            let r = c.resolve(in: EnvironmentValues())
            Log.add("set desc=\(c.description) ns=\(ns.colorSpace.localizedName ?? "?") comps=\(comps) resolved=(\(f3(Double(r.red))),\(f3(Double(r.green))),\(f3(Double(r.blue))),\(f3(Double(r.opacity))))")
            m.color = c
        }), supportsOpacity: opacity)
        .frame(width: 300, height: 120)
    }
}

// ------------------------------------------------------------------ K: keyframes
struct Shake: Equatable { var x = 0.0; var s = 1.0 }
func note(_ start: Double) -> Double { Log.add("keyframes(start: \(f3(start)))"); return 10 }
struct KeyHost: View {
    @ObservedObject var m: Model
    var body: some View {
        Color.gray.frame(width: 20, height: 20)
            .keyframeAnimator(initialValue: 0.0, trigger: m.trigger) { content, value in
                content.onAppear { Log.add("content \(f3(value))") }.offset(x: value)
                    .onChange(of: value) { _, n in Log.add("c \(f3(n))") }
            } keyframes: { start in
                KeyframeTrack {
                    LinearKeyframe(note(start), duration: 0.1)
                    LinearKeyframe(start + 20, duration: 0.1)
                }
            }
            .frame(width: 300, height: 120)
    }
}

@MainActor func run() {
    // ---------------------------------------------------------------- P
    print("--- P: positive controls")
    do {
        let (w, h) = makeWindow(Color.gray.onTapGesture { Log.add("tap") }.frame(width: 300, height: 120))
        press(w, host: h, from: CGPoint(x: 150, y: 60), through: [])
        print("  P0 onTapGesture click: \(Log.take())")
        let b = render(Color.pr.frame(width: 20, height: 20).padding(10), w: 40, h: 40)
        print("  P1 red square: \(px(b, 20, 20)) \(px(b, 5, 5))")
        size("P2 Text(\"Go\").frame(width: 50, height: 20)", Text("Go").frame(width: 50, height: 20))
    }

    // ---------------------------------------------------------------- S
    print("--- S: Slider(value:in:onEditingChanged:) in a 200-wide frame centred in 300x120")
    do {
        let m = Model()
        let (w, h) = makeWindow(SliderHost(m: m))
        _ = Log.take()
        press(w, host: h, from: CGPoint(x: 100, y: 60), through: [CGPoint(x: 120, y: 60), CGPoint(x: 140, y: 60)])
        print("  S1 press x100, drag x120, x140, release x140: \(Log.take())")
        press(w, host: h, from: CGPoint(x: 220, y: 60), through: [])
        print("  S2 press and release at x220, no drag: \(Log.take())")
        press(w, host: h, from: CGPoint(x: 150, y: 60), through: [CGPoint(x: 150, y: 60)])
        print("  S3 press x150, a drag that does not move, release: \(Log.take())")
        let ph = plainWindow(SliderHost(m: m))
        var sax: [String] = []; axDump(ph, into: &sax)
        print("  S4 ax: \(sax.joined(separator: " / "))")
        _ = Log.take()
        if let s = find(ph, role: "AXSlider") {
            _ = perform(s, "accessibilityPerformIncrement"); spin()
            print("  S4 AX increment: \(Log.take())")
            _ = perform(s, "accessibilityPerformDecrement"); spin()
            print("  S4 AX decrement: \(Log.take())")
        } else { print("  S4 no AXSlider") }
        m.v = 0.25; spin()
        print("  S5 a model write from outside: \(Log.take())")
        var tree: [String] = []; viewTree(h, into: &tree)
        print("  S6 backing views: " + tree.joined(separator: " / "))
        let md = Model()
        let (w2, h2) = makeWindow(SliderHost(m: md, disabled: true))
        _ = Log.take()
        press(w2, host: h2, from: CGPoint(x: 100, y: 60), through: [CGPoint(x: 140, y: 60)])
        print("  S7 disabled slider press/drag/release: \(Log.take())")
    }

    // ---------------------------------------------------------------- V
    print("--- V: ProgressView sizes (own; fitting)")
    size("V0 ProgressView()", ProgressView())
    size("V0 ProgressView().controlSize(.small)", ProgressView().controlSize(.small))
    size("V0 ProgressView().controlSize(.mini)", ProgressView().controlSize(.mini))
    size("V0 ProgressView().controlSize(.large)", ProgressView().controlSize(.large))
    size("V1 ProgressView(\"Loading\")", ProgressView("Loading"))
    size("V2 ProgressView().progressViewStyle(.linear)", ProgressView().progressViewStyle(.linear))
    size("V3 ProgressView(value: 0.3)", ProgressView(value: 0.3))
    size("V3 ProgressView(value: 0.3) in 300x120 .frame(width: 100)", ProgressView(value: 0.3).frame(width: 100))
    size("V3 ProgressView(value: 0.3).controlSize(.small)", ProgressView(value: 0.3).controlSize(.small))
    size("V4 ProgressView(\"Loading\", value: 0.3)", ProgressView("Loading", value: 0.3))
    size("V4 ProgressView(value: 0.3) { Text(\"L\") } currentValueLabel: { Text(\"30%\") }",
         ProgressView(value: 0.3) { Text("L") } currentValueLabel: { Text("30%") })
    size("V5 ProgressView(value: 0.3).progressViewStyle(.circular)", ProgressView(value: 0.3).progressViewStyle(.circular))
    size("V6 ProgressView(value: nil as Double?)", ProgressView(value: nil as Double?))
    print("--- V: ProgressView AX and backing views")
    func vArm(_ label: String, _ v: some View) {
        let (_, h) = makeWindow(v)
        var ax: [String] = []; axDump(plainWindow(v), into: &ax)
        var tree: [String] = []; viewTree(h, into: &tree)
        print("  \(label): ax: \(ax.joined(separator: " / "))")
        print("    views: \(tree.joined(separator: " / "))")
    }
    vArm("V7 ProgressView()", ProgressView())
    vArm("V7 ProgressView(value: 0.3)", ProgressView(value: 0.3))
    vArm("V7 ProgressView(\"Loading\", value: 0.3)", ProgressView("Loading", value: 0.3))
    vArm("V8 ProgressView(value: 1.5, total: 1)", ProgressView(value: 1.5, total: 1))
    vArm("V8 ProgressView(value: -1, total: 1)", ProgressView(value: -1, total: 1))
    vArm("V8 ProgressView(value: 5, total: 10)", ProgressView(value: 5, total: 10))
    vArm("V8 ProgressView(value: 0, total: 0)", ProgressView(value: 0, total: 0))
    let det = render(ProgressView(value: 0.3).frame(width: 100).padding(10), w: 120, h: 40)
    print("  V9 ImageRenderer determinate bar x10..109: row y=20: " + stride(from: 8, through: 112, by: 8).map { "\($0):\(rgb(det, $0, 20))" }.joined(separator: " "))
    print("  V9 column x=20: " + (10...30).map { "\($0):\(rgb(det, 20, $0).0)" }.joined(separator: " "))
    size("V12 Text(\"Loading\")", Text("Loading"))
    size("V12 Text(\"L\")", Text("L"))
    size("V12 Text(\"30%\")", Text("30%"))
    size("V12 Text(\"Tint\")", Text("Tint"))
    size("V12 ColorPicker(\"A much longer title\", selection:)", ColorPicker("A much longer title", selection: .constant(Color.red)))
    size("V12 Text(\"A much longer title\")", Text("A much longer title"))
    do {
        let (_, h) = makeWindow(ProgressView())
        func walk(_ l: CALayer) {
            for k in l.animationKeys() ?? [] {
                if let a = l.animation(forKey: k) {
                    var d = "  V13 \(k): \(type(of: a)) duration=\(a.duration) repeatCount=\(a.repeatCount) speed=\(a.speed)"
                    if let p = a as? CAPropertyAnimation { d += " keyPath=\(p.keyPath ?? "-")" }
                    if let k2 = a as? CAKeyframeAnimation { d += " values=\(k2.values?.count ?? 0) calc=\(k2.calculationMode.rawValue)" }
                    if let g = a as? CAAnimationGroup { d += " group=\((g.animations ?? []).map { "\(($0 as? CAPropertyAnimation)?.keyPath ?? "?") \($0.duration)" })" }
                    print(d)
                }
            }
            for sub in l.sublayers ?? [] { walk(sub) }
        }
        var deepest: NSView = h
        while let f = deepest.subviews.first { deepest = f }
        if let l = deepest.layer { walk(l) }
        let (_, hb) = makeWindow(ProgressView(value: 0.3).frame(width: 100).frame(width: 120, height: 40), w: 120, h: 40)
        let rep = hb.bitmapImageRepForCachingDisplay(in: hb.bounds)!
        hb.cacheDisplay(in: hb.bounds, to: rep)
        let b = bytes(of: rep.cgImage!)
        let sc = b.w / 120
        print("  V14 cacheDisplay determinate bar (scale \(sc)), column x=20pt: " + (10...30).map { "\($0):\(rgb(b, 20 * sc, $0 * sc))" }.joined(separator: " "))
        print("  V14 row y=20pt: " + stride(from: 8, through: 112, by: 8).map { "\($0):\(rgb(b, $0 * sc, 20 * sc))" }.joined(separator: " "))
    }
    installReduceMotionSwizzle()
    forceReduceMotion = true
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    spin()
    vArm("V10 ProgressView() with Reduce Motion reading true", ProgressView())
    forceReduceMotion = false
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    spin()
    vArm("V10 control: ProgressView() after the swizzle reads false again", ProgressView())

    // ---------------------------------------------------------------- C
    print("--- C: ColorPicker")
    size("C0 ColorPicker(\"Tint\", selection:)", ColorPicker("Tint", selection: .constant(Color.red)))
    size("C0 ColorPicker(\"Tint\", selection:).labelsHidden()", ColorPicker("Tint", selection: .constant(Color.red)).labelsHidden())
    do {
        let m = Model()
        let (w, h) = makeWindow(PickerHost(m: m))
        var ax: [String] = []; axDump(plainWindow(PickerHost(m: Model())), into: &ax)
        var tree: [String] = []; viewTree(h, into: &tree)
        print("  C1 ax: \(ax.joined(separator: " / "))")
        print("  C1 views: \(tree.joined(separator: " / "))")
        let wells = { () -> [NSColorWell] in
            var out: [NSColorWell] = []
            @MainActor func walk(_ v: NSView) { if let c = v as? NSColorWell { out.append(c) }; v.subviews.forEach(walk) }
            walk(h); return out
        }()
        print("  C2 NSColorWell count=\(wells.count) " + wells.map { "frame=\($0.frame) style=\($0.colorWellStyle.rawValue) supportsAlpha=\($0.supportsAlpha) active=\($0.isActive)" }.joined(separator: ", "))
        print("  C2 panel visible before click: \(NSColorPanel.sharedColorPanelExists ? NSColorPanel.shared.isVisible : false)")
        if let well = wells.first {
            let c = well.convert(CGPoint(x: well.bounds.midX, y: well.bounds.midY), to: h)
            press(w, host: h, from: CGPoint(x: c.x, y: h.bounds.height - c.y), through: [])
            spin(0.5)
            print("  C3 after a click on the well: active=\(well.isActive) panelVisible=\(NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible) showsAlpha=\(NSColorPanel.sharedColorPanelExists ? NSColorPanel.shared.showsAlpha : false) log=\(Log.take())")
            if !well.isActive { well.activate(true); spin() ; print("  C3b well.activate(true): active=\(well.isActive) panelVisible=\(NSColorPanel.shared.isVisible) showsAlpha=\(NSColorPanel.shared.showsAlpha) log=\(Log.take())") }
            NSColorPanel.shared.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
            spin(0.4)
            print("  C4 panel.color = sRGB(0.2,0.4,0.6,0.5): \(Log.take())")
            NSColorPanel.shared.color = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
            spin(0.4)
            print("  C5 panel.color = P3(1,0,0,1): \(Log.take())")
            NSColorPanel.shared.color = NSColor(calibratedWhite: 0.5, alpha: 1)
            spin(0.4)
            print("  C6 panel.color = calibratedWhite 0.5: \(Log.take())")
            m.color = Color(.sRGB, red: 0, green: 1, blue: 0); spin(0.4)
            print("  C7 binding write from outside: well.color=\(well.color) panel=\(NSColorPanel.shared.color) log=\(Log.take())")
            well.deactivate(); NSColorPanel.shared.orderOut(nil); spin()
        }
        let m2 = Model()
        let (w2, h2) = makeWindow(PickerHost(m: m2, opacity: false))
        var wells2: [NSColorWell] = []
        @MainActor func walk2(_ v: NSView) { if let c = v as? NSColorWell { wells2.append(c) }; v.subviews.forEach(walk2) }
        walk2(h2)
        if let well = wells2.first {
            print("  C8 supportsOpacity:false well.supportsAlpha=\(well.supportsAlpha)")
            let c = well.convert(CGPoint(x: well.bounds.midX, y: well.bounds.midY), to: h2)
            press(w2, host: h2, from: CGPoint(x: c.x, y: h2.bounds.height - c.y), through: [])
            if !well.isActive { well.activate(true) }
            spin(0.4)
            print("  C8 panel showsAlpha=\(NSColorPanel.shared.showsAlpha) log=\(Log.take())")
            NSColorPanel.shared.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
            spin(0.4)
            print("  C8 panel.color = sRGB(0.2,0.4,0.6,0.5) with supportsOpacity false: \(Log.take())")
            well.deactivate(); NSColorPanel.shared.orderOut(nil); spin()
        }
    }

    // ---------------------------------------------------------------- K
    print("--- K: KeyframeTimeline values (time: value)")
    func samples<V>(_ t: KeyframeTimeline<V>, _ times: [Double], _ show: (V) -> String) -> String {
        "duration=\(f3(t.duration)) " + times.map { "\(f3($0)):\(show(t.value(time: $0)))" }.joined(separator: " ")
    }
    let times = [-0.1, 0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.6, 0.8, 1.0, 1.5]
    let lin = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(10.0, duration: 0.2); LinearKeyframe(-10.0, duration: 0.2); LinearKeyframe(0.0, duration: 0.2) } }
    print("  K1 Linear 0→10 (0.2) →-10 (0.2) →0 (0.2): " + samples(lin, times) { f3($0) })
    let linE = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(10.0, duration: 0.4, timingCurve: .easeInOut) } }
    print("  K2 Linear 0→10 (0.4, .easeInOut): " + samples(linE, times) { f3($0) })
    let cub = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0.2); CubicKeyframe(-10.0, duration: 0.2); CubicKeyframe(0.0, duration: 0.2) } }
    print("  K3 Cubic 0→10→-10→0 (0.2 each): " + samples(cub, times) { f3($0) })
    let cub1 = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0.4) } }
    print("  K3b Cubic 0→10 (0.4) alone: " + samples(cub1, times) { f3($0) })
    let spr = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { SpringKeyframe(10.0, duration: 0.4, spring: .init(duration: 0.4, bounce: 0)) } }
    print("  K4 Spring 0→10 duration 0.4, Spring(duration 0.4, bounce 0): " + samples(spr, times) { f3($0) })
    let spr2 = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { SpringKeyframe(10.0, spring: .init(duration: 0.4, bounce: 0.3)) } }
    print("  K4b Spring 0→10 no duration, Spring(duration 0.4, bounce 0.3): " + samples(spr2, times) { f3($0) })
    let spr3 = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { SpringKeyframe(10.0, duration: 0.2, spring: .init(duration: 0.4, bounce: 0)); LinearKeyframe(0.0, duration: 0.2) } }
    print("  K4c Spring(0.4 spring, keyframe 0.2) then Linear→0 (0.2): " + samples(spr3, times) { f3($0) })
    let cubU = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0.1); CubicKeyframe(0.0, duration: 0.3) } }
    print("  K3c Cubic 0→10 (0.1) →0 (0.3), unequal: " + samples(cubU, [0.025, 0.05, 0.075, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35]) { f3($0) })
    let cubL = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(10.0, duration: 0.2); CubicKeyframe(0.0, duration: 0.2); LinearKeyframe(5.0, duration: 0.2) } }
    print("  K3d Linear→10, Cubic→0, Linear→5 (0.2 each): " + samples(cubL, [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.5]) { f3($0) })
    let cubV = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0.4, startVelocity: 50, endVelocity: 0) } }
    print("  K3e Cubic 0→10 (0.4) startVelocity 50 endVelocity 0: " + samples(cubV, [0.05, 0.1, 0.2, 0.3, 0.35]) { f3($0) })
    let cub4 = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0.2); CubicKeyframe(30.0, duration: 0.2) } }
    print("  K3f Cubic 0→10→30 (0.2 each, monotone): " + samples(cub4, [0.05, 0.1, 0.15, 0.25, 0.3, 0.35]) { f3($0) })
    let cubG = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0.1); CubicKeyframe(30.0, duration: 0.3) } }
    print("  K3g Cubic 0→10 (0.1) →30 (0.3), unequal, monotone: " + samples(cubG, [0.025, 0.05, 0.075, 0.175, 0.25, 0.325]) { f3($0) })
    let cubH = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0.2); CubicKeyframe(30.0, duration: 0.2); LinearKeyframe(30.0, duration: 0.2) } }
    print("  K3h Cubic 0→10→30, then Linear holding 30: " + samples(cubH, [0.25, 0.3, 0.35]) { f3($0) })
    for (d, b) in [(0.4, 0.0), (0.4, 0.3), (0.4, 0.5), (0.4, -0.3), (1.0, 0.0), (1.0, 0.3), (0.5, 0.15), (0.2, 0.7)] {
        let sp = Spring(duration: d, bounce: b)
        print("  K4d Spring(duration: \(d), bounce: \(b)).settlingDuration = \(String(format: "%.6f", sp.settlingDuration)); value(target 10, t 0.1) = \(f3(sp.value(target: 10.0, time: 0.1)))")
    }
    let sprV = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(10.0, duration: 0.2); SpringKeyframe(0.0, duration: 0.4, spring: .init(duration: 0.4, bounce: 0)) } }
    print("  K4e Linear→10 (0.2) then Spring→0: does the spring start with the linear's velocity (50/s)? " + samples(sprV, [0.2, 0.25, 0.3, 0.4, 0.6]) { f3($0) })
    let mov = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(10.0, duration: 0.2); MoveKeyframe(-5.0); LinearKeyframe(0.0, duration: 0.2) } }
    print("  K5 Linear→10 (0.2), Move -5, Linear→0 (0.2): " + samples(mov, times) { f3($0) })
    let two = KeyframeTimeline(initialValue: Shake()) {
        KeyframeTrack(\.x) { LinearKeyframe(10.0, duration: 0.2); LinearKeyframe(0.0, duration: 0.2) }
        KeyframeTrack(\.s) { LinearKeyframe(2.0, duration: 0.6) }
    }
    print("  K6 two tracks x (0.4 total), s (0.6): " + samples(two, times) { "(\(f3($0.x)),\(f3($0.s)))" })
    let partial = KeyframeTimeline(initialValue: Shake(x: 3, s: 7)) { KeyframeTrack(\.x) { LinearKeyframe(10.0, duration: 0.2) } }
    print("  K7 one track of two, initial (3,7): " + samples(partial, [0, 0.1, 0.2, 0.5]) { "(\(f3($0.x)),\(f3($0.s)))" })
    let empty = KeyframeTimeline(initialValue: 4.0) { KeyframeTrack { LinearKeyframe(4.0, duration: 0) } }
    print("  K8 a zero-duration keyframe: " + samples(empty, [0, 0.1]) { f3($0) })
    let prog = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(10.0, duration: 0.4) } }
    print("  K9 value(progress:) 0, 0.5, 1, 1.5: \([0, 0.5, 1, 1.5].map { f3(prog.value(progress: $0)) })")
    print("--- K: keyframeAnimator in a window (content value log; keyframes get the start)")
    do {
        let m = Model()
        _ = Log.take()
        _ = makeWindow(KeyHost(m: m))
        spin(0.3)
        print("  K10 appear, no trigger change: \(Log.take())")
        m.trigger += 1; spin(0.6)
        let first = Log.lines
        print("  K11 trigger 1, after 0.6 s: first=\(first.first ?? "-") last=\(first.last ?? "-")")
        _ = Log.take()
        m.trigger += 1; spin(0.6)
        let second = Log.lines
        print("  K12 first two entries: \(second.prefix(2))")
        print("  K12 trigger 2 (keyframes receive the previous end, 20): first=\(second.first ?? "-") last=\(second.last ?? "-") max=\(second.compactMap { Double($0.split(separator: " ").last ?? "") }.max().map(f3) ?? "-")")
        _ = Log.take()
        m.trigger += 1; spin(0.05); m.trigger += 1; spin(0.6)
        let third = Log.lines
        func whole(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "-" }
        let ends = third.compactMap { Double($0.split(separator: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: ")")) ?? "") }
        let starts = third.filter { $0.hasPrefix("keyframes") }.compactMap { Double($0.dropFirst(17).dropLast()) }
        print("  K13 two triggers 0.05 s apart (rounded to whole points; the instant varies): keyframes calls' starts \(starts.map { whole($0) }) last value \(whole(ends.last)) max \(whole(third.filter { $0.hasPrefix("c ") }.compactMap { Double($0.dropFirst(2)) }.max()))")
        _ = Log.take()
    }

    do {
        _ = Log.take()
        struct Rep: View {
            var body: some View {
                Color.gray.frame(width: 20, height: 20)
                    .keyframeAnimator(initialValue: 0.0, repeating: true) { content, value in
                        content.offset(x: value).onChange(of: value) { _, n in Log.add("c \(f3(n))") }
                    } keyframes: { start in
                        KeyframeTrack { LinearKeyframe(note(start), duration: 0.1); LinearKeyframe(start + 20, duration: 0.1) }
                    }
                    .frame(width: 300, height: 120)
            }
        }
        _ = makeWindow(Rep())
        spin(0.5)
        let r = Log.lines
        print("  K14 repeating: keyframes calls \(r.filter { $0.hasPrefix("keyframes") }.prefix(6)) max(rounded)=\(r.filter { $0.hasPrefix("c ") }.compactMap { Double($0.dropFirst(2)) }.max().map { String(format: "%.0f", $0) } ?? "-")")
        // Tear the looping animator down so it logs nothing into later arms.
        windows.last?.contentView = nil; windows.last?.orderOut(nil); spin(0.1)
        _ = Log.take()
    }

    // ---------------------------------------------------------------- G
    print("--- G: gradients (ImageRenderer, scale 1)")
    let g1 = render(Rectangle().fill(LinearGradient(colors: [.pr, .pb], startPoint: .top, endPoint: .bottom)).frame(width: 10, height: 101), w: 10, h: 101)
    print("  G1 red→blue top→bottom 10x101, x5: " + [0, 1, 25, 50, 75, 99, 100].map { "y\($0)=\(rgb(g1, 5, $0))" }.joined(separator: " "))
    let g2 = render(Rectangle().fill(LinearGradient(colors: [.pk, .pw], startPoint: .leading, endPoint: .trailing)).frame(width: 101, height: 4), w: 101, h: 4)
    print("  G2 black→white leading→trailing 101 wide, y2: " + [0, 10, 25, 50, 75, 90, 100].map { "x\($0)=\(rgb(g2, $0, 2).0)" }.joined(separator: " "))
    let g3 = render(Rectangle().fill(LinearGradient(colors: [.pk, .pw], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 200, height: 100), w: 200, h: 100)
    print("  G3 black→white topLeading→bottomTrailing 200x100: \(px(g3, 100, 0)) \(px(g3, 0, 50)) \(px(g3, 199, 0)) \(px(g3, 0, 99)) \(px(g3, 100, 50)) \(px(g3, 199, 99))")
    let g4 = render(Rectangle().fill(LinearGradient(stops: [.init(color: .pr, location: 0.2), .init(color: .pb, location: 0.8)], startPoint: .leading, endPoint: .trailing)).frame(width: 101, height: 4), w: 101, h: 4)
    print("  G4 stops red@0.2 blue@0.8, 101 wide: " + [0, 10, 20, 35, 50, 65, 80, 90, 100].map { "x\($0)=\(rgb(g4, $0, 2))" }.joined(separator: " "))
    let g4b = render(Rectangle().fill(LinearGradient(stops: [.init(color: .pb, location: 0.8), .init(color: .pr, location: 0.2)], startPoint: .leading, endPoint: .trailing)).frame(width: 101, height: 4), w: 101, h: 4)
    print("  G4b same stops given in reverse order: " + [0, 20, 50, 80, 100].map { "x\($0)=\(rgb(g4b, $0, 2))" }.joined(separator: " "))
    let g4c = render(Rectangle().fill(LinearGradient(stops: [.init(color: .pr, location: 0.5), .init(color: .pb, location: 0.5)], startPoint: .leading, endPoint: .trailing)).frame(width: 101, height: 4), w: 101, h: 4)
    print("  G4c two stops at 0.5 (hard edge): " + [48, 49, 50, 51, 52].map { "x\($0)=\(rgb(g4c, $0, 2))" }.joined(separator: " "))
    let g5 = render(Rectangle().fill(LinearGradient(colors: [Color.pr.opacity(0), .pb], startPoint: .leading, endPoint: .trailing)).frame(width: 101, height: 4), w: 101, h: 4)
    print("  G5 clear-red→blue over white (premultiplied or straight?): " + [0, 25, 50, 75, 100].map { "x\($0)=\(rgb(g5, $0, 2))" }.joined(separator: " "))
    let g6 = render(Rectangle().fill(LinearGradient(colors: [.pr, .pb], startPoint: .center, endPoint: .center)).frame(width: 20, height: 20), w: 20, h: 20)
    print("  G6 startPoint == endPoint: \(px(g6, 2, 10)) \(px(g6, 17, 10))")
    let g7 = render(Rectangle().fill(LinearGradient(colors: [.pr, .pb], startPoint: UnitPoint(x: 0.25, y: 0.5), endPoint: UnitPoint(x: 0.75, y: 0.5))).frame(width: 101, height: 4), w: 101, h: 4)
    print("  G7 start 0.25 end 0.75 (pad beyond?): " + [0, 20, 25, 50, 75, 80, 100].map { "x\($0)=\(rgb(g7, $0, 2))" }.joined(separator: " "))
    let g8 = render(Circle().fill(LinearGradient(colors: [.pk, .pw], startPoint: .top, endPoint: .bottom)).frame(width: 40, height: 40), w: 40, h: 40)
    print("  G8 Circle gradient: \(px(g8, 20, 1)) \(px(g8, 20, 20)) \(px(g8, 20, 38)) corner \(px(g8, 1, 1))")
    let g9 = render(Text("    ").frame(width: 60, height: 20).background(LinearGradient(colors: [.pk, .pw], startPoint: .leading, endPoint: .trailing)), w: 60, h: 20)
    print("  G9 .background(LinearGradient) on a 60x20 frame, y10: " + [0, 15, 30, 45, 59].map { "x\($0)=\(rgb(g9, $0, 10).0)" }.joined(separator: " "))
    size("G10 LinearGradient as a view (greedy?) in 300x120", LinearGradient(colors: [.pk, .pw], startPoint: .top, endPoint: .bottom))
    let r1 = render(Rectangle().fill(RadialGradient(colors: [.pk, .pw], center: .center, startRadius: 0, endRadius: 50)).frame(width: 101, height: 101), w: 101, h: 101)
    print("  R1 RadialGradient black→white r0..50 in 101x101, row y50: " + [0, 10, 25, 40, 50, 60, 75, 90, 100].map { "x\($0)=\(rgb(r1, $0, 50).0)" }.joined(separator: " ") + " diag \(px(r1, 15, 15))")
    let r2 = render(Rectangle().fill(RadialGradient(colors: [.pk, .pw], center: .center, startRadius: 0, endRadius: 50)).frame(width: 201, height: 101), w: 201, h: 101)
    print("  R2 the same in 201x101 (circular or elliptical?): \(px(r2, 100, 25)) \(px(r2, 75, 50)) \(px(r2, 50, 50))")
    let w1 = render(Rectangle().fill(LinearGradient(colors: [.pr, .pb], startPoint: .leading, endPoint: .trailing)).frame(width: 101, height: 4), w: 101, h: 4)
    print("  G11 red→blue midpoint x50: \(rgb(w1, 50, 2)) (sRGB-space mix (128,0,128); linear-light mix (188,0,188))")

    // ---------------------------------------------------------------- B
    print("--- B: .blur(radius:)")
    let b1 = render(Color.pk.frame(width: 40, height: 40).blur(radius: 4).padding(30), w: 100, h: 100)
    print("  B1 black 40x40 at (30,30) blur 4, row y50: " + (20...44).map { "\($0):\(rgb(b1, $0, 50).0)" }.joined(separator: " "))
    let b1b = render(Color.pk.frame(width: 40, height: 40).blur(radius: 10).padding(30), w: 100, h: 100)
    print("  B1b blur 10, row y50: " + stride(from: 6, through: 56, by: 2).map { "\($0):\(rgb(b1b, $0, 50).0)" }.joined(separator: " "))
    let b2 = render(ZStack { Color.pr.frame(width: 40, height: 40); Color.pb.frame(width: 40, height: 40) }.blur(radius: 4).padding(30), w: 100, h: 100)
    print("  B2 blue over red, blurred together, row y50: " + [26, 28, 30, 32, 34, 50].map { "\($0):\(rgb(b2, $0, 50))" }.joined(separator: " "))
    let b2c = render(ZStack { Color.pr.frame(width: 40, height: 40).blur(radius: 4); Color.pb.frame(width: 40, height: 40).blur(radius: 4) }.padding(30), w: 100, h: 100)
    print("  B2c control: each square blurred alone, row y50: " + [26, 28, 30, 32, 34, 50].map { "\($0):\(rgb(b2c, $0, 50))" }.joined(separator: " "))
    let b3 = render(Color.pk.frame(width: 40, height: 40).blur(radius: 4, opaque: true).padding(30), w: 100, h: 100)
    print("  B3 opaque: true, row y50: " + [26, 28, 30, 32, 34, 50].map { "\($0):\(rgb(b3, $0, 50).0)" }.joined(separator: " "))
    size("B4 Text(\"Go\").frame(width: 50, height: 20).blur(radius: 6) (layout unchanged?)", Text("Go").frame(width: 50, height: 20).blur(radius: 6))
    let b5 = render(Color.pk.frame(width: 40, height: 40).blur(radius: 4).clipped().padding(30), w: 100, h: 100)
    print("  B5 .clipped() after the blur, row y50: " + [26, 28, 30, 32, 34].map { "\($0):\(rgb(b5, $0, 50).0)" }.joined(separator: " "))

    // ---------------------------------------------------------------- M
    print("--- M: materials over red/blue stripes (10 pt), sampled at a red and a blue stripe")
    func stripes() -> some View { HStack(spacing: 0) { ForEach(0..<10) { i in (i % 2 == 0 ? Color.pr : Color.pb).frame(width: 10, height: 60) } } }
    let mats: [(String, Material)] = [("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial), ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial), ("bar", .bar)]
    for scheme in [ColorScheme.light, .dark] {
        for (name, mat) in mats {
            let v = ZStack { stripes(); Rectangle().fill(mat).frame(width: 100, height: 40) }
            let b = render(v, w: 100, h: 60, scheme: scheme)
            print("  M1 ImageRenderer \(scheme) \(name): red stripe \(rgb(b, 5, 30)) blue stripe \(rgb(b, 15, 30)) stripe edge \(rgb(b, 10, 30)) outside \(rgb(b, 5, 5))")
        }
    }
    for scheme in [ColorScheme.light, .dark] {
        for (name, mat) in mats {
            let wv = render(Rectangle().fill(mat).frame(width: 100, height: 60), w: 100, h: 60, scheme: scheme)
            let kv = render(ZStack { Color.pk; Rectangle().fill(mat) }.frame(width: 100, height: 60), w: 100, h: 60, scheme: scheme)
            let gv = render(ZStack { Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5); Rectangle().fill(mat) }.frame(width: 100, height: 60), w: 100, h: 60, scheme: scheme)
            print("  M5 \(scheme) \(name) over uniform white \(rgb(wv, 50, 30)) black \(rgb(kv, 50, 30)) grey128 \(rgb(gv, 50, 30))")
        }
    }
    let solid = render(ZStack { Color.pw.frame(width: 100, height: 60); Rectangle().fill(Material.regularMaterial).frame(width: 100, height: 40) }, w: 100, h: 60)
    print("  M2 regular over white (light): \(rgb(solid, 50, 30))")
    let bg = render(ZStack { stripes(); Text("").frame(width: 100, height: 40).background(.ultraThinMaterial) }, w: 100, h: 60)
    print("  M3 .background(.ultraThinMaterial): red stripe \(rgb(bg, 5, 30)) blue \(rgb(bg, 15, 30))")
    do {
        let v = ZStack { stripes(); Rectangle().fill(Material.regularMaterial).frame(width: 100, height: 40) }.frame(width: 100, height: 60)
        let (_, h) = makeWindow(v, w: 100, h: 60)
        let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!
        h.cacheDisplay(in: h.bounds, to: rep)
        let b = bytes(of: rep.cgImage!)
        let s = Double(b.w) / 100
        func at(_ x: Double, _ y: Double) -> (Int, Int, Int) { rgb(b, Int(x * s), Int(y * s)) }
        var tree: [String] = []; viewTree(h, into: &tree)
        print("  M4 window cacheDisplay regular light: red stripe \(at(5, 30)) blue \(at(15, 30)) outside \(at(5, 5)); views: \(tree.joined(separator: " / "))")
    }
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    // Activates SwiftUI's accessibility tree (the accessibility-bridge
    // probe's arm 2: children 0 before, 1 after).
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    run()
}
exit(0)

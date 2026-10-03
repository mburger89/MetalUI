// SwiftUI probe: colour values and colour scheme (user request 2026-10-02,
// gpui-gap item, not a plan task). Evidence for rulings CR-A… in
// docs/superpowers/2026-10-03-colour-decisions.md; spec
// docs/superpowers/specs/2026-10-03-colour-design.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-colour.swift -o /tmp/colour-probe
//   /tmp/colour-probe
//
// Headless: nothing is posted at the HID tap; windows are ordered front but
// never need to be key. Body evaluation is forced by layoutSubtreeIfNeeded and
// short run-loop turns.
//
// THE INSTRUMENTS.
// - R/N/O/S: `Color.resolve(in:)` (macOS 14) against an `EnvironmentValues`
//   whose `colorScheme` is set. Each line prints the resolved value three ways:
//   `Color.Resolved.description` (hex), its `red/green/blue/opacity` fields,
//   and the components of its `cgColor` converted to sRGB. The fields and the
//   cgColor disagree for any mid-tone if the fields are linear light, which is
//   what R1 separates.
// - E/P/V: a hosted view (NSHostingView in an NSWindow) records the
//   `@Environment(\.colorScheme)` its body read, and the window's
//   `appearance`/`effectiveAppearance` names after a layout pass.
// - D: dynamic colours SwiftUI can express: `Color(nsColor:)` over a dynamic
//   `NSColor(name:dynamicProvider:)`, resolved in both schemes.
//
// POSITIVE CONTROLS AND SEPARATING ARMS.
// - R0 (pure red: every encoding reads 1,0,0) against R1 (white 0.5: a gamma
//   reading says 0.5, a linear one 0.214).
// - E0 (bare EnvironmentValues) against E1/E2 (hosted in an aqua / darkAqua
//   window): the host stamps the window's scheme.
// - P0 (no modifier: window.appearance nil) against P1 (preferredColorScheme
//   on a CHILD view: does the window's appearance and a SIBLING's scheme move)
//   and V1 (environment(\.colorScheme) on the same child: only its subtree).
// - D0: a static NSColor in both schemes (must not move) against D1 (dynamic).

// - P6/P7/P8: nil against a non-nil preference, nested and as siblings, and a
//   live preference flipped from .dark to nil.
//
// RECORDED 2026-10-03 by the colour design session, macOS 27.0.1 (26A434),
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED (CGSSessionScreenIsLocked
// = 1, displayAsleep main: 1); the SYSTEM appearance is Dark
// (`defaults read -g AppleInterfaceStyle` = Dark) and the accent colour is
// the default (no AppleAccentColor key). Compiled form, run three times:
// stdout byte-identical (102 lines), exit 0, stderr empty.
//
// READING NOTES (what each ruling may rest on):
// - R1: `Color.Resolved`'s fields equal the cgColor's sRGB components for a
//   mid-tone (0.5, not 0.214): the fields are GAMMA-ENCODED sRGB on this SDK.
//   `Color(red:green:blue:)` and `Color(white:)` author gamma sRGB.
// - R3: `.sRGBLinear` is converted to gamma at once (0.2 -> 0.4845, the sRGB
//   transfer function). R4: `.displayP3` red resolves to EXTENDED sRGB
//   (1.0931, -0.2266, -0.1504); R5/O4/O5: out-of-range components and
//   opacities are kept in the resolved value and clamped only when drawn
//   (cgSRGB column).
// - N: every hue static, `gray` included, is DYNAMIC (a light and a dark
//   value); black, white, clear are fixed. primary/secondary are black/white at
//   0.8471 / 0.4980 (light) and 0.8471 / 0.5490 (dark) alpha; accentColor is
//   the system accent (here blue, equal to `.blue` in both schemes).
// - O2: opacity multiplies (0.8471 * 0.5 = 0.4235); O3: twice multiplies.
// - Q4/Q5: equality compares components (`Color(red:1,green:1,blue:1) ==
//   Color(white: 1) == .white`).
// - E0: a bare EnvironmentValues reads .light; E1/E2/T1: a hosted view reads the
//   window's effective appearance, and an appearance change re-runs the body.
// - P1/P3/P4/P7: `.preferredColorScheme` on a child is WINDOW-WIDE (the sibling
//   reads it too, and the NSWindow's `appearance` is set); among siblings the
//   FIRST non-nil wins (P3 dark-first -> dark, P4 light-first -> light, P7 nil
//   then dark -> dark). P5/P6: an OUTER modifier replaces its content's value,
//   nil included (outer nil over inner dark -> no preference). P8b: a
//   preference going to nil resets `NSWindow.appearance` to nil (the window
//   then follows the system, Dark here, which is why t still reads dark).
//   P1's reads show the body built light FIRST and rebuilt dark.
// - V1: `.environment(\.colorScheme, .dark)` changes only its subtree and not
//   the window's appearance — the separating arm for P1.
// - D1: a dynamic colour is expressible only through AppKit
//   (`NSColor(name:dynamicProvider:)`); `Color(light:dark:)` does NOT exist
//   (`xcrun swiftc -typecheck` of `Color(light: .red, dark: .blue)` against this
//   SDK: "error: extra argument 'dark' in call"), and an asset-catalog
//   `Color("Name", bundle:)` typechecks but needs a compiled catalog.
//
// OUTPUT, verbatim:
//
//   --- R: literal initialisers
//     R0 Color(red:1,green:0,blue:0) [light] desc=#FF0000FF fields=1.0000 0.0000 0.0000 1.0000 cgSRGB=1.0000 0.0000 0.0000 1.0000
//     R0 Color(red:1,green:0,blue:0) [dark] desc=#FF0000FF fields=1.0000 0.0000 0.0000 1.0000 cgSRGB=1.0000 0.0000 0.0000 1.0000
//     R1 Color(white:0.5) [light] desc=#808080FF fields=0.5000 0.5000 0.5000 1.0000 cgSRGB=0.5000 0.5000 0.5000 1.0000
//     R1 Color(white:0.5) [dark] desc=#808080FF fields=0.5000 0.5000 0.5000 1.0000 cgSRGB=0.5000 0.5000 0.5000 1.0000
//     R2 Color(.sRGB,0.2,0.4,0.6,opacity:0.8) [light] desc=#336699CC fields=0.2000 0.4000 0.6000 0.8000 cgSRGB=0.2000 0.4000 0.6000 0.8000
//     R2 Color(.sRGB,0.2,0.4,0.6,opacity:0.8) [dark] desc=#336699CC fields=0.2000 0.4000 0.6000 0.8000 cgSRGB=0.2000 0.4000 0.6000 0.8000
//     R3 Color(.sRGBLinear,0.2,0.4,0.6) [light] desc=#7CAACBFF fields=0.4845 0.6652 0.7977 1.0000 cgSRGB=0.4845 0.6652 0.7977 1.0000
//     R3 Color(.sRGBLinear,0.2,0.4,0.6) [dark] desc=#7CAACBFF fields=0.4845 0.6652 0.7977 1.0000 cgSRGB=0.4845 0.6652 0.7977 1.0000
//     R4 Color(.displayP3,1,0,0) [light] desc=#117FFFFFFC7FFFFFFDBFF fields=1.0931 -0.2266 -0.1504 1.0000 cgSRGB=1.0000 0.0000 0.0000 1.0000
//     R4 Color(.displayP3,1,0,0) [dark] desc=#117FFFFFFC7FFFFFFDBFF fields=1.0931 -0.2266 -0.1504 1.0000 cgSRGB=1.0000 0.0000 0.0000 1.0000
//     R5 Color(red:1.2,green:-0.1,blue:0.5) out of range [light] desc=#132FFFFFFE880FF fields=1.2000 -0.1000 0.5000 1.0000 cgSRGB=1.0000 0.0000 0.5000 1.0000
//     R5 Color(red:1.2,green:-0.1,blue:0.5) out of range [dark] desc=#132FFFFFFE880FF fields=1.2000 -0.1000 0.5000 1.0000 cgSRGB=1.0000 0.0000 0.5000 1.0000
//     R6 Color(hue:0.5,saturation:1,brightness:1) [light] desc=#00FFFFFF fields=0.0000 1.0000 1.0000 1.0000 cgSRGB=0.0000 1.0000 1.0000 1.0000
//     R6 Color(hue:0.5,saturation:1,brightness:1) [dark] desc=#00FFFFFF fields=0.0000 1.0000 1.0000 1.0000 cgSRGB=0.0000 1.0000 1.0000 1.0000
//     R7 Color(white:0.5,opacity:0.25) [light] desc=#80808040 fields=0.5000 0.5000 0.5000 0.2500 cgSRGB=0.5000 0.5000 0.5000 0.2500
//     R7 Color(white:0.5,opacity:0.25) [dark] desc=#80808040 fields=0.5000 0.5000 0.5000 0.2500 cgSRGB=0.5000 0.5000 0.5000 0.2500
//   --- N: named statics
//     N black [light] desc=#000000FF fields=0.0000 0.0000 0.0000 1.0000 cgSRGB=0.0000 0.0000 0.0000 1.0000
//     N black [dark] desc=#000000FF fields=0.0000 0.0000 0.0000 1.0000 cgSRGB=0.0000 0.0000 0.0000 1.0000
//     N white [light] desc=#FFFFFFFF fields=1.0000 1.0000 1.0000 1.0000 cgSRGB=1.0000 1.0000 1.0000 1.0000
//     N white [dark] desc=#FFFFFFFF fields=1.0000 1.0000 1.0000 1.0000 cgSRGB=1.0000 1.0000 1.0000 1.0000
//     N clear [light] desc=#00000000 fields=0.0000 0.0000 0.0000 0.0000 cgSRGB=0.0000 0.0000 0.0000 0.0000
//     N clear [dark] desc=#00000000 fields=0.0000 0.0000 0.0000 0.0000 cgSRGB=0.0000 0.0000 0.0000 0.0000
//     N gray [light] desc=#8E8E93FF fields=0.5569 0.5569 0.5765 1.0000 cgSRGB=0.5569 0.5569 0.5765 1.0000
//     N gray [dark] desc=#98989DFF fields=0.5961 0.5961 0.6157 1.0000 cgSRGB=0.5961 0.5961 0.6157 1.0000
//     N red [light] desc=#FF383CFF fields=1.0000 0.2196 0.2353 1.0000 cgSRGB=1.0000 0.2196 0.2353 1.0000
//     N red [dark] desc=#FF4245FF fields=1.0000 0.2588 0.2706 1.0000 cgSRGB=1.0000 0.2588 0.2706 1.0000
//     N orange [light] desc=#FF8D28FF fields=1.0000 0.5529 0.1569 1.0000 cgSRGB=1.0000 0.5529 0.1569 1.0000
//     N orange [dark] desc=#FF9230FF fields=1.0000 0.5725 0.1882 1.0000 cgSRGB=1.0000 0.5725 0.1882 1.0000
//     N yellow [light] desc=#FFCC00FF fields=1.0000 0.8000 0.0000 1.0000 cgSRGB=1.0000 0.8000 0.0000 1.0000
//     N yellow [dark] desc=#FFD600FF fields=1.0000 0.8392 0.0000 1.0000 cgSRGB=1.0000 0.8392 0.0000 1.0000
//     N green [light] desc=#34C759FF fields=0.2039 0.7804 0.3490 1.0000 cgSRGB=0.2039 0.7804 0.3490 1.0000
//     N green [dark] desc=#30D158FF fields=0.1882 0.8196 0.3451 1.0000 cgSRGB=0.1882 0.8196 0.3451 1.0000
//     N mint [light] desc=#00C8B3FF fields=0.0000 0.7843 0.7020 1.0000 cgSRGB=0.0000 0.7843 0.7020 1.0000
//     N mint [dark] desc=#00DAC3FF fields=0.0000 0.8549 0.7647 1.0000 cgSRGB=0.0000 0.8549 0.7647 1.0000
//     N teal [light] desc=#00C3D0FF fields=0.0000 0.7647 0.8157 1.0000 cgSRGB=0.0000 0.7647 0.8157 1.0000
//     N teal [dark] desc=#00D2E0FF fields=0.0000 0.8235 0.8784 1.0000 cgSRGB=0.0000 0.8235 0.8784 1.0000
//     N cyan [light] desc=#00C0E8FF fields=0.0000 0.7529 0.9098 1.0000 cgSRGB=0.0000 0.7529 0.9098 1.0000
//     N cyan [dark] desc=#3CD3FEFF fields=0.2353 0.8275 0.9961 1.0000 cgSRGB=0.2353 0.8275 0.9961 1.0000
//     N blue [light] desc=#0088FFFF fields=0.0000 0.5333 1.0000 1.0000 cgSRGB=0.0000 0.5333 1.0000 1.0000
//     N blue [dark] desc=#0091FFFF fields=0.0000 0.5686 1.0000 1.0000 cgSRGB=0.0000 0.5686 1.0000 1.0000
//     N indigo [light] desc=#6155F5FF fields=0.3804 0.3333 0.9608 1.0000 cgSRGB=0.3804 0.3333 0.9608 1.0000
//     N indigo [dark] desc=#6D7CFFFF fields=0.4275 0.4863 1.0000 1.0000 cgSRGB=0.4275 0.4863 1.0000 1.0000
//     N purple [light] desc=#CB30E0FF fields=0.7961 0.1882 0.8784 1.0000 cgSRGB=0.7961 0.1882 0.8784 1.0000
//     N purple [dark] desc=#DB34F2FF fields=0.8588 0.2039 0.9490 1.0000 cgSRGB=0.8588 0.2039 0.9490 1.0000
//     N pink [light] desc=#FF2D55FF fields=1.0000 0.1765 0.3333 1.0000 cgSRGB=1.0000 0.1765 0.3333 1.0000
//     N pink [dark] desc=#FF375FFF fields=1.0000 0.2157 0.3725 1.0000 cgSRGB=1.0000 0.2157 0.3725 1.0000
//     N brown [light] desc=#AC7F5EFF fields=0.6745 0.4980 0.3686 1.0000 cgSRGB=0.6745 0.4980 0.3686 1.0000
//     N brown [dark] desc=#B78A66FF fields=0.7176 0.5412 0.4000 1.0000 cgSRGB=0.7176 0.5412 0.4000 1.0000
//     N primary [light] desc=#000000D8 fields=0.0000 0.0000 0.0000 0.8471 cgSRGB=0.0000 0.0000 0.0000 0.8471
//     N primary [dark] desc=#FFFFFFD8 fields=1.0000 1.0000 1.0000 0.8471 cgSRGB=1.0000 1.0000 1.0000 0.8471
//     N secondary [light] desc=#0000007F fields=0.0000 0.0000 0.0000 0.4980 cgSRGB=0.0000 0.0000 0.0000 0.4980
//     N secondary [dark] desc=#FFFFFF8C fields=1.0000 1.0000 1.0000 0.5490 cgSRGB=1.0000 1.0000 1.0000 0.5490
//     N accentColor [light] desc=#0088FFFF fields=0.0000 0.5333 1.0000 1.0000 cgSRGB=0.0000 0.5333 1.0000 1.0000
//     N accentColor [dark] desc=#0091FFFF fields=0.0000 0.5686 1.0000 1.0000 cgSRGB=0.0000 0.5686 1.0000 1.0000
//   --- O: opacity
//     O1 red.opacity(0.5) [light] desc=#FF383C80 fields=1.0000 0.2196 0.2353 0.5000 cgSRGB=1.0000 0.2196 0.2353 0.5000
//     O1 red.opacity(0.5) [dark] desc=#FF424580 fields=1.0000 0.2588 0.2706 0.5000 cgSRGB=1.0000 0.2588 0.2706 0.5000
//     O2 primary.opacity(0.5) [light] desc=#0000006C fields=0.0000 0.0000 0.0000 0.4235 cgSRGB=0.0000 0.0000 0.0000 0.4235
//     O2 primary.opacity(0.5) [dark] desc=#FFFFFF6C fields=1.0000 1.0000 1.0000 0.4235 cgSRGB=1.0000 1.0000 1.0000 0.4235
//     O3 Color(white:0,opacity:0.5).opacity(0.5) [light] desc=#00000040 fields=0.0000 0.0000 0.0000 0.2500 cgSRGB=0.0000 0.0000 0.0000 0.2500
//     O3 Color(white:0,opacity:0.5).opacity(0.5) [dark] desc=#00000040 fields=0.0000 0.0000 0.0000 0.2500 cgSRGB=0.0000 0.0000 0.0000 0.2500
//     O4 red.opacity(1.5) [light] desc=#FF383C17F fields=1.0000 0.2196 0.2353 1.5000 cgSRGB=1.0000 0.2196 0.2353 1.0000
//     O4 red.opacity(1.5) [dark] desc=#FF424517F fields=1.0000 0.2588 0.2706 1.5000 cgSRGB=1.0000 0.2588 0.2706 1.0000
//     O5 red.opacity(-1) [light] desc=#FF383CFFFFFF02 fields=1.0000 0.2196 0.2353 -1.0000 cgSRGB=1.0000 0.2196 0.2353 0.0000
//     O5 red.opacity(-1) [dark] desc=#FF4245FFFFFF02 fields=1.0000 0.2588 0.2706 -1.0000 cgSRGB=1.0000 0.2588 0.2706 0.0000
//   --- Q: equality and hashing
//     Q1 red == red: true
//     Q2 Color(red:1,0,0) == Color(red:1,0,0): true
//     Q3 red.opacity(0.5) == red.opacity(0.5): true
//     Q4 Color(white:1) == .white: true
//     Q5 Color(red:1,green:1,blue:1) == Color(white:1): true
//     Q6 ColorScheme.allCases: [SwiftUI.ColorScheme.light, SwiftUI.ColorScheme.dark]
//   --- D: dynamic colours
//     D0 Color(nsColor: static) [light] desc=#19334CFF fields=0.1000 0.2000 0.3000 1.0000 cgSRGB=0.1000 0.2000 0.3000 1.0000
//     D0 Color(nsColor: static) [dark] desc=#19334CFF fields=0.1000 0.2000 0.3000 1.0000 cgSRGB=0.1000 0.2000 0.3000 1.0000
//     D1 Color(nsColor: dynamic) [light] desc=#1A334CFF fields=0.1000 0.2000 0.3000 1.0000 cgSRGB=0.1000 0.2000 0.3000 1.0000
//     D1 Color(nsColor: dynamic) [dark] desc=#E6CCB3FF fields=0.9000 0.8000 0.7000 1.0000 cgSRGB=0.9000 0.8000 0.7000 1.0000
//     D2 Color(nsColor: dynamic).opacity(0.5) [light] desc=#1A334C80 fields=0.1000 0.2000 0.3000 0.5000 cgSRGB=0.1000 0.2000 0.3000 0.5000
//     D2 Color(nsColor: dynamic).opacity(0.5) [dark] desc=#E6CCB380 fields=0.9000 0.8000 0.7000 0.5000 cgSRGB=0.9000 0.8000 0.7000 0.5000
//   --- E: environment colorScheme
//     E0 bare EnvironmentValues().colorScheme = light
//     E1 aqua window: reads(last)=["root=light"] window.appearance=NSAppearanceNameAqua effective=NSAppearanceNameAqua
//     E2 darkAqua window: reads(last)=["root=dark"] window.appearance=NSAppearanceNameDarkAqua effective=NSAppearanceNameDarkAqua
//   --- P: preferredColorScheme
//     P0 no modifier (aqua): reads(last)=["a=light", "b=light"] window.appearance=NSAppearanceNameAqua effective=NSAppearanceNameAqua
//     P1 child .preferredColorScheme(.dark) (aqua): reads(last)=["a=light", "b=light", "a=dark", "b=dark"] window.appearance=NSAppearanceNameDarkAqua effective=NSAppearanceNameDarkAqua
//     P2 child .preferredColorScheme(nil) (aqua): reads(last)=["a=light", "b=light"] window.appearance=NSAppearanceNameAqua effective=NSAppearanceNameAqua
//     P3 conflict: a dark, b light (aqua): reads(last)=["a=light", "b=light", "a=dark", "b=dark"] window.appearance=NSAppearanceNameDarkAqua effective=NSAppearanceNameDarkAqua
//     P4 conflict: a light, b dark (aqua): reads(last)=["a=light", "b=light"] window.appearance=NSAppearanceNameAqua effective=NSAppearanceNameAqua
//     P5 nested: outer light, inner dark (aqua): reads(last)=["a=light"] window.appearance=NSAppearanceNameAqua effective=NSAppearanceNameAqua
//     P6 nested: outer nil, inner dark (aqua): reads(last)=["a=light"] window.appearance=NSAppearanceNameAqua effective=NSAppearanceNameAqua
//     P7 siblings: a nil, b dark (aqua): reads(last)=["a=light", "b=light", "a=dark", "b=dark"] window.appearance=NSAppearanceNameDarkAqua effective=NSAppearanceNameDarkAqua
//     P8a preference .dark (window had nil appearance): reads(last)=["t=dark"] window.appearance=NSAppearanceNameDarkAqua effective=NSAppearanceNameDarkAqua
//     P8b after preference -> nil: reads(last)=["t=dark"] window.appearance=nil
//   --- V: environment(\.colorScheme)
//     V1 child .environment(\.colorScheme,.dark) (aqua): reads(last)=["a=dark", "b=light"] window.appearance=NSAppearanceNameAqua effective=NSAppearanceNameAqua
//   --- T: an appearance change on a live window
//     T0 before: reads(last)=["root=light"] window.appearance=NSAppearanceNameAqua effective=NSAppearanceNameAqua
//     T1 after window.appearance = darkAqua: reads(last)=["root=light", "root=dark"]
//   --- end

import AppKit
import SwiftUI

func fmt(_ x: Double) -> String { String(format: "%.4f", x) }

func line(_ label: String, _ color: Color, _ scheme: ColorScheme) {
    var env = EnvironmentValues()
    env.colorScheme = scheme
    let r = color.resolve(in: env)
    var cg = "nil"
    if let c = r.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   intent: .defaultIntent, options: nil),
       let comps = c.components {
        cg = comps.map { fmt(Double($0)) }.joined(separator: " ")
    }
    print("  \(label) [\(scheme)] desc=\(r.description) fields=\(fmt(Double(r.red))) \(fmt(Double(r.green))) \(fmt(Double(r.blue))) \(fmt(Double(r.opacity))) cgSRGB=\(cg)")
}

func both(_ label: String, _ color: Color) {
    line(label, color, .light)
    line(label, color, .dark)
}

print("--- R: literal initialisers")
both("R0 Color(red:1,green:0,blue:0)", Color(red: 1, green: 0, blue: 0))
both("R1 Color(white:0.5)", Color(white: 0.5))
both("R2 Color(.sRGB,0.2,0.4,0.6,opacity:0.8)", Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.8))
both("R3 Color(.sRGBLinear,0.2,0.4,0.6)", Color(.sRGBLinear, red: 0.2, green: 0.4, blue: 0.6))
both("R4 Color(.displayP3,1,0,0)", Color(.displayP3, red: 1, green: 0, blue: 0))
both("R5 Color(red:1.2,green:-0.1,blue:0.5) out of range", Color(red: 1.2, green: -0.1, blue: 0.5))
both("R6 Color(hue:0.5,saturation:1,brightness:1)", Color(hue: 0.5, saturation: 1, brightness: 1))
both("R7 Color(white:0.5,opacity:0.25)", Color(white: 0.5, opacity: 0.25))

print("--- N: named statics")
let named: [(String, Color)] = [
    ("black", .black), ("white", .white), ("clear", .clear), ("gray", .gray),
    ("red", .red), ("orange", .orange), ("yellow", .yellow), ("green", .green),
    ("mint", .mint), ("teal", .teal), ("cyan", .cyan), ("blue", .blue),
    ("indigo", .indigo), ("purple", .purple), ("pink", .pink), ("brown", .brown),
    ("primary", .primary), ("secondary", .secondary), ("accentColor", .accentColor),
]
for (name, color) in named { both("N \(name)", color) }

print("--- O: opacity")
both("O1 red.opacity(0.5)", Color.red.opacity(0.5))
both("O2 primary.opacity(0.5)", Color.primary.opacity(0.5))
both("O3 Color(white:0,opacity:0.5).opacity(0.5)", Color(white: 0, opacity: 0.5).opacity(0.5))
both("O4 red.opacity(1.5)", Color.red.opacity(1.5))
both("O5 red.opacity(-1)", Color.red.opacity(-1))

print("--- Q: equality and hashing")
print("  Q1 red == red: \(Color.red == Color.red)")
print("  Q2 Color(red:1,0,0) == Color(red:1,0,0): \(Color(red: 1, green: 0, blue: 0) == Color(red: 1, green: 0, blue: 0))")
print("  Q3 red.opacity(0.5) == red.opacity(0.5): \(Color.red.opacity(0.5) == Color.red.opacity(0.5))")
print("  Q4 Color(white:1) == .white: \(Color(white: 1) == Color.white)")
print("  Q5 Color(red:1,green:1,blue:1) == Color(white:1): \(Color(red: 1, green: 1, blue: 1) == Color(white: 1))")
print("  Q6 ColorScheme.allCases: \(ColorScheme.allCases)")

print("--- D: dynamic colours")
let staticNS = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
both("D0 Color(nsColor: static)", Color(nsColor: staticNS))
let dynamicNS = NSColor(name: "probe.dynamic") { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 0.9, green: 0.8, blue: 0.7, alpha: 1)
        : NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
}
both("D1 Color(nsColor: dynamic)", Color(nsColor: dynamicNS))
both("D2 Color(nsColor: dynamic).opacity(0.5)", Color(nsColor: dynamicNS).opacity(0.5))

print("--- E: environment colorScheme")
print("  E0 bare EnvironmentValues().colorScheme = \(EnvironmentValues().colorScheme)")

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

final class Log { static var reads: [String] = [] }

struct Reader: View {
    let tag: String
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Log.reads.append("\(tag)=\(scheme)")
        return SwiftUI.Color.clear.frame(width: 20, height: 20)
    }
}

func host<V: View>(_ label: String, appearance: NSAppearance.Name?, _ view: V) -> NSWindow {
    Log.reads = []
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    if let appearance { window.appearance = NSAppearance(named: appearance) }
    let hosting = NSHostingView(rootView: view)
    window.contentView = hosting
    window.orderFront(nil)
    for _ in 0..<5 {
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    let reads = Array(Log.reads.suffix(4))
    print("  \(label): reads(last)=\(reads) window.appearance=\(window.appearance?.name.rawValue ?? "nil") effective=\(window.effectiveAppearance.name.rawValue)")
    return window
}

var keep: [NSWindow] = []
keep.append(host("E1 aqua window", appearance: .aqua, Reader(tag: "root")))
keep.append(host("E2 darkAqua window", appearance: .darkAqua, Reader(tag: "root")))

print("--- P: preferredColorScheme")
keep.append(host("P0 no modifier (aqua)", appearance: .aqua,
                 HStack { Reader(tag: "a"); Reader(tag: "b") }))
keep.append(host("P1 child .preferredColorScheme(.dark) (aqua)", appearance: .aqua,
                 HStack { Reader(tag: "a").preferredColorScheme(.dark); Reader(tag: "b") }))
keep.append(host("P2 child .preferredColorScheme(nil) (aqua)", appearance: .aqua,
                 HStack { Reader(tag: "a").preferredColorScheme(nil); Reader(tag: "b") }))
keep.append(host("P3 conflict: a dark, b light (aqua)", appearance: .aqua,
                 HStack { Reader(tag: "a").preferredColorScheme(.dark); Reader(tag: "b").preferredColorScheme(.light) }))
keep.append(host("P4 conflict: a light, b dark (aqua)", appearance: .aqua,
                 HStack { Reader(tag: "a").preferredColorScheme(.light); Reader(tag: "b").preferredColorScheme(.dark) }))
keep.append(host("P5 nested: outer light, inner dark (aqua)", appearance: .aqua,
                 VStack { Reader(tag: "a").preferredColorScheme(.dark) }.preferredColorScheme(.light)))

keep.append(host("P6 nested: outer nil, inner dark (aqua)", appearance: .aqua,
                 VStack { Reader(tag: "a").preferredColorScheme(.dark) }.preferredColorScheme(nil)))
keep.append(host("P7 siblings: a nil, b dark (aqua)", appearance: .aqua,
                 HStack { Reader(tag: "a").preferredColorScheme(nil); Reader(tag: "b").preferredColorScheme(.dark) }))

final class Pref: ObservableObject { @Published var scheme: ColorScheme? = .dark }
struct Toggled: View {
    @ObservedObject var pref: Pref
    var body: some View { Reader(tag: "t").preferredColorScheme(pref.scheme) }
}
let pref = Pref()
let toggled = host("P8a preference .dark (window had nil appearance)", appearance: nil, Toggled(pref: pref))
pref.scheme = nil
for _ in 0..<5 {
    toggled.contentView?.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
print("  P8b after preference -> nil: reads(last)=\(Array(Log.reads.suffix(2))) window.appearance=\(toggled.appearance?.name.rawValue ?? "nil")")
keep.append(toggled)

print("--- V: environment(\\.colorScheme)")
keep.append(host("V1 child .environment(\\.colorScheme,.dark) (aqua)", appearance: .aqua,
                 HStack { Reader(tag: "a").environment(\.colorScheme, .dark); Reader(tag: "b") }))

print("--- T: an appearance change on a live window")
Log.reads = []
let live = host("T0 before", appearance: .aqua, Reader(tag: "root"))
live.appearance = NSAppearance(named: .darkAqua)
for _ in 0..<5 {
    live.contentView?.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
print("  T1 after window.appearance = darkAqua: reads(last)=\(Array(Log.reads.suffix(2)))")
print("--- end")

import Testing
import MetalUICore
import Metal
import MetalUIPlatform
@testable import MetalUI

/// `SD-A`/`SD-B`: the selected segment of a segmented `Picker` reads as selected in both
/// appearances. In the dark theme `.surface` (0x161C2E) is darker than the track
/// `.surfaceSecondary` (0x27304A), so the pill used to read as *less* selected.

/// Relative luminance of a resolved colour composited over an opaque backdrop (gamma-space,
/// Rec. 709 weights: enough to order two greys).
private func luminance(_ colour: Hsla, over backdrop: Hsla) -> Float {
    func rgb(_ c: Hsla) -> (Float, Float, Float) { let r = c.toRgba(); return (r.r, r.g, r.b) }
    let (fr, fg, fb) = rgb(colour), (br, bg, bb) = rgb(backdrop)
    let a = colour.a
    return 0.2126 * (fr * a + br * (1 - a)) + 0.7152 * (fg * a + bg * (1 - a)) + 0.0722 * (fb * a + bb * (1 - a))
}

/// The track fill and the selected segment's fill of a three-segment picker (tag 1 selected).
@MainActor
private func trackAndSelected(_ appearance: Appearance) throws -> (track: Hsla, selected: Hsla, theme: Theme) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, _) = try makeFakeWindow(device: device, size: 400, appearance: appearance) {
        controlRoot {
            Picker("Size", selection: .constant(1)) {
                Text("S").tag(0)
                Text("M").tag(1)
                Text("L").tag(2)
            }.pickerStyle(.segmented)
        }
    }
    window.drawFrameIfNeeded()
    let theme = window.theme
    let rects = window.lastScene.rects
    let tracks = rects.filter { ixSame(ixHsla($0.background), theme[.surfaceSecondary]) }
    let track = try #require(tracks.max { $0.bounds.size.width < $1.bounds.size.width }, "no track rect")
    let trackBounds = track.bounds
    var inside: [MUIRect] = []
    for rect in rects {
        let b = rect.bounds
        let within: Bool = b.origin.x >= trackBounds.origin.x && b.origin.y >= trackBounds.origin.y
        let narrower: Bool = b.size.width < trackBounds.size.width && b.size.width > 0
        let painted: Bool = rect.background.a > 0
        let isTrackFill: Bool = ixSame(ixHsla(rect.background), theme[.surfaceSecondary])
        if within && narrower && painted && !isTrackFill { inside.append(rect) }
    }
    let pill = try #require(inside.first, "no selected-segment rect inside the track")
    try #require(inside.count == 1, "exactly one segment is filled (\(inside.count))")
    return (ixHsla(track.background), ixHsla(pill.background), theme)
}

/// Dark: the selected segment composites lighter than the track, and is not the track's colour.
@Test @MainActor func theSelectedSegmentIsLighterThanTheTrackInDark() throws {
    let (track, selected, _) = try trackAndSelected(.dark)
    #expect(!ixSame(track, selected), "the pill must differ from the track")
    let pill = luminance(selected, over: track)
    let base = luminance(track, over: track)
    #expect(pill > base + 0.05, "dark: the selected pill (\(pill)) reads lighter than the track (\(base))")
}

/// Light is unchanged: the selected segment is exactly `.surface` on the `.surfaceSecondary` track.
@Test @MainActor func theSelectedSegmentIsStillSurfaceInLight() throws {
    let (track, selected, theme) = try trackAndSelected(.light)
    #expect(ixSame(selected, theme[.surface]), "light: the pill is .surface")
    #expect(ixSame(track, theme[.surfaceSecondary]))
    #expect(luminance(selected, over: track) > luminance(track, over: track))
}

// MARK: - SD-C: the selected segment's hairline edge (Alloy G23/G28)

private func wcag(_ c: Rgba) -> Double {
    func lin(_ v: Float) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
}
private func contrastRatio(_ a: Rgba, _ b: Rgba) -> Double {
    let (x, y) = (wcag(a), wcag(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}
private func composite(_ ink: Hsla, over base: Rgba) -> Rgba {
    let i = ink.toRgba()
    return Rgba(r: i.r * i.a + base.r * (1 - i.a), g: i.g * i.a + base.g * (1 - i.a), b: i.b * i.a + base.b * (1 - i.a), a: 1)
}

/// The rects with a border drawn inside a three-segment picker (tag 1 selected), plus the theme.
@MainActor
private func borderedRects(_ appearance: Appearance, theme: Theme? = nil) throws -> (bordered: [MUIRect], rects: [MUIRect], theme: Theme) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, _) = try makeFakeWindow(device: device, size: 400, appearance: appearance) {
        controlRoot {
            Picker("Size", selection: .constant(1)) {
                Text("S").tag(0)
                Text("M").tag(1)
                Text("L").tag(2)
            }.pickerStyle(.segmented).theme(theme ?? (appearance == .dark ? Theme.dark : Theme.light))
        }
    }
    window.drawFrameIfNeeded()
    let rects = window.lastScene.rects
    return (rects.filter { $0.borderWidths.top > 0 }, rects, theme ?? window.theme)
}

/// The selected segment draws a 1-pixel edge at its fill's rect, in `.textPrimary` at AppKit's `separatorColor` alpha
/// (0.10 light, 0.12 dark; probe `swiftui-segmented-thumb.swift`). Mutation: **M1** drop `border:` from the segmented
/// `Decoration` reddens it; **M2** alpha 0.5 reddens it.
@Test @MainActor func theSelectedSegmentDrawsAHairlineEdgeAtItsRect() throws {
    for (appearance, alpha) in [(Appearance.light, Float(0.10)), (.dark, Float(0.12))] {
        let (bordered, rects, theme) = try borderedRects(appearance)
        let edge = try #require(bordered.first, "\(appearance): the selected segment draws an edge")
        #expect(bordered.count == 1, "\(appearance): exactly one edge (\(bordered.count))")
        let b = edge.borderWidths
        #expect(b.top == b.left && b.left == b.bottom && b.bottom == b.right, "\(appearance): the same width on all edges")
        let eb = edge.bounds
        let fill = rects.first {
            $0.background.a > 0 && $0.bounds.origin.x == eb.origin.x && $0.bounds.origin.y == eb.origin.y
                && $0.bounds.size.width == eb.size.width && $0.bounds.size.height == eb.size.height
        }
        #expect(fill != nil, "\(appearance): the edge sits at the thumb's filled rect")
        #expect(rects.contains { $0.background.a > 0 && ixSame(ixHsla($0.background), theme[.surfaceSecondary]) }, "\(appearance): the track is still painted")
        let want = theme[.textPrimary]
        let got = ixHsla(edge.borderColor)
        #expect(abs(got.a - alpha) < 0.01, "\(appearance): alpha \(got.a)")
        #expect(abs(got.l - want.l) < 0.01 && abs(got.h - want.h) < 0.01, "\(appearance): the colour is textPrimary")
    }
}

/// An unselected segment draws no edge: with tag 1 selected of three, one bordered rect, and the track has none.
/// Mutation: **M3** `border:` unconditional reddens it (three edges).
@Test @MainActor func anUnselectedSegmentHasNoEdge() throws {
    let (bordered, _, _) = try borderedRects(.light)
    #expect(bordered.count == 1, "only the selected segment is edged (\(bordered.count))")
}

/// Solarized Light (page = surface = base3 #FDF6E3, track base2 #EEE8D5, text base00 #657B83): the edge composited on the
/// thumb differs from the page. A hairline at AppKit's 0.10 alpha reaches only about 1.2:1 here, NOT 3:1 (reported in
/// record 260 and `SD-C`); the pin is that the edge exists and is darker than the page. Mutation: **M1** reddens it.
@Test @MainActor func theEdgeSeparatesTheThumbFromAPageEqualToSurface() throws {
    let base3 = Hsla.rgb(0xFDF6E3), base2 = Hsla.rgb(0xEEE8D5), base00 = Hsla.rgb(0x657B83)
    let solarized = Theme(background: base3, surface: base3, surfaceSecondary: base2, accent: .rgb(0x268BD2),
                          separator: .rgb(0x93A1A1), textPrimary: base00, scrollIndicator: base00, scrim: .rgb(0x002B36, alpha: 0.4))
    let (bordered, _, _) = try borderedRects(.light, theme: solarized)
    let edge = try #require(bordered.first, "the thumb has an edge")
    let page = base3.toRgba()
    let onThumb = composite(ixHsla(edge.borderColor), over: base3.toRgba())
    let ratio = contrastRatio(onThumb, page)
    print("SD-C solarized edge-vs-page contrast: \(ratio)")
    #expect(ratio > 1.05, "the edge differs from the page (\(ratio):1; 3:1 is not reachable at AppKit's alpha)")
}

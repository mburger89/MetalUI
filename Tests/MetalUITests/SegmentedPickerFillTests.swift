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

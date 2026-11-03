import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIText
@testable import MetalUI

// R3-10 item 7 -- accessibility display settings as environment values from the platform
// (rulings `AD-B`..`AD-E`, `AD-I`, `AD-J`). SwiftUI's side is
// `docs/probes/swiftui-accessibility-display.swift`.

/// What a recorder saw at layout, per label: the seven values.
struct ADReading: Equatable {
    var contrast: ColorSchemeContrast
    var differentiate: Bool, invert: Bool, borders: Bool, shapes: Bool, flashing: Bool, animated: Bool
    var weight: LegibilityWeight?
    init(_ e: EnvironmentValues) {
        contrast = e.colorSchemeContrast
        differentiate = e.accessibilityDifferentiateWithoutColor
        invert = e.accessibilityInvertColors
        borders = e.accessibilityShowBorders
        shapes = e.accessibilityShowButtonShapes
        flashing = e.accessibilityDimFlashingLights
        animated = e.accessibilityPlayAnimatedImages
        weight = e.legibilityWeight
    }
}

@MainActor final class ADLog { var readings: [String: ADReading] = [:] }

/// A 10 x 10 proposal leaf that logs the environment it is laid out in.
struct ADRecorder: ProposalElement {
    let label: String
    let log: ADLog
    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        log.readings[label] = ADReading(pass.environment)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

private let allOn = AccessibilityDisplaySettings(
    colorSchemeContrast: .increased, differentiateWithoutColor: true, invertColors: true,
    showBorders: true, dimFlashingLights: true, playAnimatedImages: true)

/// **3** (V0). A bare `EnvironmentValues()` and `renderFrame`'s root read SwiftUI's bare values
/// for every key. Mutations: one computed getter returns a constant; `renderFrame`'s stamp
/// writes `.increased`.
@MainActor @Test func aBareEnvironmentAndRenderFrameReadSwiftUIsAccessibilityDisplayDefaults() {
    let bare = ADReading(EnvironmentValues())
    let expected = ADReading(EnvironmentValues())
    #expect(bare == expected)
    #expect(bare.contrast == .standard && !bare.differentiate && !bare.invert && !bare.borders && !bare.shapes
                && !bare.flashing && !bare.animated && bare.weight == nil,
            "V0: \(bare)")

    let log = ADLog()
    _ = renderFrame({ Column { ADRecorder(label: "r", log: log) } },
                    size: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                    textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 64, height: 64))
    #expect(log.readings["r"] == bare, "renderFrame stamps the bare settings: \(String(describing: log.readings["r"]))")
}

/// **4.** The window's root display settings are its platform window's: read at construction
/// (a fake starting all-on, so the bare value of `Window.environment` cannot pass for it); a
/// change reported through `onAccessibilityDisplaySettingsChange` dirties the window and the
/// next frame reads it; a report of the value the window already has does not dirty it; and
/// `Window.environment`'s own value is not the root's source. Mutations: drop the
/// `drawFrame` stamp (first arm); `Window.init` does not install the callback (change arm);
/// drop the `didSet` guard (repeat arm); drop `setNeedsRedraw()` (change arm).
@MainActor @Test func theWindowStampsAccessibilityDisplaySettingsFromItsPlatformWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = try FakePlatformWindow(device: device, size: 300)
    platform.accessibilityDisplaySettings = allOn
    let log = ADLog()
    let window = Window(platformWindow: platform, startsDisplayLink: true) {
        Column { ADRecorder(label: "r", log: log) }
    }
    try #require(ADReading(window.environment) != ADReading(allOnEnvironment()),
                 "Window.environment must hold a different value from the platform's, or the stamp is unobservable")

    #expect(window.accessibilityDisplaySettings == allOn, "read at construction")
    window.drawFrameIfNeeded()
    #expect(log.readings["r"] == ADReading(allOnEnvironment()), "the first frame reads the platform's value")
    #expect(window.needsRedraw == false)

    var standard = allOn
    standard.colorSchemeContrast = .standard
    platform.simulateAccessibilityDisplaySettingsChange(to: standard)
    #expect(window.needsRedraw == true, "a settings change must redraw")
    window.drawFrameIfNeeded()
    #expect(log.readings["r"]?.contrast == .standard, "and the next frame reads it")
    #expect(log.readings["r"]?.invert == true, "while the other values stay")

    #expect(window.needsRedraw == false)
    platform.simulateAccessibilityDisplaySettingsChange(to: standard)
    #expect(window.needsRedraw == false, "a report of the settings the window already has must not redraw")

    window.environment.accessibilityDisplay = AccessibilityDisplaySettings()
    window.drawFrameIfNeeded()
    #expect(log.readings["r"]?.invert == true && log.readings["r"]?.contrast == .standard,
            "Window.environment.accessibilityDisplay changes nothing at the root")
}

@MainActor private func allOnEnvironment() -> EnvironmentValues {
    var e = EnvironmentValues()
    e.accessibilityDisplay = allOn
    return e
}

/// **5.** Each key reads only its own field: one setting turned on moves exactly that key (and
/// `accessibilityShowButtonShapes` follows `accessibilityShowBorders`). Mutations:
/// `accessibilityInvertColors` reads `differentiateWithoutColor`; `accessibilityShowButtonShapes`
/// returns `false`.
@MainActor @Test func eachDisplaySettingReachesOnlyItsOwnKey() {
    func reading(_ change: (inout AccessibilityDisplaySettings) -> Void) -> ADReading {
        var settings = AccessibilityDisplaySettings(); change(&settings)
        var e = EnvironmentValues(); e.accessibilityDisplay = settings
        return ADReading(e)
    }
    let bare = ADReading(EnvironmentValues())
    var expected = bare; expected.contrast = .increased
    #expect(reading { $0.colorSchemeContrast = .increased } == expected, "contrast")
    expected = bare; expected.differentiate = true
    #expect(reading { $0.differentiateWithoutColor = true } == expected, "differentiate")
    expected = bare; expected.invert = true
    #expect(reading { $0.invertColors = true } == expected, "invert")
    expected = bare; expected.borders = true; expected.shapes = true
    #expect(reading { $0.showBorders = true } == expected, "borders and its alias")
    expected = bare; expected.flashing = true
    #expect(reading { $0.dimFlashingLights = true } == expected, "flashing")
    expected = bare; expected.animated = true
    #expect(reading { $0.playAnimatedImages = true } == expected, "animated")
}

/// **6** (`AD-J`). `legibilityWeight` is writable and scoped, the nearest writer winning, and
/// the window stamps none: a window's root reads `nil`. Under `.bold` no text measurement
/// changes (divergence 1079: `Text` does not read it). Mutation: a `Window` stamp of
/// `legibilityWeight` overriding the scope.
@MainActor @Test func legibilityWeightIsScopedNearestWriterWins() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = try FakePlatformWindow(device: device, size: 300)
    platform.accessibilityDisplaySettings = allOn
    let log = ADLog()
    let window = Window(platformWindow: platform, startsDisplayLink: true) {
        Column {
            ADRecorder(label: "root", log: log)
            Column { ADRecorder(label: "bold", log: log) }.environment(\.legibilityWeight, .bold)
            Column {
                Column { ADRecorder(label: "inner", log: log) }.environment(\.legibilityWeight, .regular)
            }.environment(\.legibilityWeight, .bold)
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.readings["root"]?.weight == nil, "the window stamps no weight")
    #expect(log.readings["bold"]?.weight == .bold)
    #expect(log.readings["inner"]?.weight == .regular, "the nearest writer wins")

    func width(_ weight: LegibilityWeight?) -> Float {
        let frame = effectFrame(Column { Text("Legibility weight sample") }.environment(\.legibilityWeight, weight), side: 400)
        let glyphs = frame.finalizedScene().glyphs
        return (glyphs.map { $0.bounds.origin.x + $0.bounds.size.width }.max() ?? 0) - (glyphs.map { $0.bounds.origin.x }.min() ?? 0)
    }
    #expect(width(.bold) == width(nil) && width(.regular) == width(nil), "divergence 1079: Text does not read legibilityWeight")
}

/// **7** (`AD-I`; divergences 1076, 1078). No built-in control reacts to any display setting:
/// every control's scene under the bare settings equals its scene with all six on. SwiftUI's
/// bordered `Button`, checkbox `Toggle`, `Divider` and others DO change under Increase Contrast
/// and Show Borders (probe C1, B1), which is what the divergences record. Mutation: the bordered
/// `Button`'s chrome darkens under `.increased`.
@MainActor @Test func noBuiltInControlReactsToAccessibilityDisplaySettings() throws {
    func scene(_ gallery: some ElementGroup, on: Bool) -> Data {
        let frame = effectFrame(Column { gallery }.environment(\.accessibilityDisplay, on ? allOn : AccessibilityDisplaySettings()), side: 300)
        let s = frame.finalizedScene()
        func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
        return bytes(s.rects) + bytes(s.glyphs) + bytes(s.images)
    }
    func check(_ name: String, _ control: some ElementGroup) throws {
        let off = scene(control, on: false), on = scene(control, on: true)
        try #require(!off.isEmpty, "\(name) painted nothing")
        #expect(off == on, "\(name) must not react to the display settings")
    }
    try check("Button .bordered", Button("Bordered") {}.buttonStyle(.bordered))
    try check("Button .borderless", Button("Borderless") {}.buttonStyle(.borderless))
    try check("Button .plain", Button("Plain") {}.buttonStyle(.plain))
    try check("Toggle .switch", Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch))
    try check("Toggle .checkbox", Toggle("Checkbox", isOn: .constant(true)).toggleStyle(.checkbox))
    try check("Divider", Column { Text("a"); Divider(); Text("b") })
    try check("TextField", TextField("Field", text: .constant("text")))
    try check("Picker .segmented", Picker("Seg", selection: .constant(1)) { Text("A").tag(1); Text("B").tag(2) }.pickerStyle(.segmented))
}

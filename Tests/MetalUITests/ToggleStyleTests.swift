import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Round 3, item R3-1 (rulings `BY-`, `docs/superpowers/2026-10-31-styles-decisions.md`): `toggleStyle(_:)` with
// `.checkbox`, `.switch`, `.button` and the open `ToggleStyle` protocol, and `.pickerStyle(.inline)`. SwiftUI's
// shape is the authority; every look and metric is MetalUI's (unmeasured, human check BY).

private let styleBlue = Color(srgb: 0, 0, 1, 1)
private let styleRed = Color(srgb: 1, 0, 0, 1)

@MainActor
private final class Flag {
    var isOn = false
    var writes: [Bool] = []
    var binding: Binding<Bool> {
        Binding(get: { self.isOn }, set: { self.isOn = $0; self.writes.append($0) })
    }
}

/// A custom toggle style: the label over a fill that is red while on, blue while off. It never writes the binding
/// itself, so the toggle's own click, Space and accessibility press must.
private struct FillStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some ElementGroup {
        configuration.label.padding(6).background(configuration.isOn ? styleRed : styleBlue)
    }
}

/// A custom style that records `isMixed` and flips the binding from its own click, as SwiftUI's custom styles do.
@MainActor
private final class MixedSpy { var mixed: [Bool] = [] }

private struct SelfFlippingStyle: ToggleStyle {
    let spy: MixedSpy
    func makeBody(configuration: Configuration) -> some ElementGroup {
        spy.mixed.append(configuration.isMixed)
        return configuration.label.onClick { configuration.isOn.toggle() }
    }
}

private func colour(_ color: Color) -> Hsla { color.resolved(theme: .light, scheme: .light) }

// MARK: - 1 the built-in styles

/// **1.** `.checkbox` is the macOS default: byte for byte the bare `Toggle`, on and off. Mutation `BY-M6` (the
/// default resolves to `.switch`) reddens it.
@Test @MainActor func checkboxIsTheDefaultToggleStyle() throws {
    for on in [false, true] {
        let bare = ixSceneBytes { controlRoot { Toggle("Wi-Fi", isOn: .constant(on)) } }
        let styled = ixSceneBytes { controlRoot { Toggle("Wi-Fi", isOn: .constant(on)).toggleStyle(.checkbox) } }
        #expect(bare == styled, ".checkbox is the automatic style (on: \(on))")
    }
}

/// **2.** `.switch`: a 38×22 capsule track (MetalUI's metrics, unmeasured), accent when on, with a white 18-point
/// knob inset 2 that sits at the leading end off and the trailing end on; the label follows at 7. The separating
/// arms are the checkbox's 14×14 box and the off track's neutral fill.
@Test @MainActor func switchIsACapsuleTrackWithAKnobAtTheOnEnd() throws {
    var knobXs: [Float] = []
    for on in [false, true] {
        let frame = try controlRender(controlRoot { Toggle("Wi-Fi", isOn: .constant(on)).toggleStyle(.switch) })
        let track = try controlBounds(frame, controlID([0, 0, 0]))
        let label = try controlBounds(frame, controlID([0, 0, 1, 0]))
        #expect(track.size.width.value == 38 && track.size.height.value == 22, "a 38×22 track: \(track.size)")
        #expect(label.origin.x.value - track.origin.x.value == 38 + 7, "the label 7 after the track")
        // The off track's border is its own clear-filled rect; the fills are the track and the knob.
        let rects = frame.finalizedScene().rects.filter { $0.background.a > 0 }
        try #require(rects.count == 2, "the track and the knob (on: \(on)): \(rects.count)")
        let trackRect = rects[0], knob = rects[1]
        let accent = Theme.light[.accent]
        #expect(ixSame(ixHsla(trackRect.background), accent) == on, "the track is accent exactly when on (\(on))")
        #expect(ixSame(ixHsla(knob.background), colour(.white)), "a white knob")
        #expect(ixBounds(knob).size.width.value == 18 && ixBounds(knob).size.height.value == 18, "an 18-point knob")
        knobXs.append(ixBounds(knob).origin.x.value - track.origin.x.value)
    }
    #expect(knobXs == [2, 18], "the knob inset 2 at the leading end off and the trailing end on: \(knobXs)")
}

/// **3.** `.button`: the toggle drawn as a bordered button — the bordered metrics, the bordered fill off and the
/// accent fill on — and it still flips. The separating arm is the checkbox's size.
@Test @MainActor func buttonToggleStyleDrawsABorderedButtonThatFillsWhenOn() throws {
    let text = try controlTextSize("Bold")
    var fillsSeen: [Hsla] = []
    for on in [false, true] {
        let frame = try controlRender(controlRoot { Toggle("Bold", isOn: .constant(on)).toggleStyle(.button) })
        let toggle = try controlBounds(frame, controlID([0, 0]))
        #expect(toggle.size.width.value == text.width.value + 24, "textW + 24 as a bordered button: \(toggle.size)")
        #expect(toggle.size.height.value == max(text.height.value, 24), "and max(textH, 24)")
        fillsSeen.append(ixHsla(try #require(frame.finalizedScene().rects.first).background))
    }
    #expect(ixSame(fillsSeen[0], Theme.light[.surfaceSecondary]), "off: the bordered fill")
    #expect(ixSame(fillsSeen[1], Theme.light[.accent]), "on: the accent fill")
    let model = Flag()
    let (window, platform) = try controlWindow {
        controlRoot { Toggle("Bold", isOn: model.binding).toggleStyle(.button) }
    }
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), controlID([0, 0]))))
    #expect(model.writes == [true], "a click flips it once")
}

// MARK: - 2 a custom ToggleStyle

/// **4.** A custom style draws from `configuration.isOn` and the toggle keeps the behaviour: a click, a focused
/// Space and an accessibility press each write the negation once, and the node is a published check box. Mutation
/// `BY-M7` (the custom path registers no handlers) reddens it.
@Test @MainActor func aCustomToggleStyleDrawsFromIsOnAndKeepsTheTogglesBehaviour() throws {
    let model = Flag()
    let (window, platform) = try controlWindow {
        controlRoot { Toggle("Wi-Fi", isOn: model.binding).toggleStyle(FillStyle()) }
    }
    func fill() throws -> Hsla { ixHsla(try #require(window.lastScene.rects.first, "the body's fill").background) }
    let id = controlID([0, 0])
    #expect(ixSame(try fill(), colour(styleBlue)), "off: blue")
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    #expect(model.writes == [true], "a click writes true once")
    controlRedraw(window)
    #expect(ixSame(try fill(), colour(styleRed)), "on: red")
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "a custom-styled toggle takes focus")
    platform.simulateInput(controlKey(" "))
    #expect(model.writes == [true, false], "a focused Space writes false once")
    let tree = try controlTree(window, platform)
    let box = try #require(tree.nodes.first { $0.value.role == .checkBox }, "no check box published")
    #expect(platform.simulateAccessibilityRequest(.press(box.key)))
    #expect(model.writes == [true, false, true], "a press writes true once")
}

/// **5.** The configuration's `isMixed` is false (a `Toggle` has no mixed source here, `BY-F`), and a style may
/// write `isOn` itself through the binding. Style written inside a wrapper is inherited.
@Test @MainActor func theConfigurationReportsNotMixedAndItsBindingWrites() throws {
    let spy = MixedSpy()
    let model = Flag()
    let (window, platform) = try controlWindow {
        controlRoot { Column { Toggle("Wi-Fi", isOn: model.binding) }.toggleStyle(SelfFlippingStyle(spy: spy)) }
    }
    #expect(spy.mixed == [false], "isMixed is false: \(spy.mixed)")
    let label = try #require(window.lastElementBounds[controlID([0, 0, 0])], "the toggle's bounds")
    controlClick(platform, at: controlCentre(label))
    #expect(model.writes == [true], "the style's own isOn.toggle() wrote the binding once: \(model.writes)")
}

// MARK: - 3 inheritance and the picker

/// **6.** `.toggleStyle(_:)` is inherited through the environment, nearest writer winning; a toggle outside the
/// scope keeps the checkbox.
@Test @MainActor func aToggleStyleIsInheritedNearestWriterWinning() throws {
    let frame = try controlRender(controlRoot {
        Column {
            Toggle("A", isOn: .constant(true))
            Toggle("B", isOn: .constant(true)).toggleStyle(.checkbox)
        }.toggleStyle(.switch)
        Toggle("C", isOn: .constant(true))
    })
    let inherited = try controlBounds(frame, controlID([0, 0, 0, 0]))
    let overridden = try controlBounds(frame, controlID([0, 0, 1, 0]))
    let outside = try controlBounds(frame, controlID([0, 1, 0]))
    #expect(inherited.size.width.value == 38, "A inherits .switch")
    #expect(overridden.size.width.value == 14, "B's own .checkbox wins")
    #expect(outside.size.width.value == 14, "C is outside the scope")
}

/// **7.** `.pickerStyle(.inline)` is offered: on macOS SwiftUI draws it as the radio group (the labelled column),
/// and so does MetalUI, byte for byte.
@Test @MainActor func anInlinePickerDrawsAsTheRadioGroup() throws {
    func scene(_ style: PickerStyle) -> [[UInt8]] {
        ixSceneBytes {
            controlRoot {
                Picker("Size", selection: .constant(1)) {
                    Text("S").tag(0)
                    Text("M").tag(1)
                }.pickerStyle(style)
            }
        }
    }
    #expect(scene(.inline) == scene(.radioGroup), ".inline is the radio group's look")
    #expect(scene(.inline) != scene(.segmented), "the separating arm: not the segmented look")
}

// MARK: - The switch knob (`SR-D`, divergence 885 retired, 886 live; probe `swiftui-switch-knob.swift`)

/// The knob's x relative to the track's left edge, from the scene's two filled rects (the track, then the knob).
@MainActor
private func knobOffset(_ window: Window) throws -> Float {
    let rects = window.lastScene.rects.filter { $0.background.a > 0 }
    try #require(rects.count == 2, "the track and the knob: \(rects.count)")
    return ixBounds(rects[1]).origin.x.value - ixBounds(rects[0]).origin.x.value
}

/// A ticking window over one `.switch` toggle driven by `flag`, drawn at t = 0.
@MainActor
private func switchWindow(_ flag: Flag, rightToLeft: Bool = false) throws -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 400, startsDisplayLink: true) {
        controlRoot { Toggle("Wi-Fi", isOn: flag.binding).toggleStyle(.switch) }
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    }
    platform.simulateTick(timestamp: 0)
    return (window, platform)
}

/// `SR-D` (found by reading, then measured here): under right-to-left the track is reflected (`LD-A`), so the knob
/// has to be too. Off it sits at the track's leading end, which is the right: 18 from the track's left edge; on at 2.
/// Mutation: `paintKnob` unmirrored (the left-to-right offsets) reddens it.
@Test @MainActor func aSwitchKnobSitsOnItsTrackUnderRightToLeft() throws {
    var offsets: [Float] = []
    for on in [false, true] {
        let flag = Flag(); flag.isOn = on
        let (window, _) = try switchWindow(flag, rightToLeft: true)
        offsets.append(try knobOffset(window))
    }
    #expect(offsets == [18, 2], "off at the track's right (leading) end, on at its left: \(offsets)")
}

/// `SR-D`, probe K2: a write with no animation at all slides (SwiftUI's knob moves on every change). At 0.05 s the
/// knob is strictly between its ends and it has landed by 0.5 s. Mutation: `transaction: nil`.
@Test @MainActor func aSwitchKnobSlidesOnAnUnanimatedWrite() throws {
    let flag = Flag()
    let (window, platform) = try switchWindow(flag)
    let start = try knobOffset(window)
    #expect(start == 2)
    flag.isOn = true
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 1.0)
    let changeFrame = try knobOffset(window)
    #expect(changeFrame == 2, "the change frame is progress 0")
    platform.simulateTick(timestamp: 1.05)
    let early = try knobOffset(window)
    #expect(early > 2.5 && early < 17.5, "mid-travel at 0.05 s: \(early)")
    var peak: Float = 0
    for step in 6...40 {
        platform.simulateTick(timestamp: 1.0 + Double(step) * 0.01)
        peak = max(peak, try knobOffset(window))
    }
    #expect(peak > 18.2 && peak < 19, "the spring overshoots its end by a little (SwiftUI's 0.54): \(peak)")
    platform.simulateTick(timestamp: 1.5)
    let landed = try knobOffset(window)
    #expect(abs(landed - 18) < 0.01, "landed by 0.5 s: \(landed)")
}

/// `SR-D`, probe K3: a `.linear(duration: 1)` write does not slow the knob (SwiftUI's settles in ~0.27 s whatever the
/// transaction). Linear would be at 8.3 at 0.35 s; the fixed spring has landed. Mutation: the transaction drives it.
@Test @MainActor func aLinearOneSecondWriteHasAlreadyLandedByThreeHundredFiftyMilliseconds() throws {
    let flag = Flag()
    let (window, platform) = try switchWindow(flag)
    withAnimation(.linear(duration: 1)) { flag.isOn = true; window.setNeedsRedraw() }
    platform.simulateTick(timestamp: 1.0)
    platform.simulateTick(timestamp: 1.35)
    let landed = try knobOffset(window)
    #expect(abs(landed - 18) < 0.1, "landed: \(landed)")
}

/// `SR-D`, probe K5: `disablesAnimations` snaps the knob (and only that flag does; `withAnimation(nil)` still slides, K6).
/// Mutation: ignore `disablesAnimations`.
@Test @MainActor func aSwitchKnobSnapsUnderDisablesAnimationsAndSlidesUnderANilAnimation() throws {
    let flag = Flag()
    let (window, platform) = try switchWindow(flag)
    var snap = Transaction(); snap.disablesAnimations = true
    withTransaction(snap) { flag.isOn = true; window.setNeedsRedraw() }
    platform.simulateTick(timestamp: 1.0)
    let snapped = try knobOffset(window)
    #expect(snapped == 18, "snapped under disablesAnimations")
    withAnimation(nil) { flag.isOn = false; window.setNeedsRedraw() }
    platform.simulateTick(timestamp: 2.0)
    platform.simulateTick(timestamp: 2.05)
    let early = try knobOffset(window)
    #expect(early < 17.5 && early > 2.5, "withAnimation(nil) still slides (K6): \(early)")
}

/// `SR-D`: the first frame snaps to the declared end (nothing to slide from), and a settled switch interpolates nothing
/// and keeps the window asleep. Mutation: the baseline stored as 0 (the first frame would slide); a key rebuilt per frame.
@Test @MainActor func aSwitchsFirstFrameSnapsAndASettledOneInterpolatesNothing() throws {
    let flag = Flag(); flag.isOn = true
    let (window, platform) = try switchWindow(flag)
    let first = try knobOffset(window)
    #expect(first == 18, "first sighting snaps")
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 1.0)
    #expect(!window.hasActiveAnimations, "settled: nothing animating")
    flag.isOn = false
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 2.0)
    platform.simulateTick(timestamp: 2.05)
    #expect(window.hasActiveAnimations, "sliding keeps the display link awake")
    platform.simulateTick(timestamp: 3.0)
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 3.1)
    #expect(!window.hasActiveAnimations, "landed: asleep again")
    let end = try knobOffset(window)
    #expect(abs(end - 2) < 0.01, "\(end)")
}

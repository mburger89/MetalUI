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

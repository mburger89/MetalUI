import Testing
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 10, part 2, lane 1: `Toggle(isOn:)` (ruling `DD-S`; spec tests
// 1.9–1.13). Helpers are `ButtonTests.swift`'s `control…`.

@MainActor
private final class Switch {
    var isOn = false
    var writes: [Bool] = []
    var binding: Binding<Bool> {
        Binding(get: { self.isOn }, set: { self.isOn = $0; self.writes.append($0) })
    }
}

@MainActor
private func toggleWindow(_ model: Switch, disabled: Bool = false,
                          onKey: (@MainActor (KeyEvent) -> Bool)? = nil,
                          onClick: (@MainActor () -> Void)? = nil) throws -> (Window, FakePlatformWindow) {
    try controlWindow {
        var toggle = Toggle("Wi-Fi", isOn: model.binding)
        if let onKey { toggle = toggle.onKey(onKey) }
        if let onClick { toggle = toggle.onClick(onClick) }
        return controlRoot { toggle.disabled(disabled) }
    }
}

/// **1.9.** A 14-point checkbox, 7 points, then the label: `14 + 7 + textW`
/// wide and as tall as its taller child (TG0: 53×16 over a 32-point label —
/// only the sum 21 is measured). M1h (gap 7 → 8) must redden it.
@Test @MainActor func aToggleIsAFourteenPointCheckboxSevenPointsBeforeItsLabel() throws {
    let text = try controlTextSize("Wi-Fi")
    let frame = try controlRender(controlRoot { Toggle("Wi-Fi", isOn: .constant(false)) })
    let toggle = try controlBounds(frame, controlID([0, 0]))
    let indicator = try controlBounds(frame, controlID([0, 0, 0]))
    let label = try controlBounds(frame, controlID([0, 0, 1]))
    #expect(indicator.size.width.value == 14 && indicator.size.height.value == 14, "a 14×14 box")
    #expect(label.origin.x.value - indicator.origin.x.value == 21, "14 + 7 before the label")
    #expect(toggle.size.width.value == 14 + 7 + text.width.value,
            "14 + 7 + textW: \(toggle.size.width.value) vs \(text.width.value)")
    #expect(toggle.size.height.value == max(indicator.size.height.value, label.size.height.value),
            "as tall as the taller of the box and the label")
}

/// **1.10.** A click, a focused Space and an accessibility press each write
/// the negation once (TA0: `on set true`); a focused Return writes nothing, on
/// every platform. M1i (the write is `isOn`, not `!isOn`) and V12 (Return also
/// toggles) must redden it.
@Test @MainActor func aToggleClickSpaceAndPressEachWriteTheNegationOnce() throws {
    let model = Switch()
    let (window, platform) = try toggleWindow(model)
    let id = controlID([0, 0])
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    #expect(model.writes == [true], "a click writes true once")
    controlRedraw(window)
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "a toggle takes focus")
    platform.simulateInput(controlKey(" "))
    #expect(model.writes == [true, false], "a focused Space writes false once")
    // Return is not a toggle's key on any platform (`ControlKeys.togglesToggle`).
    platform.simulateInput(controlKey("\r"))
    #expect(model.writes == [true, false], "a focused Return writes nothing, read \(model.writes)")
    let tree = try controlTree(window, platform)
    let box = try #require(tree.nodes.first { $0.value.role == .checkBox }, "no check box published")
    #expect(platform.simulateAccessibilityRequest(.press(box.key)))
    #expect(model.writes == [true, false, true], "a press writes true once")
}

/// **1.10b.** A caller's `onKey` runs before the toggle's Space (spec §4, as
/// 1.6 for `Button`): one that claims Space suppresses the write; one that
/// declines lets it run. V8 (the toggle's key replaces the caller's `onKey`)
/// must redden it (`DD-AD` item 5).
@Test @MainActor func aCallersOnKeyRunsBeforeTheTogglesSpace() throws {
    for claims in [true, false] {
        let model = Switch()
        let seen = ControlModel()
        let (window, platform) = try toggleWindow(model, onKey: { event in
            seen.keys.append(event.charactersIgnoringModifiers)
            return claims
        })
        let id = controlID([0, 0])
        window.focus(id)
        window.drawFrameIfNeeded()
        try #require(window.focusedElement == id)
        platform.simulateInput(controlKey(" "))
        #expect(seen.keys == [" "], "claims \(claims): the caller saw the key first")
        #expect(model.writes == (claims ? [] : [true]), "claims \(claims): the write ran only if declined")
    }
}

/// **1.10c.** A caller's `.onClick` on a `Toggle` **replaces** its write (spec
/// §4): a click, a focused Space and a `.press` each run the caller's handler
/// once and write nothing. V9 (the toggle's write overwrites the caller's
/// `onClick`) must redden it (`DD-AD` item 5).
@Test @MainActor func aCallersOnClickReplacesTheTogglesWrite() throws {
    let model = Switch()
    let caller = ControlModel()
    let (window, platform) = try toggleWindow(model, onClick: { caller.count += 1 })
    let id = controlID([0, 0])
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    #expect(caller.count == 1 && model.writes.isEmpty, "a click runs the caller's handler, not the write")
    controlRedraw(window)
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id)
    platform.simulateInput(controlKey(" "))
    #expect(caller.count == 2 && model.writes.isEmpty, "Space runs what the click runs")
    let tree = try controlTree(window, platform)
    let box = try #require(tree.nodes.first { $0.value.role == .checkBox }, "no check box published")
    #expect(platform.simulateAccessibilityRequest(.press(box.key)))
    #expect(caller.count == 3 && model.writes.isEmpty, "a press runs the caller's handler: \(caller.count), \(model.writes)")
}

/// **1.11.** Published as a check box labelled by its label, value `"0"` then
/// `"1"`, no children (TA0; the full fold, `DD-U` item 2). M1j (`.checkBox`
/// left out of the full fold) must redden it.
@Test @MainActor func aTogglePublishesALabelledCheckboxWithItsValue() throws {
    let model = Switch()
    let (window, platform) = try toggleWindow(model)
    let off = try controlTree(window, platform)
    let first = try #require(off.nodes.values.first { $0.role == .checkBox }, "no check box: \(off.nodes.values.map(\.role))")
    #expect(first.label == "Wi-Fi" && first.value == "0" && first.children.isEmpty)
    #expect(off.nodes.count == 1, "the label folds into the check box")
    model.isOn = true
    controlRedraw(window)
    let on = try #require(platform.publishedAccessibilityTrees.last)
    let second = try #require(on.nodes.values.first { $0.role == .checkBox })
    #expect(second.value == "1" && second.label == "Wi-Fi")
}

/// **1.12.** Disabled: no write from a click, a focused Space or a press, and
/// published disabled (TA3). M1g, re-run on this arm, must redden it.
@Test @MainActor func aDisabledToggleWritesNothingAndPublishesDisabled() throws {
    let model = Switch()
    let (window, platform) = try toggleWindow(model, disabled: true)
    let id = controlID([0, 0])
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    window.focus(id)
    window.drawFrameIfNeeded()
    platform.simulateInput(controlKey(" "))
    let tree = try controlTree(window, platform)
    let box = try #require(tree.nodes.first { $0.value.role == .checkBox }, "no check box published")
    platform.simulateAccessibilityRequest(.press(box.key))
    #expect(model.writes.isEmpty, "nothing written while disabled: \(model.writes)")
    #expect(box.value.isEnabled == false, "published disabled")
}

@MainActor @Observable
private final class AnimatedSwitch {
    var isOn = false
}

/// **1.13.** The indicator is a `Box`, so its fill animates under
/// `withAnimation` through `animatedBackground` (`DD-S`): mid-flight it is
/// neither `.surface` nor `.accent`, and it lands on `.accent`. M1k (the
/// indicator painted by `Toggle.paint` with `pass.fill`, not a `Box`) must
/// redden it.
@Test @MainActor func aTogglesIndicatorColourAnimatesUnderWithAnimation() throws {
    let model = AnimatedSwitch()
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        controlRoot { Toggle("Wi-Fi", isOn: Binding(get: { model.isOn }, set: { model.isOn = $0 })) }
    }
    let theme = Theme.light
    window.theme = theme
    func indicator() throws -> Hsla {
        let rect = try #require(window.lastScene.rects.first {
            $0.bounds.size.width == 14 && $0.bounds.size.height == 14
        }, "no 14×14 indicator rect")
        return Hsla(h: rect.background.h, s: rect.background.s, l: rect.background.l, a: rect.background.a)
    }
    func equal(_ a: Hsla, _ b: Hsla) -> Bool {
        abs(a.h - b.h) < 1e-4 && abs(a.s - b.s) < 1e-4 && abs(a.l - b.l) < 1e-4 && abs(a.a - b.a) < 1e-4
    }
    let surface = theme[.surface], accent = theme[.accent]
    try #require(!equal(surface, accent), "set up: the two tokens must differ")

    platform.simulateTick(timestamp: 100)
    #expect(equal(try indicator(), surface), "at rest off: .surface")
    withAnimation(.linear(duration: 1)) { model.isOn = true }
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    let mid = try indicator()
    #expect(!equal(mid, surface) && !equal(mid, accent),
            "mid-flight the fill is neither endpoint: \(mid) between \(surface) and \(accent)")
    platform.simulateTick(timestamp: 101.5)
    #expect(equal(try indicator(), accent), "landed on .accent")
}

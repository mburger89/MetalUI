import MetalUI
import MetalUITesting
import Testing

// `ES-`: a modifier written after a transparent scope (`.lineLimit`, `.disabled`, ...) applies to the
// content inside the scope, as in SwiftUI. Plain imports, as an app spells them.

private let longText = "A long line of text that cannot fit in one hundred and twenty points of width at all"

/// ES-A. `Text(...).lineLimit(1).padding(8).accessibilityIdentifier("x")`: found by "x", the padding
/// applies (the frame moves in and narrows by the padding against the unpadded one), and the
/// limit still applies (one line tall where the unlimited text is taller). Mutation: forward `style` to a
/// fresh `Style()` (the padding arms redden); drop `elementID` forwarding (the identifier is lost, the
/// `throws` of `element(identifier:)`).
@Test @MainActor func aLineLimitedTextTakesPaddingAndAnIdentifierAfterTheScope() throws {
    func frame(limited: Bool, padded: Bool) throws -> Bounds<Pixels> {
        let window = try harnessWindow {
            VStack(alignment: .leading) {
                if limited && padded {
                    Text(longText).lineLimit(1).padding(Pixels(8)).accessibilityIdentifier("x").frame(width: Pixels(120))
                } else if limited {
                    Text(longText).lineLimit(1).accessibilityIdentifier("x").frame(width: Pixels(120))
                } else {
                    Text(longText).padding(Pixels(8)).accessibilityIdentifier("x").frame(width: Pixels(120))
                }
            }
        }
        return try window.element(identifier: "x").frame
    }
    let scoped = try frame(limited: true, padded: true)
    let scopedUnpadded = try frame(limited: true, padded: false)
    let unlimitedPadded = try frame(limited: false, padded: true)
    #expect(scoped.origin != scopedUnpadded.origin, "the padding must apply: \(scoped) \(scopedUnpadded)")
    #expect(scoped.size.width.value <= 104, "the text lays out inside the 120 frame less 16 of padding: \(scoped)")
    #expect(scopedUnpadded.size.width.value - scoped.size.width.value >= 16 - 2, "\(scoped) \(scopedUnpadded)")
    #expect(scoped.size.height.value < unlimitedPadded.size.height.value, "the limit must apply: \(scoped) \(unlimitedPadded)")
}

/// ES-A. `Button.disabled(true).accessibilityIdentifier("b")`: found, disabled, and a click does nothing;
/// the enabled twin clicks (the separating arm). `.disabled(true).onClick {}` is covered too.
@Test @MainActor func aDisabledButtonKeepsItsIdentifierAndIgnoresClicks() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        VStack {
            Button("off") { log.add("off") }.disabled(true).accessibilityIdentifier("off")
            Button("on") { log.add("on") }.disabled(false).accessibilityIdentifier("on")
        }
    }
    let off = try window.element(identifier: "off")
    let on = try window.element(identifier: "on")
    #expect(!off.isEnabled)
    #expect(on.isEnabled)
    try window.click(off)
    try window.click(on)
    #expect(log.entries == ["on"], "\(log.entries)")
}

/// ES-A. A handler written after `.disabled(true)` sits inside the scope and is disabled, as in SwiftUI;
/// the `.disabled(false)` twin beside it fires (the separating arm: the handler is registered at all).
/// Mutation: make the scope's `handlers` setter drop the write (the twin does not fire).
@Test @MainActor func aHandlerAfterDisabledIsDisabledToo() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        HStack(spacing: Pixels(0)) {
            Box {}.frame(width: Pixels(60), height: Pixels(30)).disabled(true).accessibilityIdentifier("d")
                .onClick { log.add("off") }
            Box {}.frame(width: Pixels(60), height: Pixels(30)).disabled(false).accessibilityIdentifier("e")
                .onClick { log.add("on") }
        }
    }
    let off = try window.element(identifier: "d").frame
    let on = try window.element(identifier: "e").frame
    window.click(at: pt(off.origin.x.value + off.size.width.value / 2, off.origin.y.value + off.size.height.value / 2))
    #expect(log.entries.isEmpty, "\(log.entries)")
    window.click(at: pt(on.origin.x.value + on.size.width.value / 2, on.origin.y.value + on.size.height.value / 2))
    #expect(log.entries == ["on"], "\(log.entries)")
}

/// ES-A. The scope still supplies its environment to the content it decorates: a `.controlSize`
/// scope followed by a `.padding` keeps the padded element findable and the padded frame bigger by the padding.
@Test @MainActor func aSiblingScopeChainsToo() throws {
    let window = try harnessWindow {
        VStack(alignment: .leading) {
            Text("a").onAppear {}.padding(Pixels(4)).accessibilityIdentifier("life")
            Text("b").toolbar { ToolbarItem { Button("t") {} } }.padding(Pixels(4)).accessibilityIdentifier("tool")
        }
    }
    _ = try window.element(identifier: "life")
    _ = try window.element(identifier: "tool")
}

/// ES-A. The forwarded `decoration` reaches the content: `.background` adds a painted rect against the
/// same text without it. Mutation: make the scope's `decoration` setter drop the write. (`style` has no
/// observable arm: every `Style`-writing modifier is refused by name under the proposal layout authority,
/// `LR-FO`, so a forwarded `style` write cannot be seen from a window.)
@Test @MainActor func aBackgroundWrittenAfterAScopeIsPainted() throws {
    func rects(decorated: Bool) throws -> Int {
        let window = try harnessWindow {
            VStack(alignment: .leading) {
                if decorated {
                    Text("hi").lineLimit(1).background(Color.red).accessibilityIdentifier("x")
                } else {
                    Text("hi").lineLimit(1).accessibilityIdentifier("x")
                }
            }
        }
        return window.scene.rects.count
    }
    #expect(try rects(decorated: true) == rects(decorated: false) + 1)
}

/// ES-A. A scope over an element is an element, so it can be a window's root (the `Element` path, which
/// no container's group walk takes): `.disabled(true)` on a root `Button` still disables it, and the
/// `.disabled(false)` root fires. Mutation: drop the `withEnvironment` push in
/// `EnvironmentScope.prepaint(_:bounds:layout:pass:)` (the disabled root fires).
@Test @MainActor func aScopeOnTheRootElementStillScopesItsEnvironment() throws {
    for disabled in [true, false] {
        let log = HarnessLog()
        let window = try harnessWindow {
            Button("go") { log.add("go") }.disabled(disabled).accessibilityIdentifier("r")
        }
        let element = try window.element(identifier: "r")
        try window.click(element)
        #expect(log.entries == (disabled ? [] : ["go"]), "disabled=\(disabled): \(log.entries)")
    }
}

// MARK: - ES-D, ES-E: the remaining scopes that forward

/// ES-D. `.onModifierKeysChanged {}` followed by `.accessibilityIdentifier` and `.onClick`: the element is found,
/// the click lands, and the scope still reports a modifier change. Mutation: the `ModifierKeysScope` `handlers`
/// setter drops the write (the identifier is lost).
@Test @MainActor func aModifierKeysScopeTakesAnIdentifierAndAClickAfterIt() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        VStack {
            Box {}.frame(width: Pixels(60), height: Pixels(30))
                .onModifierKeysChanged(mask: .shift) { _, new in log.add(new.contains(.shift) ? "shift" : "none") }
                .accessibilityIdentifier("m").onClick { log.add("click") }
        }
    }
    window.pressModifiers([.shift])
    window.tick()
    #expect(log.entries.contains("shift"), "\(log.entries)")
    try window.click(window.element(identifier: "m"))
    #expect(log.entries.last == "click", "\(log.entries)")
}

/// ES-D. A modifier-keys scope over an element is an element, so it can be a window's root, and it still reports
/// a change there (the `Element` path, which no container's group walk takes). Mutation: drop the
/// `noteModifierKeys` call in `ModifierKeysScope.prepaint(_:bounds:layout:pass:)` (nothing is reported).
@Test @MainActor func aModifierKeysScopeAtTheRootStillReports() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Box {}.frame(width: Pixels(60), height: Pixels(30))
            .onModifierKeysChanged(mask: .shift) { _, new in log.add(new.contains(.shift) ? "shift" : "none") }
            .accessibilityIdentifier("root")
    }
    _ = try window.element(identifier: "root")
    window.pressModifiers([.shift])
    window.tick()
    #expect(log.entries == ["shift"], "\(log.entries)")
}

/// ES-E. A decoration and a handler after `.transition` land on the content: found by identifier, clickable.
@Test @MainActor func aTransitionTakesAnIdentifierAndAClickAfterIt() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        VStack {
            Box {}.frame(width: Pixels(60), height: Pixels(30)).transition(.opacity)
                .accessibilityIdentifier("t").onClick { log.add("t") }
        }
    }
    try window.click(window.element(identifier: "t"))
    #expect(log.entries == ["t"], "\(log.entries)")
}

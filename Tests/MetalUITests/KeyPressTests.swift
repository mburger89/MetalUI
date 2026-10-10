import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Key and focus scoping, lane A — SwiftUI's `onKeyPress` family in the key
// pipeline (rulings `KF-B`, `KF-C`, `KF-Q`, `KF-R`; spec
// `docs/superpowers/specs/2026-10-08-key-focus-design.md` §4.1, tests A1–A17,
// A36's stage arms, A38–A44). SwiftUI's answers are the probe
// `docs/probes/swiftui-key-focus.swift` arms named on each test.
//
// Windows are 200 × 200 over `FakePlatformWindow`; key events go in through
// `simulateInput`, exactly as a platform delivers them. Nothing sleeps. Red
// before: the stub commit's `onKeyPress` stores nothing (every handler is
// silent) — each test names what it read there.

// MARK: - Harness

private func kd(_ c: String, _ modifiers: Modifiers = [], repeating: Bool = false,
                characters: String? = nil) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: characters ?? c, modifiers: modifiers,
                      isRepeat: repeating, timestamp: 0))
}

private func ku(_ c: String) -> InputEvent {
    .keyUp(KeyEvent(charactersIgnoringModifiers: c, characters: c, timestamp: 0))
}

@MainActor private final class KPLog {
    var log: [String] = []
    var text: String
    var submits = 0
    var claims = true
    init(_ text: String = "") { self.text = text }
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private func square(_ side: Float = 20) -> some StyledElement {
    Box().frame(width: px(side), height: px(side))
}

@MainActor private func kpWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// Focuses the only focusable element (or the `index`th in Tab order) and draws.
@MainActor private func focusFirst(_ window: Window, _ index: Int = 0) throws {
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count > index, "set up: \(order.count) focusable elements")
    window.focus(order[index])
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == order[index], "set up: the element holds focus")
}

/// A one-field window: `TextField(text)` with `extra` applied, focused by Tab
/// (which selects the whole text, as AppKit's fields do).
@MainActor private func fieldWindow(_ model: KPLog,
                                    _ extra: @escaping @MainActor (TextField) -> TextField)
    throws -> (Window, FakePlatformWindow) {
    let (window, platform) = try kpWindow {
        Box { extra(TextField("t", text: model.text) { model.text = $0 }.onSubmit { model.submits += 1 }) }
    }
    platform.simulateInput(kd("\t"))
    window.drawFrameIfNeeded()
    try #require(window.focusedElement != nil, "set up: Tab focuses the field")
    return (window, platform)
}

// MARK: - A1–A5: focus-scoped, outermost first

/// **A1** (`KF-B`, `KF-C` item 3). A focused element's `onKeyPress` hears a
/// key down and claims it. Red before: the stub stores nothing (`[]`).
/// Mutation: delete the `dispatchKeyPress` call in the pipeline.
@MainActor
@Test func aFocusedElementsOnKeyPressHearsAKeyDown() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box { square().focusable().onKeyPress("x") { m.log.append("x"); return .handled } }
    }
    try focusFirst(window)
    #expect(platform.simulateInput(kd("x")), "the handler claims the key")
    #expect(m.log == ["x"], "the focused element's onKeyPress ran once: \(m.log)")
}

/// **A2** (K1s: keys need focus). With nothing focused (and no key region) an
/// `onKeyPress` hears nothing and the key reaches `onInput`. Green against
/// the stub by construction; mutation: walk every registered handler instead
/// of the chain.
@MainActor
@Test func anUnfocusedElementsOnKeyPressHearsNothing() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box { square().focusable().onKeyPress("x") { m.log.append("x"); return .handled } }
    }
    window.onInput = { event in
        if case .keyDown = event { m.log.append("input") }
        return false
    }
    #expect(window.focusedElement == nil)
    #expect(!platform.simulateInput(kd("x")))
    #expect(m.log == ["input"], "nothing focused: only the window's onInput hears it: \(m.log)")
}

/// **Divergence 186's pin** (K1, K1t: SwiftUI focuses a window's first
/// focusable view). MetalUI focuses nothing when a window first draws.
@MainActor
@Test func noElementHoldsFocusWhenTheWindowFirstDraws() throws {
    let (window, _) = try kpWindow { Box { square().focusable(); square().focusable() } }
    try #require(window.lastFocusRegistry.tabOrder.count == 2, "control: two focusable elements")
    #expect(window.focusedElement == nil, "no default focus (divergence 186)")
}

/// Three nested elements, each logging its name from an `onKeyPress` that
/// answers `answer(name)`; the inner one is focusable.
@MainActor private func threeLevels(_ m: KPLog, _ answer: @escaping (String) -> KeyPress.Result) -> some Element {
    Box {
        Box {
            square().focusable().onKeyPress { _ in m.log.append("inner"); return answer("inner") }
        }
        .onKeyPress { _ in m.log.append("mid"); return answer("mid") }
    }
    .onKeyPress { _ in m.log.append("root"); return answer("root") }
}

/// **A3** (K2t, K2v: `root,mid,inner`). The walk runs outermost first along
/// the focus chain — the opposite of `onKey`'s bubble. Red before: `[]`.
/// Mutation: iterate the key chain innermost first.
@MainActor
@Test func onKeyPressRunsOutermostFirstAlongTheFocusChain() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow { threeLevels(m) { _ in .ignored } }
    try focusFirst(window)
    #expect(!platform.simulateInput(kd("q")), "every handler ignored it")
    #expect(m.log == ["root", "mid", "inner"], "outermost first (K2v): \(m.log)")
}

/// **A4** (K2: a handled ancestor shadows the child). `mid` claims: `inner`
/// never hears. Red before: `[]`. Mutation: continue after `.handled`.
@MainActor
@Test func aHandledKeyPressStopsTheWalk() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow { threeLevels(m) { $0 == "mid" ? .handled : .ignored } }
    try focusFirst(window)
    #expect(platform.simulateInput(kd("q")), "mid claims the key")
    #expect(m.log == ["root", "mid"], "the walk stops at the claim: \(m.log)")
}

/// **A5** (K2w). On one element the later-written `onKeyPress` runs first —
/// the `StyledElement` arm, and lane C's `KeyboardModifier` arm (C7).
/// Red before: `[]`. Mutation: run one element's handlers in written order.
@MainActor
@Test func theLaterOnKeyPressOnOneElementRunsFirst() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box {
            square().focusable()
                .onKeyPress { _ in m.log.append("first"); return .ignored }
                .onKeyPress { _ in m.log.append("second"); return .ignored }
        }
    }
    try focusFirst(window)
    platform.simulateInput(kd("q"))
    #expect(m.log == ["second", "first"], "last written first (K2w): \(m.log)")

    // **C7** (lane C, `KF-H` item 2): the `KeyboardModifier` arm — two
    // `onKeyPress` on one proposal layer, the later-written first. Mutation:
    // `KeyboardModifier.addingKeyPress` prepends (runs the layer's handlers in
    // written order).
    let p = KPLog()
    let (proposal, proposalPlatform) = try kpWindow {
        HStack {
            Rectangle(width: px(20), height: px(20)).focusable()
                .onKeyPress { _ in p.log.append("first"); return .ignored }
                .onKeyPress { _ in p.log.append("second"); return .ignored }
        }
    }
    try focusFirst(proposal)
    proposalPlatform.simulateInput(kd("q"))
    #expect(p.log == ["second", "first"], "last written first on one keyboard layer (K2w): \(p.log)")
}

// MARK: - A6–A8: before the field's editing keys

/// **A6** (K4c). An `onKeyPress(.upArrow)` on a focused `TextField` claims ↑
/// ahead of the field: the selection (the whole text, from Tab) is unchanged,
/// so a typed `z` replaces all of it. Red before (and at `c62d6ba`): ↑ moves
/// the caret to the start and `z` reads `zabc`. Mutation: move
/// `dispatchKeyPress` after `dispatchTextKey`.
@MainActor
@Test func onKeyPressOnAFocusedTextFieldClaimsUpArrowAheadOfTheField() throws {
    let m = KPLog("abc")
    let (window, platform) = try fieldWindow(m) { $0.onKeyPress(.upArrow) { m.log.append("up"); return .handled } }
    #expect(platform.simulateInput(kd(TextEditing.upArrow)))
    platform.simulateInput(.textInput("z"))
    window.drawFrameIfNeeded()
    #expect(m.log == ["up"], "the handler heard ↑: \(m.log)")
    #expect(m.text == "z", "the selection was untouched, so z replaced it: \(m.text)")
}

/// **A7** (K4b, K4d). An ignored ↑ reaches the field: the caret moves to the
/// start and `z` is inserted there. Mutation: treat `.ignored` as claimed.
@MainActor
@Test func anIgnoredKeyPressLetsTheFieldEdit() throws {
    let m = KPLog("abc")
    let (window, platform) = try fieldWindow(m) { $0.onKeyPress(.upArrow) { m.log.append("up"); return .ignored } }
    platform.simulateInput(kd(TextEditing.upArrow))
    platform.simulateInput(.textInput("z"))
    window.drawFrameIfNeeded()
    #expect(m.log == ["up"], "the handler heard ↑: \(m.log)")
    #expect(m.text == "zabc", "the field moved the caret to the start: \(m.text)")
}

/// **A8** (K4g). A handled Return never submits the field. Red before: the
/// stub submits (`submits == 1`). Mutation: A6's.
@MainActor
@Test func aHandledReturnDoesNotSubmitTheField() throws {
    let m = KPLog("abc")
    let (window, platform) = try fieldWindow(m) { $0.onKeyPress(.return) { m.log.append("return"); return .handled } }
    #expect(platform.simulateInput(kd("\r")))
    _ = window
    #expect(m.log == ["return"] && m.submits == 0, "claimed before the field: \(m.log), submits \(m.submits)")
}

// MARK: - A9–A12: the stage's place, phases

private struct KPBump: Action {}

/// **A9** (`KF-C` item 3). A bound keymap action runs before `onKeyPress`: the
/// bound `x` reaches the action and not the handler; an unbound `y` reaches
/// the handler. Red before: `y` never heard. Mutation: swap `dispatchAction`
/// and `dispatchKeyPress`.
@MainActor
@Test func aBoundKeymapActionRunsBeforeOnKeyPress() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box {
            square().focusable().onKeyPress { press in m.log.append("kp \(press.characters)"); return .handled }
        }
        .onAction(KPBump.self) { _ in m.log.append("action") }
    }
    window.keymap = Keymap([KeyBinding("x", KPBump())])
    try focusFirst(window)
    platform.simulateInput(kd("x"))
    platform.simulateInput(kd("y"))
    #expect(m.log == ["action", "kp y"], "the keymap first, then onKeyPress: \(m.log)")
}

/// **A10** (K10, K11). `onKeyPress` runs before a `Button`'s plain-key
/// shortcut: a handled `k` never fires the button; an ignored `j` reaches it.
/// Red before: the button fires on `k`. Mutation: move `dispatchKeyPress`
/// after `dispatchShortcut`.
@MainActor
@Test func onKeyPressRunsBeforeAButtonShortcutAndAnIgnoredKeyReachesIt() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Row {
            square().focusable().onKeyPress { press in
                m.log.append("kp \(press.characters)")
                return press.characters == "k" ? .handled : .ignored
            }
            Button("K") { m.log.append("button k") }.keyboardShortcut("k", modifiers: [])
            Button("J") { m.log.append("button j") }.keyboardShortcut("j", modifiers: [])
        }
    }
    try focusFirst(window)
    platform.simulateInput(kd("k"))
    platform.simulateInput(kd("j"))
    #expect(m.log == ["kp k", "kp j", "button j"], "K10 then K11: \(m.log)")
}

/// A focusable square whose `onKeyPress` (with `phases`, if given) logs each
/// phase it hears and claims it.
@MainActor private func phaseLogger(_ m: KPLog, _ phases: KeyPress.Phases?) -> some Element {
    let log: @MainActor (KeyPress) -> KeyPress.Result = { press in
        m.log.append(press.phase == .down ? "down" : press.phase == .repeat ? "repeat" : press.phase == .up ? "up" : "?")
        return .handled
    }
    return Box {
        if let phases { square().focusable().onKeyPress(phases: phases, action: log) }
        else { square().focusable().onKeyPress(action: log) }
    }
}

/// **A11a** (K5a). The default phases are down and repeat: a down, a repeat
/// and an up deliver `down, repeat`. Red before: `[]`. Mutation: map every
/// key event to `.down` (ignore `isRepeat`/`keyUp`).
@MainActor
@Test func defaultPhasesAreDownAndRepeat() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow { phaseLogger(m, nil) }
    try focusFirst(window)
    platform.simulateInput(kd("a"))
    platform.simulateInput(kd("a", repeating: true))
    platform.simulateInput(ku("a"))
    #expect(m.log == ["down", "repeat"], "K5a: \(m.log)")
}

/// **A11b** (K5b). `.all` adds the release. Mutation: as A11a.
@MainActor
@Test func phasesAllAddsTheRelease() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow { phaseLogger(m, .all) }
    try focusFirst(window)
    platform.simulateInput(kd("a"))
    platform.simulateInput(kd("a", repeating: true))
    platform.simulateInput(ku("a"))
    #expect(m.log == ["down", "repeat", "up"], "K5b: \(m.log)")
}

/// **A11c** (K5c). A release-only handler hears only the release, through the
/// single-key `phases:` form. Mutation: as A11a.
@MainActor
@Test func aReleaseOnlyHandlerHearsOnlyTheRelease() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box { square().focusable().onKeyPress("a", phases: .up) { press in m.log.append("\(press.phase == .up)"); return .handled } }
    }
    try focusFirst(window)
    platform.simulateInput(kd("a"))
    platform.simulateInput(kd("a", repeating: true))
    platform.simulateInput(ku("a"))
    #expect(m.log == ["true"], "K5c: \(m.log)")
}

/// **A12**. An unclaimed key up still reaches the window's `onInput`, after the
/// handler heard it. Red before: the handler is silent (`["input up"]`).
/// Mutation: claim every key up in the stage.
@MainActor
@Test func anUnclaimedKeyUpStillReachesOnInput() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box { square().focusable().onKeyPress(phases: .all) { press in m.log.append("kp \(press.phase == .up ? "up" : "down")"); return .ignored } }
    }
    window.onInput = { event in
        if case .keyUp = event { m.log.append("input up") }
        return false
    }
    try focusFirst(window)
    platform.simulateInput(ku("a"))
    #expect(m.log == ["kp up", "input up"], "the handler ignored it; onInput hears it: \(m.log)")
}

// MARK: - A13–A15: matching

/// **A13** (K8). A key filter ignores modifiers but compares the character:
/// `a` and ⌘A fire `onKeyPress("a")`, ⇧A (which reports `A`) does not. Red
/// before: `[]`. Mutations: compare `key` case-insensitively (⇧A fires);
/// compare modifiers (⌘A silent).
@MainActor
@Test func aKeyFilterIgnoresModifiersButComparesTheCharacter() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box { square().focusable().onKeyPress("a") { m.log.append("a"); return .handled } }
    }
    try focusFirst(window)
    platform.simulateInput(kd("a"))
    platform.simulateInput(kd("a", [.command]))
    platform.simulateInput(kd("A", [.shift]))
    #expect(m.log == ["a", "a"], "a and cmd-a fire, shift-A does not (K8): \(m.log)")
}

/// **A14** (K7). A `characters:` filter tests the characters the key produced
/// (`KeyEvent.characters`), not the unmodified key: ⌥1 producing `¡` matches a
/// set holding `¡` and not `.decimalDigits`; a plain `1` matches the digits.
/// Red before: `[]`. Mutation: test `charactersIgnoringModifiers`.
@MainActor
@Test func aCharacterSetFilterTestsTheProducedCharacters() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box {
            square().focusable()
                .onKeyPress(characters: .decimalDigits) { press in m.log.append("digit \(press.characters)"); return .ignored }
                .onKeyPress(characters: CharacterSet(charactersIn: "¡")) { press in m.log.append("bang \(press.characters)"); return .ignored }
        }
    }
    try focusFirst(window)
    platform.simulateInput(kd("1", [.option], characters: "¡"))
    platform.simulateInput(kd("1"))
    #expect(m.log == ["bang ¡", "digit 1"], "matched on the produced characters (K7): \(m.log)")
}

/// **A15** (K6). A `keys:` filter hears only its keys. Red before: `[]`.
/// Mutation: ignore the set.
@MainActor
@Test func aKeysSetFilterHearsOnlyItsKeys() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box {
            square().focusable().onKeyPress(keys: [.upArrow, .downArrow]) { press in
                m.log.append(press.key == .upArrow ? "up" : "down")
                return .handled
            }
        }
    }
    try focusFirst(window)
    platform.simulateInput(kd(TextEditing.upArrow))
    platform.simulateInput(kd(TextEditing.downArrow))
    platform.simulateInput(kd(TextEditing.leftArrow))
    #expect(m.log == ["up", "down"], "K6: \(m.log)")
}

// MARK: - A16–A17: dispatch and gates

/// A focusable square whose `onKeyPress` counts into its own `@State`, drawn
/// as a bar `10 + 10 × count` wide and 7 tall.
private struct KPCounter: Component {
    @State var count = 0
    var content: some ElementGroup {
        Box().frame(width: px(10 + 10 * Float(count)), height: px(7)).background(.accent).focusable()
            .onKeyPress("x") { count += 1; return .handled }
    }
}

/// **A16** (ID-F, `KF-B` item 5). One counter value placed twice: the pressed
/// (focused) occurrence's `@State` changes — the first, which is not the last
/// bound. Red before: neither changes. Mutation: drop
/// `StateDispatch.dispatching(to:)` (the last-bound occurrence counts).
@MainActor
@Test func onKeyPressWritesStateOnItsOwnElement() throws {
    let (window, platform) = try kpWindow {
        let counter = KPCounter()
        return Row { counter; counter }
    }
    try focusFirst(window, 0)
    platform.simulateInput(kd("x"))
    for _ in 0..<3 { window.drawFrameIfNeeded() }
    let widths = window.lastScene.rects.filter { $0.bounds.size.height == 7 }.map { $0.bounds.size.width }
    #expect(widths == [20, 10], "the focused (first) occurrence counted: \(widths)")
}

/// **A17** (`KF-I`; EV-F's gate). A disabled ancestor's `onKeyPress` is silent
/// while its re-enabled, focused child's runs; a hidden element's never
/// registers. Red before: the child is silent too. Mutation: register the
/// key presses outside the gate.
@MainActor
@Test func aDisabledOrHiddenElementsOnKeyPressIsSilent() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Row {
            Box {
                square().focusable().onKeyPress { _ in m.log.append("child"); return .ignored }
                    .environment(\.isEnabled, true)
            }
            .onKeyPress { _ in m.log.append("disabled parent"); return .handled }
            .disabled(true)
            square().focusable().onKeyPress { _ in m.log.append("hidden"); return .handled }.hidden()
        }
    }
    try #require(window.lastFocusRegistry.tabOrder.count == 1, "set up: only the re-enabled child is focusable")
    try focusFirst(window)
    platform.simulateInput(kd("q"))
    #expect(m.log == ["child"], "the disabled ancestor stays silent: \(m.log)")
    #expect(window.lastFocusRegistry.keyPressCount == 1, "only the child registered its handlers")
}

// MARK: - A38–A42: typed characters on a focused field (`KF-Q`)

/// **A38** (K4a, `KF-Q`). A handled typed character on a focused field is
/// never typed. Red before: `z` typed (`abcz`). Mutation: delete the
/// `.textInput` arm.
@MainActor
@Test func aHandledKeyPressSwallowsATypedCharacterInAFocusedField() throws {
    let m = KPLog("abc")
    let (window, platform) = try fieldWindow(m) { $0.onKeyPress("z") { m.log.append("z"); return .handled } }
    platform.simulateInput(kd(TextEditing.end))
    #expect(platform.simulateInput(.textInput("z")), "claimed")
    window.drawFrameIfNeeded()
    #expect(m.log == ["z"] && m.text == "abc", "nothing typed: \(m.log) \(m.text)")
}

/// **A39** (K4b). An ignored typed character is typed. Mutation: treat
/// `.ignored` as claimed on the `.textInput` arm.
@MainActor
@Test func anIgnoredKeyPressLetsATypedCharacterIn() throws {
    let m = KPLog("abc")
    let (window, platform) = try fieldWindow(m) { $0.onKeyPress("z") { m.log.append("z"); return .ignored } }
    platform.simulateInput(kd(TextEditing.end))
    platform.simulateInput(.textInput("z"))
    window.drawFrameIfNeeded()
    #expect(m.log == ["z"] && m.text == "abcz", "heard, then typed: \(m.log) \(m.text)")
}

/// **A40** (K2x). An ancestor's `onKeyPress` hears a typed character before the
/// field's own. Red before: `[]`. Mutation: walk innermost first on the
/// `.textInput` arm.
@MainActor
@Test func anAncestorsKeyPressHearsTypedCharactersBeforeTheFieldsOwn() throws {
    let m = KPLog("abc")
    let (window, platform) = try kpWindow {
        Box {
            TextField("t", text: m.text) { m.text = $0 }
                .onKeyPress { _ in m.log.append("field"); return .ignored }
        }
        .onKeyPress { _ in m.log.append("anc"); return .ignored }
    }
    platform.simulateInput(kd("\t"))
    window.drawFrameIfNeeded()
    m.log = []
    platform.simulateInput(.textInput("q"))
    #expect(m.log == ["anc", "field"], "outermost first on the typed arm: \(m.log)")
}

/// **A41** (`KF-Q` items 2 and 4, divergence 187). A composition's commit and a
/// multi-grapheme commit are never offered; a single typed character arrives
/// as `.down` with no modifiers, and no `.up` follows it unless the platform
/// sends a key up (SDL drops the text-producing one). Red before: `[]` for the
/// offered arm. Mutation: offer every `.textInput`.
@MainActor
@Test func aCompositionAndAMultiGraphemeCommitAreNeverOffered() throws {
    let m = KPLog("")
    let (window, platform) = try fieldWindow(m) {
        $0.onKeyPress(phases: .all) { press in
            m.log.append("\(press.characters) \(press.phase == .down ? "down" : "other") \(press.modifiers.isEmpty)")
            return .ignored
        }
    }
    platform.simulateInput(.textComposition(TextComposition(text: "k", selection: 1..<1)))
    platform.simulateInput(.textInput("か"))
    platform.simulateInput(.textInput("ab"))
    #expect(m.log.isEmpty, "a composition commit and a two-grapheme commit are not offered: \(m.log)")
    platform.simulateInput(.textInput("z"))
    window.drawFrameIfNeeded()
    #expect(m.log == ["z down true"], "one grapheme: .down, no modifiers, no .up (divergence 187): \(m.log)")
    #expect(m.text == "かabz", "every commit typed: \(m.text)")
}

/// **A42** (`KF-Q` item 5). A digit filter on a field keeps only digits:
/// typing `a1b2` leaves `12`. Red before: `a1b2`. Mutation: A38's.
@MainActor
@Test func aDigitFilterOnAFieldKeepsOnlyDigits() throws {
    let m = KPLog("")
    let (window, platform) = try fieldWindow(m) {
        $0.onKeyPress(characters: CharacterSet.decimalDigits.inverted) { _ in .handled }
    }
    for c in ["a", "1", "b", "2"] { platform.simulateInput(.textInput(c)) }
    window.drawFrameIfNeeded()
    #expect(m.text == "12", "letters swallowed, digits typed: \(m.text)")
}

// MARK: - A43–A44: ⌘-keys against commands and shortcuts (`KF-R` item 3)

/// **A43** (`KF-R` item 3, first row; ruling `KF-X`: KX2 and KX3 read `menu`).
/// The app's ⌘J command runs and a focused `onKeyPress("j")` never hears ⌘J,
/// whether it would answer `.handled` or `.ignored`; a catch-all
/// `onKeyPress { .handled }` does not swallow it either. A ⌘-key no command
/// binds (⌘K) still reaches the handler — the separating arm. Red before (the
/// fourth row's order): the handler hears ⌘J and a handled one runs no
/// command. Mutation: drop the command-table decline in `dispatchKeyPress`.
@MainActor
@Test func aCommandsKeystrokeRunsTheCommandNotOnKeyPress() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Box {
            square().focusable()
                .onKeyPress("j") { m.log.append("kp-j"); return m.claims ? .handled : .ignored }
                .onKeyPress { press in m.log.append("all-\(press.characters)"); return .handled }
        }
    }
    let command: @MainActor @Sendable () -> Void = { m.log.append("command") }
    window.commandShortcuts = { [(KeyboardShortcut("j"), command)] }
    try focusFirst(window)
    platform.simulateInput(kd("j", [.command]))
    m.claims = false
    platform.simulateInput(kd("j", [.command]))
    #expect(m.log == ["command", "command"], "the command runs; no onKeyPress hears ⌘J: \(m.log)")
    m.log = []
    platform.simulateInput(kd("k", [.command]))
    #expect(m.log == ["all-k"], "a ⌘-key no command binds reaches onKeyPress: \(m.log)")
}

/// **A44** (`KF-R` item 3, third row for a `Button`; ruling `KF-X`: KX1 reads
/// `view:k[down+cmd]`, no `button`). A focused `onKeyPress` hears ⌘K before
/// a ⌘K `Button` shortcut. Red before: the button runs. Mutation: decline a
/// keystroke a modified `Button` shortcut matches (KX1's "button" row).
@MainActor
@Test func aModifiedButtonShortcutReachesOnKeyPressBeforeTheButton() throws {
    let m = KPLog()
    let (window, platform) = try kpWindow {
        Row {
            square().focusable().onKeyPress("k") { m.log.append("kp"); return m.claims ? .handled : .ignored }
            Button("K") { m.log.append("button") }.keyboardShortcut("k")
        }
    }
    try focusFirst(window)
    platform.simulateInput(kd("k", [.command]))
    m.claims = false
    platform.simulateInput(kd("k", [.command]))
    #expect(m.log == ["kp", "kp", "button"], "onKeyPress first; an ignored ⌘K reaches the button: \(m.log)")
}

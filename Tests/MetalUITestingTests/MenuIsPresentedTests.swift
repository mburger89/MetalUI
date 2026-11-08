import MetalUI
import MetalUITesting
import Observation
import Testing

// Alloy gap G9 (ruling `MN-AK`, record 241): `Menu(isPresented:)` / `.menuPresented(_:)` open a pull-down from
// code, natively and drawn. PLAIN imports. Every test runs both ways (`presentsMenusNatively` true and false).

@Observable @MainActor private final class ComposerModel {
    var open = false
    var log: [String] = []
    var writes: [Bool] = []
    var binding: Binding<Bool> {
        Binding(get: { self.open }, set: { self.writes.append($0); self.open = $0 })
    }
}

/// The composer: a button standing for typing `/model`, and the model `Menu` driven by the binding.
@MainActor private func composer(_ m: ComposerModel, enabled: Bool = true) -> some Element {
    VStack(alignment: .leading, spacing: 8) {
        Button("Slash") { m.open = true }
        Menu("Model", isPresented: m.binding) {
            Button("Sonnet") { m.log.append("sonnet") }
            Button("Opus") { m.log.append("opus") }
        }
        .disabled(!enabled)
    }
}

private let modes: [Bool] = [true, false]

@MainActor private func window(_ native: Bool, size: Size<Pixels> = sz(400, 300),
                               _ content: @escaping @MainActor () -> some Element) throws -> TestWindow {
    try harnessWindow(size: size, options: .init(presentsMenusNatively: native), content)
}

/// Whether a menu is up: the platform's, or the window's drawn items.
@MainActor private func isOpen(_ w: TestWindow, native: Bool) throws -> Bool {
    native ? w.presentedMenu != nil
        : try !w.elements { $0.role == .menuItem }.isEmpty
}

/// Where the menu opened: the platform's pop-up point, or the drawn first row's origin.
@MainActor private func openedAt(_ w: TestWindow, native: Bool) throws -> Point<Pixels> {
    if native { return try #require(w.platformWindow.presentedMenus.last).at }
    return try #require(w.elements { $0.role == .menuItem }.first).frame.origin
}

/// Writing `true` from a button's action opens the menu where a click on its label does; both go through the same
/// anchor. Mutation: `reconcileMenuBindings` not called (the first expectation); the anchor read from another table.
@Test(arguments: modes) @MainActor func writingTrueFromAnActionOpensTheMenuAtTheLabelsAnchor(native: Bool) throws {
    let m = ComposerModel()
    let w = try window(native) { composer(m) }
    #expect(try !isOpen(w, native: native))
    try w.click(w.element(label: "Slash"))
    #expect(try isOpen(w, native: native), "opened by the binding")
    let byBinding = try openedAt(w, native: native)

    let clicked = ComposerModel()
    let c = try window(native) { composer(clicked) }
    try c.click(c.element(label: "Model"))
    #expect(try isOpen(c, native: native))
    let byClick = try openedAt(c, native: native)
    #expect(byBinding == byClick, "the same anchor: \(byBinding) vs \(byClick)")
    let label = try w.element(label: "Model").frame
    #expect(abs(byBinding.y.value - (label.origin.y.value + label.size.height.value)) < 1.01 || !native && byBinding.y.value > label.origin.y.value)
    #expect(m.writes.isEmpty, "opening wrote nothing: the binding was already true")
}

/// Choosing an item runs it and writes `false`. Mutation: `menuSessionDidChange` removed (the binding stays `true`).
@Test(arguments: modes) @MainActor func choosingAnItemRunsItAndWritesFalse(native: Bool) throws {
    let m = ComposerModel()
    let w = try window(native) { composer(m) }
    try w.click(w.element(label: "Slash"))
    #expect(m.open)
    if native {
        try w.chooseMenuItem("Opus")
    } else {
        try w.click(w.element(label: "Opus"))
    }
    #expect(m.log == ["opus"])
    #expect(!m.open, "any dismissal writes false")
    #expect(m.writes == [false])
    #expect(try !isOpen(w, native: native))
}

/// Dismissing with no choice (the native menu closing, Escape on the drawn one) writes `false`. Mutation: as above.
@Test(arguments: modes) @MainActor func dismissalWritesFalse(native: Bool) throws {
    let m = ComposerModel()
    let w = try window(native) { composer(m) }
    try w.click(w.element(label: "Slash"))
    #expect(try isOpen(w, native: native))
    if native { try w.dismissMenu() } else { w.typeKey(.escape) }
    #expect(!m.open)
    #expect(m.log.isEmpty)
    #expect(try !isOpen(w, native: native))
    // And it opens again: the second write is a fresh open.
    try w.click(w.element(label: "Slash"))
    #expect(try isOpen(w, native: native))
}

/// An outside press on the drawn menu dismisses it and writes `false`.
@Test @MainActor func anOutsidePressOnTheDrawnMenuWritesFalse() throws {
    let m = ComposerModel()
    let w = try window(false) { composer(m) }
    try w.click(w.element(label: "Slash"))
    #expect(try isOpen(w, native: false))
    w.click(at: pt(380, 280))
    #expect(!m.open)
    #expect(try !isOpen(w, native: false))
}

/// Writing `false` while the menu is open closes it. Mutation: the close branch of `reconcileMenuBindings` removed.
@Test(arguments: modes) @MainActor func writingFalseDismissesAnOpenMenu(native: Bool) throws {
    let m = ComposerModel()
    let w = try window(native) { composer(m) }
    try w.click(w.element(label: "Slash"))
    #expect(try isOpen(w, native: native))
    let token = native ? w.presentedMenu?.token : nil
    m.open = false
    w.tick()
    #expect(try !isOpen(w, native: native))
    if native {
        #expect(w.platformWindow.dismissedPresentations.contains(try #require(token)), "the platform was told")
    }
    #expect(m.writes.isEmpty, "the binding was written by the caller only")
}

/// A click on the label sets the binding; the label while open keeps it in step.
/// Mutation: the click path not passing `isPresented` (the first expectation).
@Test(arguments: modes) @MainActor func clickingTheLabelSetsTrue(native: Bool) throws {
    let m = ComposerModel()
    let w = try window(native) { composer(m) }
    try w.click(w.element(label: "Model"))
    #expect(m.open)
    #expect(try isOpen(w, native: native))
    if native {
        try w.dismissMenu()
    } else {
        w.typeKey(.escape)
    }
    #expect(!m.open)
    #expect(m.writes == [true, false])
}

/// A menu in a `ViewThatFits` candidate: the chosen one opens, an unchosen one with its binding `true` does not.
/// Mutation: no `fitNotes` entry in `notePresentation` for the menu's record (the second expectation).
@Test(arguments: modes) @MainActor func aMenuInAViewThatFitsCandidateStillWorks(native: Bool) throws {
    let m = ComposerModel()
    let other = ComposerModel()
    let w = try window(native, size: sz(300, 100)) {
        VStack(alignment: .leading, spacing: 4) {
            Button("Slash") { m.open = true }
            ViewThatFits(in: .horizontal) {
                Menu("Wide", isPresented: other.binding) { Button("W") {} }.frame(width: Pixels(500))
                Menu("Model", isPresented: m.binding) { Button("Sonnet") {} }.frame(width: Pixels(120))
            }
        }
    }
    other.open = true
    w.tick()
    #expect(try !isOpen(w, native: native), "the unchosen candidate's menu does not open")
    #expect(other.open && other.writes.isEmpty, "its binding is left alone: no open was attempted, none written back")
    try w.click(w.element(label: "Slash"))
    #expect(try isOpen(w, native: native), "the chosen candidate's menu opens")
}

/// A menu that cannot open (disabled) writes `false` back rather than leaving the binding lying.
@Test(arguments: modes) @MainActor func aDisabledMenuWritesFalseBack(native: Bool) throws {
    let m = ComposerModel()
    let w = try window(native) { composer(m, enabled: false) }
    try w.click(w.element(label: "Slash"))
    #expect(try !isOpen(w, native: native))
    #expect(!m.open)
}

/// `.menuPresented(_:)` on a built `Menu` is the same as the initialiser.
@Test(arguments: modes) @MainActor func theModifierIsTheSameAsTheInitialiser(native: Bool) throws {
    let m = ComposerModel()
    let w = try window(native) {
        VStack {
            Button("Slash") { m.open = true }
            Menu("Model") { Button("Sonnet") {} }.menuPresented(m.binding)
        }
    }
    try w.click(w.element(label: "Slash"))
    #expect(try isOpen(w, native: native))
    if native { try w.dismissMenu() } else { w.typeKey(.escape) }
    #expect(!m.open)
}

/// The `Menu` leaving the tree while its menu is open closes it and writes `false`.
@Test(arguments: modes) @MainActor func aMenuThatLeavesTheTreeIsClosed(native: Bool) throws {
    let m = ComposerModel()
    let shown = ComposerModel()
    shown.open = true
    let w = try window(native) {
        VStack {
            Button("Slash") { m.open = true }
            if shown.open { Menu("Model", isPresented: m.binding) { Button("Sonnet") {} } }
        }
    }
    try w.click(w.element(label: "Slash"))
    #expect(try isOpen(w, native: native))
    shown.open = false
    w.tick()
    #expect(try !isOpen(w, native: native))
    #expect(!m.open)
}

import Foundation
import MetalUI
import MetalUITesting
import Observation
import Testing

// `ViewThatFits` in a window (`VF-A`..`VF-J`, record 217; probe `docs/probes/swiftui-view-that-fits.swift`, whose arm
// ids are quoted): only the chosen candidate is interactive, visible and alive; the others are built and nothing more.
// Portable (a plain import of `MetalUI` and `MetalUITesting`, text through `harnessTextSystem`), counts and logs, never
// time. The kernel's side is `MetalUILayoutTests/FirstFittingTests.swift`.

/// A candidate: a button `width` wide with its own `@State`, a keyboard shortcut and lifecycle logs.
private struct FitRow: Component {
    let tag: String
    let width: Float
    let key: KeyEquivalent
    let log: HarnessLog
    @State var n = 0
    var content: some ElementGroup {
        Button("\(tag) \(n)") { n += 1; log.add("fire \(tag) \(n)") }
            .keyboardShortcut(key)
            .frame(width: Pixels(width), height: Pixels(20))
            .onAppear { log.add("appear \(tag) n=\(n)") }
            .onDisappear { log.add("disappear \(tag)") }
    }
}

/// `A(400, a)`, `B(150, b)`, `C(10, c)`, as the probe's `S0`/`K1` arms.
@MainActor private func threeCandidates(_ log: HarnessLog, keys: [KeyEquivalent] = ["a", "b", "c"]) -> some Element {
    ViewThatFits(in: .horizontal) {
        FitRow(tag: "A", width: 400, key: keys[0], log: log)
        FitRow(tag: "B", width: 150, key: keys[1], log: log)
        FitRow(tag: "C", width: 10, key: keys[2], log: log)
    }
}

@MainActor private func labels(_ window: TestWindow) throws -> [String] {
    try window.elements(role: .button).compactMap(\.label)
}

/// `K1`, `K4`: a candidate that is not chosen registers no shortcut. At 300 wide `B` is chosen: `a` and `c` fire nothing,
/// `b` fires `B`; with three candidates sharing one key the shortcut fires **once** (the chosen one), not three times.
/// Mutation: deleting the elision check in `Element.prepaintGroup` (`ElementGroup.swift`) reddens both (a, c and the
/// shared key fire from the unchosen candidates).
@Test @MainActor func anUnchosenCandidatesShortcutDoesNotFire() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(300, 100)) { threeCandidates(log) }
    window.typeKey("a", modifierFlags: .primary)
    window.typeKey("c", modifierFlags: .primary)
    #expect(log.entries.filter { $0.hasPrefix("fire") }.isEmpty, "K1: the unchosen candidates' keys fire nothing: \(log.entries)")
    window.typeKey("b", modifierFlags: .primary)
    window.typeKey("b", modifierFlags: .primary)
    #expect(log.entries.filter { $0.hasPrefix("fire") } == ["fire B 1", "fire B 2"], "K1 positive control: the chosen key fires, counting")

    let shared = HarnessLog()
    let sharedWindow = try harnessWindow(size: sz(300, 100)) { threeCandidates(shared, keys: ["g", "g", "g"]) }
    sharedWindow.typeKey("g", modifierFlags: .primary)
    #expect(shared.entries.filter { $0.hasPrefix("fire") } == ["fire B 1"], "K4: three candidates sharing a key fire once: \(shared.entries)")
}

/// `AX0`, `AX1`: only the chosen candidate's button is an accessibility node; elements below an unchosen candidate are
/// not prepainted at all (`elementPrepaints` equals a tree holding only the chosen candidate's). Mutation: as above.
@Test @MainActor func onlyTheChosenCandidateIsAnAccessibilityNodeOrAHitbox() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(300, 100)) { threeCandidates(log) }
    #expect(try labels(window) == ["B 0"], "AX0")
    let alone = try harnessWindow(size: sz(300, 100)) {
        ViewThatFits(in: .horizontal) { FitRow(tag: "B", width: 150, key: "b", log: HarnessLog()) }
    }
    #expect(window.lastFrameWork.elementPrepaints == alone.lastFrameWork.elementPrepaints,
            "the unchosen candidates' elements are not prepainted: \(window.lastFrameWork.elementPrepaints) vs \(alone.lastFrameWork.elementPrepaints)")
    #expect(window.lastFrameWork.elementPaints == alone.lastFrameWork.elementPaints, "and not painted")
    #expect(window.scene.rects.count == alone.scene.rects.count && window.scene.glyphs.count == alone.scene.glyphs.count)
    window.resize(to: sz(50, 100))
    #expect(try labels(window) == ["C 0"], "AX1: narrow, the fallback is the only button")
}

/// `S0`, `R1`, `R2`, `R3`: lifecycle runs only for the chosen candidate, and a switch is an appearance and a disappearance.
/// **The order is MetalUI's** (`LC-F`: appearances before disappearances); SwiftUI's probe read `disappear(B) appear(C)`
/// (`R1`), the lifecycle rule's own difference and not this view's. Mutation: skipping `LifecycleStore.retract` in `applyFitChoices` reddens the `appear` assertions (every
/// candidate appears).
@Test @MainActor func lifecycleRunsOnlyForTheChosenCandidate() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(300, 100)) { threeCandidates(log) }
    #expect(log.entries == ["appear B n=0"], "S0: only B appears: \(log.entries)")
    log.entries = []
    window.resize(to: sz(50, 100))
    #expect(log.entries == ["appear C n=0", "disappear B"], "R1: \(log.entries)")
    log.entries = []
    window.resize(to: sz(300, 100))
    #expect(log.entries == ["appear B n=0", "disappear C"], "R2: \(log.entries)")
    log.entries = []
    window.resize(to: sz(500, 100))
    #expect(log.entries == ["appear A n=0", "disappear B"], "R3: \(log.entries)")
}

/// `R2`: a candidate's `@State` survives a switch (the candidates are built every frame under the view's id, so their
/// state is live): `B` is pressed three times, the window narrows and widens, and `B` shows 3 and the next press 4.
@Test @MainActor func stateSurvivesASwitchBetweenCandidates() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(300, 100)) { threeCandidates(log) }
    for _ in 0..<3 { window.typeKey("b", modifierFlags: .primary) }
    #expect(try labels(window) == ["B 3"])
    window.resize(to: sz(50, 100))
    window.resize(to: sz(300, 100))
    #expect(try labels(window) == ["B 3"], "the state came back with the candidate")
    window.typeKey("b", modifierFlags: .primary)
    #expect(try labels(window) == ["B 4"])
    #expect(log.entries.last == "fire B 4")
}

// MARK: - Labels, resizes

private let moreLabel = "More"

@MainActor @Observable private final class MirrorModel {
    var mirrored = false
}

/// `{ HStack { Text(label); Text("Other tool") }; Text("More") }`, the probe's `T` arms.
private struct MirrorBar: Component {
    let model: MirrorModel
    var content: some ProposalElementGroup {
        ViewThatFits(in: .horizontal) {
            HStack { Text(model.mirrored ? "Mirror \u{2713}" : "Mirror"); Text("Other tool") }.id("wide")
            Text(moreLabel).id("more")
        }
    }
}

/// `T1`..`T4`, `WR0`..`WR2`: a resize and a label change both switch candidates. The wide row's width is read from a
/// window that holds it alone; the window is then midway between the `Mirror` row and the wider `Mirror ✓` row, so `Mirror` fits and
/// `Mirror ✓` does not: toggling the label switches to `More` and back, and so does a resize.
@Test @MainActor func aResizeAndALabelChangeSwitchCandidates() throws {
    func wideWidth(_ label: String) throws -> Float {
        let measure = try harnessWindow(size: sz(600, 100)) { VStack { HStack { Text(label); Text("Other tool") }.id("wide") } }
        return try measure.frame(ofID: "wide").size.width.value
    }
    let narrowRow = try wideWidth("Mirror"), wideRow = try wideWidth("Mirror \u{2713}")
    try #require(wideRow > narrowRow + 1, "set up: the check mark widens the row")
    let model = MirrorModel()
    let width = (narrowRow + wideRow) / 2   // between the two rows, so neither rounding nor a platform's glyph widths decide
    let window = try harnessWindow(size: sz(width, 100)) { VStack { MirrorBar(model: model) } }
    func shown() throws -> String { (try? window.frame(ofID: "wide")) != nil ? "wide" : "more" }
    #expect(try shown() == "wide", "T1: the Mirror row fits")
    model.mirrored = true
    window.tick()
    #expect(try shown() == "more", "T2: \"Mirror \u{2713}\" does not fit: More")
    model.mirrored = false
    window.tick()
    #expect(try shown() == "wide", "T3: and back")
    window.resize(to: sz(narrowRow - 5, 100))
    #expect(try shown() == "more", "WR1: narrower")
    window.resize(to: sz(600, 100))
    #expect(try shown() == "wide", "WR2: and wider again")
}

// MARK: - What an unchosen candidate does not do

/// A candidate with every build-time and prepaint-time modifier: `.onChange`, `.task`, `.onGeometryChange`, an alert.
private struct EventfulRow: Component {
    let tag: String
    let width: Float
    let presents: Bool
    let log: HarnessLog
    @State var value = 0
    @State var shown = false
    var content: some ElementGroup {
        Text(tag).frame(width: Pixels(width), height: Pixels(20))
            .onChange(of: value) { _, new in log.add("onChange \(tag) \(new)") }
            .task { log.add("task \(tag)") }
            .onGeometryChange(for: Float.self, of: { Float($0.size.width.value) }) { log.add("geometry \(tag) \(Int($0))") }
            .alert("Alert \(tag)", isPresented: $shown) { Button("OK") {} }
            .onAppear { log.add("appear \(tag)"); value = 1; if presents { shown = true } }
    }
}

@MainActor private func eventful(_ log: HarnessLog) -> some Element {
    ViewThatFits(in: .horizontal) {
        EventfulRow(tag: "wide", width: 400, presents: true, log: log)
        EventfulRow(tag: "mid", width: 150, presents: false, log: log)
    }
}

/// `X0`..`X2`: in an unchosen candidate no `.onChange`, `.task`, `onGeometryChange` or alert runs; once it is chosen they
/// all do. The wide candidate is the one that presents an alert, so a presented alert at 300 wide would be the unchosen
/// candidate's. Mutations: skipping `retract` reddens the `onChange`/`task`/`appear` and alert arms; the `GeometryChangeScope`
/// elision guard (`allElided`/`isElided` filter) reddens the geometry arm alone.
@Test @MainActor func unchosenCandidatesRunNoLifecycleOrGeometryOrPresentation() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(300, 100)) { eventful(log) }
    #expect(log.entries.filter { $0.contains("wide") }.isEmpty, "X0: nothing of the wide candidate ran: \(log.entries)")
    #expect(Set(log.entries) == ["geometry mid 150", "task mid", "appear mid", "onChange mid 1"], "X1: the chosen candidate's did: \(log.entries)")
    #expect(window.presentedAlert == nil, "X0: the unchosen candidate's alert is not presented")
    log.entries = []
    window.resize(to: sz(600, 100))
    #expect(Set(log.entries.filter { $0.contains("wide") }) == ["geometry wide 400", "task wide", "appear wide", "onChange wide 1"],
            "X2: chosen, the candidate's all run: \(log.entries)")
    #expect(window.presentedAlert?.title == "Alert wide", "X2: and its alert is presented")
}

/// `X3`, the control: the same alert outside a `ViewThatFits` presents (so `presentedAlert == nil` above is the elision's).
@Test @MainActor func theSameAlertOutsideAViewThatFitsPresents() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(300, 100)) {
        VStack { EventfulRow(tag: "wide", width: 400, presents: true, log: log) }
    }
    #expect(window.presentedAlert?.title == "Alert wide")
}

// MARK: - Focus

/// A wide candidate holding a focused-able `TextField`, a narrow one a `Text`.
@MainActor private func focusTree(_ text: Binding<String>) -> some Element {
    ViewThatFits(in: .horizontal) {
        TextField("t", text: text).frame(width: Pixels(200), height: Pixels(20)).id("field")
        Text("narrow").frame(width: Pixels(50), height: Pixels(20))
    }
}

/// `FO0`..`FO2`: a focused control in a candidate that stops being chosen loses focus, and does not regain it when the
/// candidate returns. Mutation: dropping the `elidedIDs` test in `Frame.resolveFocus` leaves the window's focus on the
/// elided field (the third expectation).
@Test @MainActor func focusInACandidateThatIsNoLongerChosenIsCleared() throws {
    var text = ""
    let window = try harnessWindow(size: sz(300, 100)) { focusTree(Binding(get: { text }, set: { text = $0 })) }
    window.clearTheFirstDrawSeat()
    #expect(window.window.focusedElement == nil, "set up: nothing is focused")
    window.click(at: pt(150, 50))
    #expect(window.window.focusedElement != nil, "FO0: the field is focused")
    window.resize(to: sz(100, 100))
    #expect(window.window.focusedElement == nil, "FO1: the narrow candidate is chosen and the focus is gone")
    window.resize(to: sz(300, 100))
    #expect(window.window.focusedElement == nil, "FO2: the field is back and not focused again")
}

// MARK: - Window metadata, the pin for divergence 219

/// Divergence 219 (pinned): a `navigationTitle` in an unchosen candidate still titles the window, because the title is
/// collected at build time and the first writer wins (SwiftUI's side is inferred from `X0`'s alert, not measured). Flip
/// this when the divergence is retired.
@Test @MainActor func aNavigationTitleInAnUnchosenCandidateStillTitlesTheWindow() throws {
    let window = try harnessWindow(size: sz(300, 100)) {
        ViewThatFits(in: .horizontal) {
            Text("wide").frame(width: Pixels(400), height: Pixels(20)).navigationTitle("From the unchosen candidate")
            Text("narrow").frame(width: Pixels(50), height: Pixels(20))
        }
    }
    #expect(window.title == "From the unchosen candidate", "219: the unchosen candidate's title applies")
}

// MARK: - The spacing edge

/// The gap between the first item and the second of `VStack { Text("T"); second }` in a 100 x 200 window, `second` identified `"u"`.
@MainActor private func gapBelowText<Second: ProposalElementGroup>(
    @ProposalContentBuilder _ second: @escaping @MainActor () -> Second) throws -> Float {
    let window = try harnessWindow(size: sz(100, 200)) {
        VStack(alignment: .leading) { Text("T").id("t"); second() }
    }
    let first = try window.frame(ofID: "t"), next = try window.frame(ofID: "u")
    return next.origin.y.value - (first.origin.y.value + first.size.height.value)
}

/// `SP0`..`SP2`: the view presents its **first** candidate's default-spacing edge, whichever is chosen. A `Text` above a
/// `Text` has no gap and above a `Color` one of 8.16 (`SP0`, `SP0b`); `{ Text; Color }` reads as the `Text` whether it
/// or the `Color` is chosen (`SP1`), and `{ Color (unchosen); Text }` as the `Color` (`SP2`). Mutation: `spacingEdges`
/// answering the union of the candidates (or the chosen one's) turns `SP1'` and `SP2` around.
@Test @MainActor func theSpacingEdgeIsTheFirstCandidates() throws {
    let textGap = try gapBelowText { Text("U").id("u") }
    let colorGap = try gapBelowText { Color.red.frame(width: Pixels(20), height: Pixels(10)).id("u") }
    try #require(textGap != colorGap, "set up: the two edges differ (\(textGap) vs \(colorGap))")
    let textFirst = try gapBelowText {
        ViewThatFits(in: .horizontal) { Text("U"); Color.red.frame(width: Pixels(20), height: Pixels(10)) }.id("u")
    }
    #expect(textFirst == textGap, "SP1: the Text is first and chosen")
    let colorChosen = try gapBelowText {
        ViewThatFits(in: .horizontal) { Text("U").frame(width: Pixels(500)); Color.red.frame(width: Pixels(20), height: Pixels(10)) }.id("u")
    }
    #expect(colorChosen == textGap, "SP1': the Text is first, the Color is chosen, the edge is the Text's")
    let colorFirst = try gapBelowText {
        ViewThatFits(in: .horizontal) { Color.red.frame(width: Pixels(500), height: Pixels(10)); Text("U") }.id("u")
    }
    #expect(colorFirst == colorGap, "SP2: the Color is first (and unchosen), the edge is the Color's")
}

// MARK: - scrollTo

@MainActor private final class ScrollBox {
    var proxy: ScrollViewProxy?
    func keep(_ proxy: ScrollViewProxy) -> Bool { self.proxy = proxy; return true }
}

/// A `scrollTo` into an unchosen candidate finds nothing, and the window still goes idle (no frame is requested for a
/// target that never prepaints). The element is also not recorded as bounds. Mutation: dropping the `IdentifiedGroup` guard
/// in `ExplicitIdentity.swift` records zero bounds for the identified unchosen group (the first expectation).
@Test @MainActor func aScrollToIntoAnUnchosenCandidateIdles() async throws {
    let box = ScrollBox()
    let window = try harnessWindow(size: sz(100, 100)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                let _ = box.keep(proxy)
                ProposalScrollView {
                    VStack(spacing: Pixels(0)) {
                        ViewThatFits(in: .horizontal) {
                            Text("wide").frame(width: Pixels(500), height: Pixels(20)).id("target")
                            Text("narrow").frame(width: Pixels(40), height: Pixels(20))
                        }
                    }
                }
            }
        }
    }
    window.tick()
    #expect(throws: TestHarnessError.self) { try window.frame(ofID: "target") }
    box.proxy?.scrollTo("target")
    try await window.runUntilIdle()
}

// MARK: - The census: every kind of candidate registers nothing when it is not chosen

private struct CensusComponent: Component {
    var content: some ElementGroup {
        Text("component label")
        Button("inside a component") {}.keyboardShortcut("k")
    }
}

private struct CensusEquatable: Component, @MainActor Equatable {
    let value: Int
    var content: some ElementGroup {
        Text("equatable \(value)")
        Button("inside an equatable") {}
    }
}

private struct CensusRow: Identifiable { let id: Int }

/// What a window with a view-that-fits whose first candidate is `kind` itself (rejected in the 5-wide window: every kind's
/// ideal is wider) shows compared with a window holding the fallback alone. The differences, empty when the candidate
/// registered, painted and appeared nothing. **The kind is the candidate's root, not nested in a container**: a nested
/// kind would be elided with its container and the group-level hooks the census exists for would never be reached.
@MainActor private func censusDifferences<Kind: ProposalElementGroup>(
    _ name: String, @ProposalContentBuilder _ kind: @escaping @MainActor () -> Kind) throws -> [String] {
    let log = HarnessLog()
    let subject = try harnessWindow(size: sz(5, 200)) {
        ViewThatFits(in: .horizontal) {
            kind()
                .onAppear { log.add("appear \(name)") }
                .task { log.add("task \(name)") }
            Text("fallback")
        }
    }
    let control = try harnessWindow(size: sz(5, 200)) {
        ViewThatFits(in: .horizontal) { Text("fallback") }
    }
    var differences: [String] = []
    if !log.entries.isEmpty { differences.append("lifecycle ran: \(log.entries)") }
    let (s, c) = (subject.lastFrameWork, control.lastFrameWork)
    if s.elementPrepaints != c.elementPrepaints { differences.append("prepaints \(s.elementPrepaints) vs \(c.elementPrepaints)") }
    if s.elementPaints != c.elementPaints { differences.append("paints \(s.elementPaints) vs \(c.elementPaints)") }
    if s.rects != c.rects || s.glyphs != c.glyphs || s.images != c.images { differences.append("scene \(s.rects)/\(s.glyphs) vs \(c.rects)/\(c.glyphs)") }
    let subjectNodes = try subject.elements(where: { _ in true }).map { "\($0.role)|\($0.label ?? "")" }
    let controlNodes = try control.elements(where: { _ in true }).map { "\($0.role)|\($0.label ?? "")" }
    if subjectNodes != controlNodes { differences.append("accessibility \(subjectNodes) vs \(controlNodes)") }
    for key: KeyEquivalent in ["k", "b"] {
        subject.typeKey(key, modifierFlags: .primary)
    }
    if !subject.windowActions.isEmpty { differences.append("window actions \(subject.windowActions)") }
    if subject.window.focusedElement != control.window.focusedElement, control.window.focusedElement == nil {
        differences.append("focus seated in the candidate")
    }
    return differences.map { "\(name): \($0)" }
}

/// The census guard (`VF-C`, D2-style): every kind of candidate registers nothing when it is not chosen: no prepaint, no
/// paint, no accessibility node, no focus stop, no shortcut, no `.onAppear` or `.task`, in a window that is otherwise
/// identical to one holding only the fallback. The kinds are `Text`, `Button`, `Toggle`, `Picker`, `Menu`, `TextField`, `List`,
/// `Grid`, `LazyVStack`, `ScrollView`, a `Component`, an `.equatable()` `Component`, an `AnyElement`, a `ForEach` element
/// and a legacy `Row`. Mutation: the elision check in `Element.prepaintGroup` deleted reddens every kind; a new element
/// kind that registers in a group-level hook (as `GeometryChangeScope` and `ModifierKeysScope` did) is the case this
/// census exists for, and takes an arm here.
@Test @MainActor func everyCandidateKindRegistersNothingWhenUnchosen() throws {
    var differences: [String] = []
    differences += try censusDifferences("Text") { Text("a long label that is unchosen") }
    differences += try censusDifferences("Button") { Button("go") {}.keyboardShortcut("k") }
    differences += try censusDifferences("Toggle") { Toggle("toggle", isOn: .constant(true)) }
    differences += try censusDifferences("Picker") { Picker("pick", selection: .constant(1)) { Text("one").tag(1); Text("two").tag(2) } }
    differences += try censusDifferences("Menu") { Menu("more") { Button("b") {}.keyboardShortcut("b") } }
    differences += try censusDifferences("TextField") { TextField("field", text: .constant("")) }
    differences += try censusDifferences("List") { List([CensusRow(id: 1), CensusRow(id: 2)], rowHeight: Pixels(20)) { row in Text("row \(row.id)") } }
    differences += try censusDifferences("Grid") { Grid { GridRow { Text("a"); Text("b") } } }
    differences += try censusDifferences("LazyVStack") { LazyVStack { Text("lazy a"); Text("lazy b") } }
    differences += try censusDifferences("ScrollView") { ProposalScrollView { Text("scrolled") } }
    differences += try censusDifferences("Component") { CensusComponent() }
    differences += try censusDifferences("EquatableComponent") { CensusEquatable(value: 1).equatable() }
    differences += try censusDifferences("AnyElement") { AnyElement(Button("erased") {}.keyboardShortcut("k")) }
    differences += try censusDifferences("ForEach") { ForEach(0..<3) { index in Button("each \(index)") {} } }
    differences += try censusDifferences("LegacyRow") { Row { Button("legacy") {}.keyboardShortcut("k"); Text("in a row") } }
    #expect(differences.isEmpty, "\(differences)")
}

/// The group-level hooks (a scope that registers at prepaint, before it reaches its content): a candidate wrapped in
/// `onGeometryChange`, `onModifierKeysChanged`, `coordinateSpace`, `scrollTargetLayout` and `.id` registers none of them
/// when it is not chosen (`VF-C`; the geometry and modifier-keys scopes and the identified group each took an elision
/// guard of their own, found by reading every `prepaintGroup`). Mutation: dropping the `allElided` guard of
/// `GeometryChangeScope` / `ModifierKeysScope` / `IdentifiedGroup` reddens the geometry log, the modifier log and the
/// `frame(ofID:)` expectation respectively.
@Test @MainActor func everyGroupLevelHookRegistersNothingWhenUnchosen() throws {
    func build(_ log: HarnessLog) -> some Element {
        ViewThatFits(in: .horizontal) {
            Text("an unchosen candidate").frame(width: Pixels(400), height: Pixels(20))
                .onGeometryChange(for: Float.self, of: { Float($0.size.width.value) }) { log.add("geometry \($0)") }
                .onModifierKeysChanged(initial: true) { _, new in log.add("modifiers \(new.rawValue)") }
                .coordinateSpace(.named("census"))
                .scrollTargetLayout()
                .id("hook")
            Text("fallback").frame(width: Pixels(30), height: Pixels(20))
        }
    }
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(60, 100)) { build(log) }
    window.pressModifiers([.shift])
    window.tick()
    #expect(log.entries.isEmpty, "nothing of the unchosen candidate's hooks ran: \(log.entries)")
    #expect(throws: TestHarnessError.self) { try window.frame(ofID: "hook") }
    // The positive control: the same tree with the candidate chosen runs all of them and records its bounds.
    let chosenLog = HarnessLog()
    let chosen = try harnessWindow(size: sz(500, 100)) { build(chosenLog) }
    chosen.pressModifiers([.shift])
    chosen.tick()
    #expect(chosenLog.entries.contains { $0.hasPrefix("geometry") } && chosenLog.entries.contains { $0.hasPrefix("modifiers") })
    #expect(try chosen.frame(ofID: "hook").size.width.value == 400)
}

// MARK: - Retained subtrees (`VF-H`)

/// An `.equatable()` row in each candidate: its content reads nothing that changes, so it replays while it is chosen.
private struct RetainedRow: Component, @MainActor Equatable {
    let tag: String
    let width: Float
    var content: some ElementGroup {
        Text(tag).frame(width: Pixels(width), height: Pixels(20))
    }
}

/// An occurrence that holds a whole `ViewThatFits`.
private struct HoldsAViewThatFits: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                Text("a wide candidate").frame(width: Pixels(400), height: Pixels(20))
                Text("narrow").frame(width: Pixels(40), height: Pixels(20))
            }
        }
    }
}

/// A retained window and its retention-off twin, drawn alike.
@MainActor private func retainedPair<Root: Element>(size: Size<Pixels>, _ root: @escaping @MainActor () -> Root) throws -> (on: TestWindow, off: TestWindow) {
    let on = try harnessWindow(size: size, root)
    on.window.testingRetainedSubtrees = true
    on.window.testingRetainedGraft = true
    let off = try harnessWindow(size: size, root)
    off.window.testingRetainedSubtrees = false
    off.window.testingRetainedGraft = false
    for window in [on, off] { for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() } }
    return (on, off)
}

@MainActor private func sceneKey(_ window: TestWindow) -> [String] {
    window.scene.rects.map { "\($0.bounds)" } + window.scene.glyphs.map { "\($0.bounds)" }
}

/// `.equatable()` rows in a view-that-fits: an unchosen occurrence replays and records nothing (it takes the plain,
/// elided branch), a switch draws what a retention-off twin draws in every frame, and the occurrence that holds a whole
/// `ViewThatFits` (or sits in a candidate) is refused a graft **by the name `viewThatFits`** (the occurrence's build
/// registers spans, elisions and retractions the journal does not replay). Run it under `METALUI_VERIFY_RETAINED=1` too:
/// a wrong replay traps there. Mutation: deleting `EquatableComponent.prepaintGroup`'s elision branch draws the unchosen
/// occurrence from its record (the twin comparison reddens); dropping `fitContainers` from `BuildAudit.movedChannel` leaves
/// the container grafted (the refusal expectation).
@Test @MainActor func equatableRowsInAViewThatFitsReplayNothingUnchosen() throws {
    func tree() -> some Element {
        ViewThatFits(in: .horizontal) {
            RetainedRow(tag: "wide row", width: 400).equatable()
            RetainedRow(tag: "mid row", width: 150).equatable()
            RetainedRow(tag: "narrow row", width: 10).equatable()
        }
    }
    let pair = try retainedPair(size: sz(300, 100)) { tree() }
    #expect(sceneKey(pair.on) == sceneKey(pair.off), "chosen: the retained window draws what the twin draws")
    for width: Float in [50, 300, 500, 300] {
        for window in [pair.on, pair.off] { window.resize(to: sz(width, 100)); for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() } }
        #expect(sceneKey(pair.on) == sceneKey(pair.off), "W = \(width): the twin agrees")
        #expect(pair.on.scene.glyphs.count == pair.off.scene.glyphs.count)
    }
    let labels = try pair.on.elements(role: .staticText).compactMap { $0.value ?? $0.label }
    #expect(labels == ["mid row"], "only the chosen row is an accessibility node: \(labels)")

    let holder = try retainedPair(size: sz(300, 100)) { VStack(spacing: 0) { HoldsAViewThatFits().equatable() } }
    #expect(holder.on.window.testingGraftRefusals.contains { $0.hasPrefix("viewThatFits") },
            "the occurrence holding a view-that-fits is refused by name: \(holder.on.window.testingGraftRefusals)")
    #expect(holder.on.lastFrameWork.retainedGrafts == 0)
    #expect(sceneKey(holder.on) == sceneKey(holder.off))
}

// MARK: - Divergence 220

@MainActor private enum SeedLog {
    static var next = 0
    static func take() -> Int { next += 1; return next }
}

/// A candidate that shows the seed its `@State` took.
private struct SeededRow: Component {
    let tag: String
    let width: Float
    @State var seed = SeedLog.take()
    var content: some ElementGroup {
        Text("\(tag) \(seed)").frame(width: Pixels(width), height: Pixels(20))
    }
}

/// Divergence 220 (pinned): a candidate after the chosen one is built from the first frame, so its `@State` default is
/// evaluated and kept then, not when it is first chosen. `C` never shows at 300 wide; after the window narrows its
/// seed is one the first frame took (`<=` the count after that frame), where a state created on first choice would hold a
/// later one. SwiftUI creates a measured candidate's state when it is measured and, as the recorded probe read it, every
/// candidate's (`S0b`).
@Test @MainActor func aLaterCandidatesStateIsSeededOnTheFirstBuiltFrame() throws {
    SeedLog.next = 0
    let window = try harnessWindow(size: sz(300, 100)) {
        ViewThatFits(in: .horizontal) {
            SeededRow(tag: "A", width: 400)
            SeededRow(tag: "B", width: 150)
            SeededRow(tag: "C", width: 10)
        }
    }
    let afterTheFirstFrame = SeedLog.next
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    #expect(SeedLog.next > afterTheFirstFrame, "set up: the defaults are evaluated again every frame")
    window.resize(to: sz(50, 100))
    let shown = try window.elements(role: .staticText).compactMap { $0.value ?? $0.label }
    let seed = try #require(shown.first.flatMap { Int($0.dropFirst(2)) }, "C shows its seed: \(shown)")
    #expect(shown.first?.hasPrefix("C ") == true)
    #expect(seed <= afterTheFirstFrame, "C's seed \(seed) was taken on the first frame (\(afterTheFirstFrame)), not when C was chosen")
}

// MARK: - Scroll targets, scopes over several candidates, a retained row that goes unchosen

@MainActor private final class PositionBox { var id: Int? }

/// A `ForEach` of scroll targets in a candidate that is not chosen notes none (`allElided` in `ForEach.prepaintGroup`): the
/// position binding stays unwritten at 100 wide, and the positive control (the same tree at 600 wide, the candidate chosen)
/// writes the first row. Mutation: dropping the `allElided` guard writes a zero-rect target's id.
@Test @MainActor func aScrollTargetInAnUnchosenCandidateIsNotNoted() throws {
    func writtenPosition(width: Float) throws -> Int? {
        let box = PositionBox()
        let binding = Binding<Int?>(get: { box.id }, set: { box.id = $0 })
        let window = try harnessWindow(size: sz(width, 100)) {
            ProposalScrollView {
                ViewThatFits(in: .horizontal) {
                    VStack(spacing: Pixels(0)) {
                        ForEach(0..<5) { index in Text("r\(index)").frame(width: Pixels(500), height: Pixels(60)) }
                    }.scrollTargetLayout()
                    Text("narrow")
                }
            }.scrollPosition(id: binding)
        }
        for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
        window.scroll(at: pt(width / 2, 50), byDeltaX: 0, deltaY: -70)
        for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
        return box.id
    }
    let control = try writtenPosition(width: 600)
    #expect(control == 1, "the control: scrolled by 70, a chosen candidate's second target (60 tall) is the position")
    #expect(try writtenPosition(width: 100) == nil, "an unchosen candidate's targets are not noted")
}

/// A component of two members: a group of two candidates (probe `E3`).
private struct TwoCandidates: Component {
    var content: some ElementGroup {
        Text("A").frame(width: Pixels(400), height: Pixels(20))
        Text("B").frame(width: Pixels(150), height: Pixels(20))
    }
}

/// A lifecycle scope over a group of two members in a view-that-fits: the two candidates are one scope. It is retracted only
/// when **neither** is chosen: with `A` chosen (wide) it appears once; with `B` chosen (mid) it appears, because its interval
/// reaches a chosen candidate; with the fallback `C` chosen (narrow) it does not. Mutation: merging the unchosen ranges
/// (`range.low <= last.high + 1` to a never-true test) retracts nothing for the `narrow` case's two adjacent unchosen
/// candidates, so the scope appears.
@Test @MainActor func aScopeOverSeveralCandidatesIsRetractedOnlyWhenNoneIsChosen() throws {
    func appearances(width: Float) throws -> [String] {
        let log = HarnessLog()
        _ = try harnessWindow(size: sz(width, 100)) {
            ViewThatFits(in: .horizontal) {
                TwoCandidates().onAppear { log.add("group") }
                Text("C").frame(width: Pixels(10), height: Pixels(20)).onAppear { log.add("C") }
            }
        }
        return log.entries
    }
    #expect(try appearances(width: 500) == ["group"], "A chosen")
    #expect(try appearances(width: 300) == ["group"], "B chosen")
    #expect(try appearances(width: 50) == ["C"], "neither A nor B chosen: the scope over both is retracted")
}

private struct RetainedAppearRow: Component, @MainActor Equatable {
    let log: HarnessLog
    var content: some ElementGroup {
        Text("retained").frame(width: Pixels(200), height: Pixels(20))
            .onAppear { log.add("appear") }
            .onDisappear { log.add("disappear") }
    }
    static func == (l: RetainedAppearRow, r: RetainedAppearRow) -> Bool { l.log === r.log }
}

/// A grafted `.equatable()` occurrence inside a candidate would replay its lifecycle notes whether or not the candidate is
/// chosen: a graft window opened inside a view's content is therefore refused (`VF-H`), and the row disappears when its
/// candidate stops being chosen, with the retention and the graft switched on. Mutation: dropping the `fitDepth > 0` taint in
/// `Frame.openGraftWindow` records a graft under the view, which then replays `appear` for the unchosen row.
@Test @MainActor func aRetainedRowThatGoesUnchosenDisappearsWithGraftsOn() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(300, 100)) {
        ViewThatFits(in: .horizontal) {
            RetainedAppearRow(log: log).equatable()
            Text("n").frame(width: Pixels(10), height: Pixels(20))
        }
    }
    window.window.testingRetainedSubtrees = true
    window.window.testingRetainedGraft = true
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    #expect(log.entries == ["appear"], "chosen: appears once: \(log.entries)")
    window.resize(to: sz(100, 100))
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(log.entries == ["appear", "disappear"], "unchosen with grafts on: it disappears: \(log.entries)")
    window.resize(to: sz(300, 100))
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(log.entries == ["appear", "disappear", "appear"], "and appears again: \(log.entries)")
}

/// A presentation that is already requested when the build starts (its binding is `true`) in an unchosen candidate is not
/// presented: the record is retracted (`VF-D`) before anything dispatches, where `unchosenCandidates...` only reaches an alert
/// through an `onAppear` that is itself retracted. Widened, the candidate is chosen and the alert presents. Mutation:
/// skipping the `presentationRecords` removal in `applyFitChoices()` presents the unchosen candidate's alert.
@Test @MainActor func anAlertRequestedBeforeTheBuildInAnUnchosenCandidateIsNotPresented() throws {
    let window = try harnessWindow(size: sz(300, 100)) {
        ViewThatFits(in: .horizontal) {
            Text("wide").frame(width: Pixels(400), height: Pixels(20))
                .alert("From the wide candidate", isPresented: .constant(true)) { Button("OK") {} }
            Text("mid").frame(width: Pixels(150), height: Pixels(20))
        }
    }
    window.tick()
    #expect(window.presentedAlert == nil, "the unchosen candidate's alert is retracted")
    window.resize(to: sz(600, 100))
    window.tick()
    #expect(window.presentedAlert?.title == "From the wide candidate", "chosen, it presents")
}

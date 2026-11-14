import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Alloy G33(a) A0 follow-ups (`RW-K`, `RW-V`; record 292): a closed menu or menu picker anchors replay and does not taint its
// ancestors' graft; an open one still does. Two windows over one builder as in `RetainedGraftTests`.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

enum RPTKind: String, CaseIterable { case plainMenu, codeMenu, picker, composer }

/// A composer-shaped occurrence: a menu-style picker and a menu in a row, and a text under them.
private struct RPTCard: Component, @MainActor Equatable {
    let kind: RPTKind
    let side: RPSide
    var content: some ElementGroup {
        let mode = Binding<Int>(get: { 0 }, set: { _ in })
        // Not observable: a flip is invisible to the occurrence's observation, only the binding's own read can see it (`RW-V`).
        let open = Binding<Bool>(get: { side.menuOpen }, set: { side.menuOpen = $0 })
        VStack(spacing: 2) {
            Text("composer").frame(width: Pixels(80), height: Pixels(12))
            HStack(spacing: 4) {
                if kind == .picker || kind == .composer {
                    Picker("Mode", selection: mode) {
                        Text("Ask").tag(0)
                        Text("Plan").tag(1)
                    }
                }
                if kind == .plainMenu {
                    Menu("Model") { Button("Sonnet") {} ; Button("Opus") {} }
                }
                if kind == .codeMenu || kind == .composer {
                    Menu("Model") { Button("Sonnet") {} ; Button("Opus") {} }.menuPresented(open)
                }
            }
        }
    }
    static func == (l: RPTCard, r: RPTCard) -> Bool { l.kind == r.kind && l.side === r.side }
}

/// A closed code-driven menu (`.menuPresented`) and a menu-style `Picker` sit in an `.equatable()` occurrence: it grafts
/// every steady frame (`RW-K`: a closed anchor replays; `RW-V`: so does a closed menu's record), where the record used to
/// refuse it by the `presentation` channel. The off window is the differential: scene, accessibility, hitboxes and the
/// presentation records the window adopts are equal. **Red before:** `codeMenu` and `composer` read 0 grafts, 1 ineligible,
/// 8 and 16 element requests, refusal `presentation`. **Mutation:** the `.presentationNote` replay dropped in `reapply`
/// (the record keys differ from the off window's), the `buildAudit` subtraction dropped (the refusal returns).
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: RPTKind.allCases) @MainActor
func aClosedMenuOrPickerDoesNotRefuseTheGraft(kind: RPTKind) throws {
    let pair = try RPPair(size: sz(240, 120), warm: 5) { side in VStack(spacing: 0) { RPTCard(kind: kind, side: side).equatable() } }
    try pair.compare("warm")
    pair.redraw()
    let f = try #require(pair.frames.last)
    #expect(f.retainedGrafts == 1 && f.retainedGraftIneligible == 0, "\(kind) grafts: \(f.retainedGrafts)/\(f.retainedGraftIneligible)")
    #expect(f.elementRequests == 0, "the build recursion is skipped: \(f.elementRequests)")
    #expect(pair.on.window.testingGraftRefusals.isEmpty, "\(pair.on.window.testingGraftRefusals)")
    #expect(pair.on.window.testingPresentationRecordKeys == pair.off.window.testingPresentationRecordKeys,
            "the window adopts the same records: \(pair.on.window.testingPresentationRecordKeys) vs \(pair.off.window.testingPresentationRecordKeys)")
    try pair.compare("the steady frame")
}

/// Open from code, close, graft again: the binding turning `true` refuses the graft (the build runs, the menu opens as
/// the retention-off window's does), and once it reads `false` again the occurrence grafts after one build. **Mutation:**
/// the binding compare dropped in `graftDependenciesHold` (the stale graft keeps the menu shut: the scenes differ).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aCodeDrivenMenuOpensUnderAGraftAndTheGraftReturnsOnClose() throws {
    let pair = try RPPair(size: sz(240, 160), warm: 5) { side in VStack(spacing: 0) { RPTCard(kind: .composer, side: side).equatable() } }
    pair.redraw()
    try #require(pair.frames.last?.retainedGrafts == 1, "grafting while closed: \(String(describing: pair.frames.last))")
    try #require(pair.on.presentedMenu == nil && pair.off.presentedMenu == nil)
    pair.onSide.menuOpen = true; pair.offSide.menuOpen = true
    pair.redraw()
    let opening = try #require(pair.frames.last)
    #expect(opening.retainedGrafts == 0, "an open request builds: \(opening.retainedGrafts)")
    pair.redraw(); pair.redraw()
    try pair.compare("open")
    #expect(pair.on.presentedMenu != nil && pair.off.presentedMenu != nil, "the menu is up in both windows")
    pair.onSide.menuOpen = false; pair.offSide.menuOpen = false
    for _ in 0..<12 { pair.redraw() }
    try pair.compare("closed")
    #expect(pair.on.presentedMenu == nil && pair.off.presentedMenu == nil, "the menu is gone")
    let again = try #require(pair.frames.last)
    #expect(again.retainedGrafts == 1 && again.elementRequests == 0, "grafting again after the close: \(again.retainedGrafts)/\(again.elementRequests)")
}

/// A code-driven menu that is already open when its occurrence is built is a presentation: no graft record, by name.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func anOpenCodeDrivenMenuStillRefusesTheGraftByName() throws {
    let pair = try RPPair(size: sz(240, 160), warm: 0) { side in
        side.menuOpen = true
        return VStack(spacing: 0) { RPTCard(kind: .codeMenu, side: side).equatable() }
    }
    for _ in 0..<6 { pair.redraw() }
    try pair.compare("open")
    let f = try #require(pair.frames.last)
    #expect(f.retainedGrafts == 0, "an open menu does not graft: \(f.retainedGrafts)")
    #expect(f.retainedGraftIneligible >= 1 && pair.on.window.testingGraftRefusals.contains("presentation"),
            "\(f.retainedGraftIneligible) \(pair.on.window.testingGraftRefusals)")
}

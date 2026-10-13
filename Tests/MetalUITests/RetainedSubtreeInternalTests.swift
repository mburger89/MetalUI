import Foundation
import Observation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIText
import MetalUITesting
@testable import MetalUI

// C14b lane 1 (`SB-E`, `SB-G`, `SB-I`, `SB-K`): what only the internal view can see — the
// classification of every stored channel of `Frame`, `StateTable` and `AnimationStore`, the
// environment fingerprint, the paint-time observed read, the slots a replay keeps alive, and the
// glyph atlas's lack of an eviction caller. Tests 1.7, 1.9, 1.11 and 1.19 of the design spec.

// MARK: 1.11 — the ledger's classification

/// What a stored channel is to a retained subtree (`SB-E`).
private enum Channel: String {
    /// Recorded and replayed.
    case recorded
    /// In the replay key.
    case keyed
    /// A change makes the occurrence ineligible.
    case ledger
    /// Not touched by prepaint or paint, or constant for the frame.
    case frameLocal
    /// Written in the layout phase only (the build runs in lane 1).
    case buildOnly
}

/// Every stored property of `Frame`, with its class and the line that justifies it. **Adding a stored
/// property to `Frame` owes a row** (`everyFrameChannelIsClassified`).
private let frameChannels: [String: Channel] = [
    // Frame constants and window inputs.
    "contentSize": .keyed, "scaleFactor": .keyed, "timestamp": .frameLocal, "mousePosition": .keyed,
    "activeElement": .keyed, "stateTable": .recorded, "animationStore": .recorded, "textSystem": .frameLocal,
    "shapingCache": .frameLocal, "glyphAtlas": .frameLocal, "surfaceRegistry": .ledger,
    "tree": .frameLocal, "rootFontSize": .frameLocal, "rootTheme": .frameLocal, "lightTheme": .frameLocal,
    "darkTheme": .frameLocal, "transaction": .keyed, "snapsEveryChange": .frameLocal,
    "collectsAccessibility": .keyed, "reportsUnlowerableFields": .frameLocal, "recordsElementBounds": .frameLocal,
    // Scroll requests and keys (layout, or ineligible).
    "scrollRequestQueue": .buildOnly, "scrollRequests": .buildOnly, "scrollRequestResolved": .buildOnly,
    "unresolvedScrollRequestCount": .keyed, "notesScrollKeys": .buildOnly, "scrollKeys": .ledger,
    "scrollResolutions": .ledger, "scrollAnchorAdjustments": .ledger, "forEachIdentityWork": .buildOnly,
    // Animation and lifecycle.
    "wantsAnotherFrame": .ledger, "hasActiveAnimations": .ledger, "timeVaryingNotes": .ledger,
    "transactionTop": .keyed, "transactionDepth": .keyed, "lifecycleDepth": .buildOnly,
    "effectScopesPushed": .frameLocal, "compositeScopesPushed": .frameLocal,
    // Tallies, replayed.
    "hoverRegionCount": .recorded, "pointerStyleRegionCount": .recorded, "keyRegionCount": .recorded,
    "focusOnPressCount": .recorded, "resignRegionCount": .recorded,
    // Presentations, toolbar, menu bar, popovers.
    "presentationDepth": .keyed, "presentationRecords": .ledger, "presentationOccurrences": .ledger,
    "toolbarRecords": .ledger, "drawsToolbarStrip": .frameLocal, "drewToolbarStrip": .frameLocal,
    "menuBarTitles": .frameLocal, "menuBarOpenIndex": .frameLocal, "menuBarOpen": .frameLocal,
    "drewMenuBar": .frameLocal, "menuBarTitleFrames": .frameLocal, "openPopovers": .ledger,
    "tooltip": .frameLocal, "menuPresenter": .frameLocal, "presentationAnchors": .ledger,
    "previousPresentationAnchors": .frameLocal, "presentationSpaces": .ledger,
    "previousPresentationSpaces": .frameLocal, "wantsAccessibilityRetry": .ledger,
    // Environment and colour.
    "environmentTop": .keyed, "storedRootEnvironment": .frameLocal, "isRendering": .frameLocal,
    "colorSchemePreferenceDepth": .buildOnly, "mainColorSchemePreference": .buildOnly,
    "presentationColorSchemePreference": .buildOnly, "collectedNavigationTitle": .buildOnly,
    "collectedNavigationDocument": .buildOnly, "openURLHandlers": .buildOnly,
    "contentSizeLimitsMode": .buildOnly, "contentMinimum": .buildOnly, "contentMaximum": .buildOnly,
    "environmentPushCount": .frameLocal, "environmentSnapshotCount": .frameLocal,
    "environmentTransformCount": .frameLocal,
    // The scene and its stacks.
    "scene": .recorded, "clipStack": .keyed, "clipBase": .keyed, "flatteningClipBase": .keyed,
    "layerStack": .keyed, "opacityStack": .keyed, "portalCount": .ledger, "portalStack": .keyed,
    "scrollContextStack": .keyed, "scrollerFrameStack": .keyed, "paintScopes": .keyed,
    "leafGroup": .keyed, "prepaintEffects": .keyed, "shareCandidates": .keyed, "shareCollecting": .keyed,
    "shareFloor": .keyed, "shareFloorAtEntry": .keyed,
    // Hitboxes, accessibility, focus, hover.
    "hitboxes": .recorded, "hitTestingDisabledDepth": .keyed, "keyboardHiddenDepth": .keyed,
    "axNodes": .recorded, "axEmissions": .recorded, "accessibilityPressOnly": .recorded,
    "contextMenuRecords": .recorded, "namedSpaces": .keyed, "hitboxNamedSpaces": .recorded,
    "namedSpaceSnapshots": .recorded, "accessibilitySuppressionExceptions": .keyed,
    "focusRegistry": .recorded, "focusedElement": .keyed, "focusedElementProducedThisFrame": .recorded,
    "hoveredHitbox": .keyed, "stackAxes": .keyed,
    // Layout results.
    "lowering": .buildOnly, "hiddenNodes": .buildOnly, "elementBounds": .recorded, "unlowerableFields": .ledger,
    // Surfaces.
    "surfaceRequests": .ledger,
    // The drawn overlays and the drag preview: owned by the window, painted at the root.
    "dragSourceID": .keyed, "menuPanelLevels": .frameLocal, "menuRowsPainted": .frameLocal,
    "pickerTitleWidths": .frameLocal, "alertPanel": .frameLocal, "dragPreviewTranslation": .frameLocal,
    "dragPreviewOrigin": .frameLocal, "previousDragSnapshot": .frameLocal, "dragSnapshot": .frameLocal,
    "dragCapturedPrimitives": .frameLocal,
    // Retained subtrees' own.
    "elementRequests": .frameLocal, "elementPrepaints": .frameLocal, "elementPaints": .frameLocal,
    "retainLog": .frameLocal,
]

@MainActor private func storedNames(of subject: Any) -> Set<String> {
    Set(Mirror(reflecting: subject).children.compactMap { child in
        guard var label = child.label else { return nil }
        if label.hasPrefix("$__lazy_storage_$_") { label.removeFirst("$__lazy_storage_$_".count) }
        if label.hasPrefix("_") { label.removeFirst() }
        return label
    })
}

/// 1.11 — **every stored property of `Frame` is classified** (`SB-E`), as `theSevenRetentionSlots…`
/// fails on an eighth slot. A property absent from the table fails with its name; a table row naming a
/// property that no longer exists fails too, so the table cannot rot. Mutation: a stored property added
/// to `Frame` (any) — reds with its name.
@MainActor @Test func everyFrameChannelIsClassified() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                      stateTable: StateTable(), shapingCache: ShapingCache(),
                      glyphAtlas: GlyphAtlas(width: 64, height: 64), theme: Theme.forAppearance(.light))
    let names = storedNames(of: frame)
    let known = Set(frameChannels.keys)
    #expect(names.subtracting(known).sorted() == [], "stored properties of Frame with no row in frameChannels")
    #expect(known.subtracting(names).sorted() == [], "rows of frameChannels naming no stored property of Frame")
}

/// `StateTable` and `AnimationStore` (`SB-E`): the stores a prepaint or paint writes. Recorded through
/// the journals (`markJournal`, `retainLog`), or ledger (`writeCount` and the entries behind `withState`),
/// or touched only by sweeps and builds.
private let stateTableChannels: [String: Channel] = [
    "storage": .ledger, "marked": .recorded, "versionCounter": .ledger, "contentMemos": .recorded,
    "markJournal": .recorded, "retainLog": .frameLocal, "generation": .frameLocal, "aliasedStateBoxes": .buildOnly,
    "producedSlots": .buildOnly, "previouslyProducedSlots": .buildOnly, "subtreeResetScans": .buildOnly,
    "absentSlots": .buildOnly, "namedPositions": .buildOnly, "previousNamedPositions": .buildOnly,
    "producedNames": .buildOnly, "departedNames": .buildOnly, "windowedParents": .buildOnly,
    "departedNameResets": .buildOnly, "resetScanWork": .buildOnly, "lastResetScanWork": .buildOnly,
    "loopExtents": .buildOnly, "previousLoopExtents": .buildOnly, "retainsDepartedValues": .buildOnly,
    "departedValues": .buildOnly, "departedRootsKept": .buildOnly, "lastDepartedValueCount": .buildOnly,
    "departedOverlay": .buildOnly, "focusStates": .buildOnly, "departedRoots": .buildOnly,
    "doomedKeys": .buildOnly, "resetFocusSlots": .buildOnly, "isDirty": .ledger, "onWrite": .frameLocal,
    "writeCount": .ledger,
]

private let animationStoreChannels: [String: Channel] = [
    "entries": .recorded, "touched": .recorded, "interpolationsThisFrame": .ledger, "transitions": .ledger,
    "rasters": .recorded, "layoutMemo": .buildOnly, "lifecycle": .buildOnly, "timeline": .buildOnly,
    "keyframeDepth": .buildOnly, "lastFrameInterpolations": .frameLocal, "retainLog": .frameLocal,
]

@MainActor @Test func everyStateTableAndAnimationStoreChannelIsClassified() {
    let table = storedNames(of: StateTable())
    #expect(table.subtracting(stateTableChannels.keys).sorted() == [], "stored properties of StateTable with no row")
    #expect(Set(stateTableChannels.keys).subtracting(table).sorted() == [], "rows naming no stored property of StateTable")
    let store = storedNames(of: AnimationStore())
    #expect(store.subtracting(animationStoreChannels.keys).sorted() == [], "stored properties of AnimationStore with no row")
    #expect(Set(animationStoreChannels.keys).subtracting(store).sorted() == [], "rows naming no stored property of AnimationStore")
}

/// The built-in environment fields the fingerprint covers, and those declared irrelevant (`SB-G`).
private let environmentFields: [String: String] = [
    "isEnabled": "fingerprint", "layoutDirection": "fingerprint", "locale": "fingerprint",
    "dynamicTypeSize": "fingerprint", "displayScale": "fingerprint", "controlActiveState": "fingerprint",
    "accessibilityReduceMotion": "fingerprint", "accessibilityReduceTransparency": "fingerprint",
    "titleBarInsets": "fingerprint", "windowSize": "fingerprint", "colorScheme": "fingerprint",
    "controlSize": "fingerprint", "font": "fingerprint",
    "truncationMode": "fingerprint", "multilineTextAlignment": "fingerprint", "foregroundStyle": "fingerprint",
    "fontWeight": "fingerprint", "italic": "fingerprint", "textLineLimit": "fingerprint",
    "fieldStyles": "fingerprint (both styles)", "theme": "fingerprint", "textSystemBox": "fingerprint (presence)",
    "objects": "fingerprint (identities)", "custom": "customKeyCount, a refusal",
    "fileDialogs": "irrelevant: a window-owned handle, constant for the window",
]

/// 1.11b — **every stored property of `EnvironmentValues` is in the fingerprint or declared irrelevant**
/// (`SB-G`). Mutation: a stored property added to `EnvironmentValues`.
@MainActor @Test func everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant() {
    let names = storedNames(of: EnvironmentValues())
    #expect(names.subtracting(environmentFields.keys).sorted() == [], "stored properties of EnvironmentValues with no row")
    #expect(Set(environmentFields.keys).subtracting(names).sorted() == [], "rows naming no stored property")
}

// MARK: 1.19 — the atlas has no eviction caller

private func sourceFiles(under directory: URL) -> [URL] {
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return [] }
    return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
}

/// 1.19 — replay re-inserts glyph sprites whose atlas slots were stamped in a past frame, which is only
/// sound while nothing evicts (`SB-I`). **Nothing calls `GlyphAtlas.evictUnusedSince(_:)` outside its
/// definition**; the day something does, a replayed glyph may point at a dropped slot and this test names
/// the caller. Mutation: a caller added in `Sources/`.
@Test func theGlyphAtlasHasNoEvictionCaller() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    var callers: [String] = []
    for directory in ["Sources", "Backends/SDL/Sources"] {
        for file in sourceFiles(under: root.appendingPathComponent(directory)) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.drop(while: { $0 == " " })
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                if line.contains("evictUnusedSince("), !line.contains("func evictUnusedSince(") {
                    callers.append("\(file.path):\(number + 1)")
                }
            }
        }
    }
    #expect(callers == [], "GlyphAtlas.evictUnusedSince has a caller: replayed glyphs may name evicted slots (SB-I)")
}

// MARK: 1.7 — an observed read in paint

@Observable @MainActor private final class PaintModel { var tone = 0 }

private struct PaintReader: Element {
    let model: PaintModel
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {
        pass.fill(bounds, color: model.tone == 0 ? Hsla(h: 0.6, s: 1, l: 0.5, a: 1) : Hsla(h: 0.0, s: 1, l: 0.5, a: 1))
    }
}

private struct PaintHolder: Component, @MainActor Equatable {
    let model: PaintModel
    var content: some ElementGroup { PaintReader(model: model) }
    static func == (l: PaintHolder, r: PaintHolder) -> Bool { true }
}

/// 1.7 — an `@Observable` read in an element's `paint` invalidates the record (`SB-D` item 4): the
/// getter never read it and the holder is always `==`, so only the paint session can see the change.
/// Mutation: `RetainedSession.run`'s `onChange` made a no-op — the changed tone is never drawn.
@MainActor @Test func anObservedReadInPaintInvalidatesTheRecord() async throws {
    let model = PaintModel()
    let window = try TestWindow(size: Size(width: Pixels(100), height: Pixels(60))) {
        VStack(spacing: 0) { PaintHolder(model: model).equatable() }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.lastFrameWork.retainedHits == 1)
    let before = window.scene.rects.last?.background
    model.tone = 1
    await Task.yield()
    window.window.setNeedsRedraw(); window.tick()
    let after = window.scene.rects.last?.background
    #expect(after != nil && before != nil && (after!.h != before!.h), "the new tone was drawn")
    #expect(window.lastFrameWork.retainedMisses == 1)
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.lastFrameWork.retainedHits == 1)
}

// MARK: 1.9 — a replayed frame keeps its slots alive

private struct SlotHolder: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text("go").accessibilityLabel("go label").frame(width: Pixels(40), height: Pixels(20))
        }
    }
    static func == (l: SlotHolder, r: SlotHolder) -> Bool { true }
}

/// 1.9 — the accessibility retention slot (`$ax`) of a button inside a replayed subtree stays live over
/// frames that replay it: the replay re-runs the slot's `withState` (a mark), so `sweep()` never sees it
/// unproduced. Mutation: the `axNodes` loop of `replayPrepaint` dropped — after the first replayed frame's
/// sweep the slot reads `isLive == false`.
@MainActor @Test func aReplayedFrameKeepsItsAccessibilitySlotsAlive() throws {
    let window = try TestWindow(size: Size(width: Pixels(100), height: Pixels(60))) {
        VStack(spacing: 0) { SlotHolder().equatable() }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let slots = window.window.stateTable.ids.filter {
        if case .named(let name) = $0.component { return name.name == "$ax" }
        return false
    }
    try #require(slots.isEmpty == false, "the declared label left an accessibility retention slot")
    try #require(slots.contains { window.window.stateTable.isLive($0) }, "the slot is live after recording")
    for _ in 0..<3 {
        window.window.setNeedsRedraw(); window.tick()
        #expect(window.lastFrameWork.retainedHits == 1)
        #expect(slots.contains { window.window.stateTable.isLive($0) }, "live after a replayed frame")
    }
}

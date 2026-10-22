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

/// What a stored channel is to a retained subtree (`SB-E`, `SB-AA`).
private enum Channel: String {
    /// Recorded and replayed (the scene, the marks and touches paint makes).
    case recorded
    /// In the replay key, or the pointer/press/focus rule.
    case keyed
    /// A change in a paint makes the occurrence ineligible.
    case ledger
    /// Written by prepaint only: replayed from a prepaint ledger, or audited by count and refused (`RK-E`).
    case prepaintOnly
    /// Not touched by prepaint or paint, or constant for the frame.
    case frameLocal
    /// Written in the layout phase only (the build runs in lane 1).
    case buildOnly
}

/// Every stored property of `Frame`, with its class. **Adding a stored property to `Frame` owes a row**
/// (`everyFrameChannelIsClassified`).
private let frameChannels: [String: Channel] = [
    // Frame constants and window inputs.
    "contentSize": .keyed, "scaleFactor": .keyed, "timestamp": .frameLocal, "mousePosition": .prepaintOnly,
    "activeElement": .keyed, "stateTable": .recorded, "animationStore": .recorded, "textSystem": .frameLocal,
    "shapingCache": .frameLocal, "glyphAtlas": .frameLocal, "surfaceRegistry": .ledger,
    "tree": .frameLocal, "rootFontSize": .frameLocal, "rootTheme": .frameLocal, "lightTheme": .frameLocal,
    "darkTheme": .frameLocal, "transaction": .keyed, "snapsEveryChange": .frameLocal,
    "collectsAccessibility": .prepaintOnly, "reportsUnlowerableFields": .frameLocal, "recordsElementBounds": .frameLocal,
    // Scroll requests and keys (layout, or prepaint).
    "scrollRequestQueue": .buildOnly, "scrollRequests": .buildOnly, "scrollRequestResolved": .buildOnly,
    "unresolvedScrollRequestCount": .prepaintOnly, "notesScrollKeys": .buildOnly, "scrollKeys": .buildOnly,
    "scrollResolutions": .prepaintOnly, "scrollAnchorAdjustments": .prepaintOnly, "forEachIdentityWork": .buildOnly, "lazyWork": .buildOnly,
    // Animation and lifecycle.
    "wantsAnotherFrame": .ledger, "hasActiveAnimations": .ledger, "timeVaryingNotes": .ledger,
    "transactionTop": .keyed, "transactionDepth": .keyed, "lifecycleDepth": .buildOnly,
    "effectScopesPushed": .frameLocal, "compositeScopesPushed": .frameLocal,
    // Tallies, prepaint's.
    "hoverRegionCount": .prepaintOnly, "pointerStyleRegionCount": .prepaintOnly, "keyRegionCount": .prepaintOnly,
    "focusOnPressCount": .prepaintOnly, "resignRegionCount": .prepaintOnly,
    // Presentations, toolbar, menu bar, popovers.
    "presentationDepth": .buildOnly, "presentationRecords": .buildOnly, "presentationOccurrences": .buildOnly,
    "environmentReadings": .buildOnly, "toolbarRecords": .buildOnly, "drawsToolbarStrip": .frameLocal, "drewToolbarStrip": .frameLocal,
    "menuBarTitles": .frameLocal, "menuBarOpenIndex": .frameLocal, "menuBarOpen": .frameLocal,
    "drewMenuBar": .frameLocal, "menuBarTitleFrames": .frameLocal, "openPopovers": .prepaintOnly,
    "windowControls": .frameLocal, "drewWindowControls": .frameLocal,   // the drawn window buttons (CW-C), the strips' class
    "tooltip": .frameLocal, "menuPresenter": .frameLocal, "presentationAnchors": .prepaintOnly,
    "previousPresentationAnchors": .frameLocal, "presentationSpaces": .prepaintOnly,
    "previousPresentationSpaces": .frameLocal, "wantsAccessibilityRetry": .prepaintOnly,
    // Environment and colour.
    "environmentTop": .keyed, "storedRootEnvironment": .frameLocal, "isRendering": .frameLocal,
    "colorSchemePreferenceDepth": .buildOnly, "mainColorSchemePreference": .buildOnly,
    "presentationColorSchemePreference": .buildOnly, "collectedNavigationTitle": .buildOnly,
    "collectedNavigationDocument": .buildOnly, "openURLHandlers": .buildOnly,
    // Presentation extras (`BG-B`, record 144): the popover bracket's collected fill and its depth, read inside
    // `AnchoredPresentation.requestLayout` only; an open popover is retention-ineligible by name (`BG-F`).
    "presentationBackgroundSlot": .buildOnly, "presentationBracketDepth": .buildOnly,
    "contentSizeLimitsMode": .buildOnly, "contentMinimum": .buildOnly, "contentMaximum": .buildOnly,
    "environmentPushCount": .frameLocal, "environmentSnapshotCount": .frameLocal,
    "environmentTransformCount": .frameLocal,
    // The scene and its stacks.
    "scene": .recorded, "clipStack": .keyed, "clipBase": .keyed, "flatteningClipBase": .keyed,
    "layerStack": .keyed, "opacityStack": .keyed, "portalCount": .frameLocal, "portalStack": .prepaintOnly,
    "scrollContextStack": .buildOnly, "scrollerFrameStack": .prepaintOnly, "paintScopes": .keyed,
    "leafGroup": .keyed, "prepaintEffects": .prepaintOnly, "shareCandidates": .prepaintOnly,
    "shareCollecting": .prepaintOnly, "shareFloor": .prepaintOnly, "shareFloorAtEntry": .prepaintOnly,
    // Hitboxes, accessibility, focus, hover: prepaint's.
    "hitboxes": .prepaintOnly, "hitTestingDisabledDepth": .prepaintOnly, "keyboardHiddenDepth": .prepaintOnly,
    "axNodes": .prepaintOnly, "axEmissions": .prepaintOnly, "accessibilityPressOnly": .prepaintOnly,
    "contextMenuRecords": .prepaintOnly, "namedSpaces": .prepaintOnly, "hitboxNamedSpaces": .prepaintOnly,
    "namedSpaceSnapshots": .prepaintOnly, "accessibilitySuppressionExceptions": .prepaintOnly,
    "focusRegistry": .prepaintOnly, "focusedElement": .keyed, "focusedElementProducedThisFrame": .prepaintOnly,
    "hoveredHitbox": .keyed, "stackAxes": .buildOnly,
    // Layout results.
    "lowering": .buildOnly, "hiddenNodes": .buildOnly, "elementBounds": .prepaintOnly, "unlowerableFields": .buildOnly,
    // Surfaces.
    "surfaceRequests": .ledger,
    // The drawn overlays and the drag preview: owned by the window, painted at the root.
    "dragSourceID": .frameLocal, "menuPanelLevels": .frameLocal, "menuRowsPainted": .frameLocal,
    "pickerTitleWidths": .frameLocal, "alertPanel": .frameLocal, "dragPreviewTranslation": .frameLocal,
    "dragPreviewOrigin": .frameLocal, "previousDragSnapshot": .frameLocal, "dragSnapshot": .frameLocal,
    "dragCapturedPrimitives": .frameLocal,
    // Retained subtrees' own.
    "elementRequests": .frameLocal, "elementPrepaints": .frameLocal, "elementPaints": .frameLocal,
    "retainLog": .frameLocal,
    // C14b-2 (`RK-E`, `RK-D`): the prepaint journal is open only inside a recorder's window; the redo list is
    // read by `Frame.render` after the root's paint and by the window, never replayed.
    "prepaintLog": .frameLocal, "redoEntries": .frameLocal, "verifySnapshot": .frameLocal,
    "verifyAbandoned": .frameLocal,
    // C14-g (`AT-G`): the open effects as steps, a cache dropped whenever the stack changes.
    "axEffectChain": .frameLocal,
    // C14-h (`RL-I`): the effect chain each hitbox was registered under, kept only while a prepaint log records.
    "hitboxChains": .frameLocal,
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
    "markJournal": .recorded, "readJournal": .recorded, "lastReadJournal": .frameLocal, "lastMarkJournal": .frameLocal,
    "comparedWriteCount": .frameLocal, "retainLog": .frameLocal, "generation": .frameLocal, "aliasedStateBoxes": .buildOnly,
    "producedSlots": .buildOnly, "previouslyProducedSlots": .buildOnly, "subtreeResetScans": .buildOnly,
    "absentSlots": .buildOnly, "namedPositions": .buildOnly, "previousNamedPositions": .buildOnly,
    "producedNames": .buildOnly, "departedNames": .buildOnly, "windowedParents": .buildOnly,
    "departedNameResets": .buildOnly, "resetScanWork": .buildOnly, "lastResetScanWork": .buildOnly,
    "loopExtents": .buildOnly, "previousLoopExtents": .buildOnly, "retainsDepartedValues": .buildOnly,
    "departedValues": .buildOnly, "departedRootsKept": .buildOnly, "lastDepartedValueCount": .buildOnly,
    "departedOverlay": .buildOnly, "focusStates": .buildOnly, "departedRoots": .buildOnly, "prepaintLog": .frameLocal,
    "doomedKeys": .buildOnly, "resetFocusSlots": .buildOnly, "isDirty": .ledger, "onWrite": .frameLocal,
    "writeCount": .ledger,
]

private let animationStoreChannels: [String: Channel] = [
    "entries": .recorded, "touched": .recorded, "interpolationsThisFrame": .ledger, "transitions": .ledger,
    "rasters": .recorded, "layoutMemo": .buildOnly, "lifecycle": .buildOnly, "timeline": .buildOnly,
    "keyframeDepth": .buildOnly, "lastFrameInterpolations": .frameLocal, "retainLog": .frameLocal,
    "buildJournal": .buildOnly,
    // Cumulative work counters of `HP-I` (read by differencing); a retained skip does not replay them.
    "borderKeyBuilds": .frameLocal, "numberTrackRebuilds": .frameLocal,
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
    "objects": "fingerprint (identities)", "custom": "fingerprint (readings), an uncomparable one a refusal",
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
    for _ in 0..<4 { await Task.yield() }
    window.window.setNeedsRedraw(); window.tick()
    let after = window.scene.rects.last?.background
    #expect(after != nil && before != nil && (after!.h != before!.h), "the new tone was drawn")
    #expect(window.lastFrameWork.retainedMisses == 1)
    // The miss frame observed only its paint, so its record is not replayed; the next frame records
    // with all three windows observed and the one after replays (`SB-V`).
    var replays = false
    for _ in 0..<3 {
        window.window.setNeedsRedraw(); window.tick()
        replays = replays || window.lastFrameWork.retainedHits == 1
    }
    #expect(replays, "and the new frame is recorded and replays")
}

// MARK: 1.9 — a replayed frame keeps its slots alive

private struct SlotHolder: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Box().frame(width: Pixels(40), height: Pixels(20)).background(Color.accent)
        }
    }
    static func == (l: SlotHolder, r: SlotHolder) -> Bool { true }
}

/// 1.9 — the animated-colour slot (`$anim-color`) of a legacy box inside a replayed subtree stays live over
/// frames that replay it: paint's steady-state `mark` (`AnimatedColor.swift`) is journalled and replayed, so
/// `sweep()` never sees the slot unproduced. Mutation: the `marks` loop of `replayPaint` dropped — after the
/// first replayed frame's sweep the slot reads `isLive == false`.
@MainActor @Test func aReplayedFrameKeepsItsAnimatedColourSlotsAlive() throws {
    let window = try TestWindow(size: Size(width: Pixels(100), height: Pixels(60))) {
        VStack(spacing: 0) { SlotHolder().equatable() }
    }
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    let slots = window.window.stateTable.ids.filter {
        if case .named(let name) = $0.component { return name.name == "$anim-color" }
        return false
    }
    try #require(slots.isEmpty == false, "the legacy background left an animated-colour slot")
    for _ in 0..<3 {
        window.window.setNeedsRedraw(); window.tick()
        #expect(window.lastFrameWork.retainedHits == 1)
        #expect(slots.allSatisfy { window.window.stateTable.isLive($0) }, "live after a replayed frame")
    }
}

// MARK: 1.7b — an observed read in prepaint that paint draws

private struct TonedBox: Element {
    let model: PaintModel
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) -> Hsla {
        // The tone read here, and only here, is the colour paint draws.
        model.tone == 0 ? Hsla(h: 0.6, s: 1, l: 0.5, a: 1) : Hsla(h: 0.0, s: 1, l: 0.5, a: 1)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Hsla,
               pass: inout PaintPass) {
        pass.fill(bounds, color: prepaint)
    }
}

private struct TonedHolder: Component, @MainActor Equatable {
    let model: PaintModel
    var content: some ElementGroup { TonedBox(model: model) }
    static func == (l: TonedHolder, r: TonedHolder) -> Bool { true }
}

/// 1.7b — an `@Observable` read in an element's `prepaint` whose result paint draws invalidates the record
/// (`SB-V`, the prepaint window): prepaint ran with the new tone, and the replayed paint must not show the
/// old. Mutation: the prepaint session dropped (`RetainedSession.run` returns the body for it) — the old
/// colour stays.
@MainActor @Test func anObservedReadInPrepaintInvalidatesTheRecord() async throws {
    let model = PaintModel()
    let window = try TestWindow(size: Size(width: Pixels(100), height: Pixels(60))) {
        VStack(spacing: 0) { TonedHolder(model: model).equatable() }
    }
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    #expect(window.lastFrameWork.retainedHits == 1)
    let before = window.scene.rects.last?.background
    model.tone = 1
    for _ in 0..<4 { await Task.yield() }
    window.window.setNeedsRedraw(); window.tick()
    let after = window.scene.rects.last?.background
    #expect(after != nil && before != nil && after!.h != before!.h, "the new tone was drawn")
    #expect(window.lastFrameWork.retainedHits == 0)
}

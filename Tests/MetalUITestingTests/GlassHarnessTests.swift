import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Liquid Glass, lane C, the window-level tests (rulings `LG-I`, `LG-J`, `LG-K`, `LG-M`, `LG-U`; spec
// `docs/superpowers/specs/2026-10-23-liquid-glass-design.md` §5, tests 25, 26, 30, 32b, 33). PLAIN imports: what an
// app's test target can write. The records are read off `TestWindow.scene`.

private func gpx(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private func glassCircle() -> some ProposalElementGroup {
    Color.clear.frame(width: gpx(60), height: gpx(60)).glassEffect(in: Circle())
}

private struct GlassContainerHolder: Component, @MainActor Equatable {
    let tag: Int
    var content: some ElementGroup {
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: gpx(40)) {
                HStack(spacing: 10) { glassCircle(); glassCircle(); glassCircle() }
            }
        }
    }
}

private struct StandaloneGlassHolder: Component, @MainActor Equatable {
    let tag: Int
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Color.clear.frame(width: gpx(80), height: gpx(40)).glassEffect(.regular.tint(Color.blue.opacity(0.2)))
        }
    }
}

// MARK: - 25

/// **25** (`LG-I`). A container's subtree refuses retention by name: under a warm `.equatable()` component the blob
/// is still emitted frame after frame (members register in prepaint, which no ledger replays) and retention counts
/// the taint `glassContainer`. **Mutation:** drop the taint (the replayed prepaint registers nothing and the blob
/// disappears; also red under `METALUI_VERIFY_RETAINED=1`).
@Test @MainActor func aContainerSubtreeRefusesRetentionByName() throws {
    let window = try harnessWindow { VStack(spacing: 0) { GlassContainerHolder(tag: 1).equatable() } }
    for _ in 0..<6 { window.window.setNeedsRedraw(); window.tick() }
    #expect(window.scene.backdrops.count == 1, "one blob after warm frames: \(window.scene.backdrops.count)")
    #expect(window.scene.backdrops.first?.glassMemberCount == 3, "three members")
    let reasons = window.lastFrameWork.retainedIneligibleReasons
    #expect((reasons["glassContainer"] ?? 0) > 0, "retention refuses by name: \(reasons)")
}

// MARK: - 26

/// **26** (`LG-I`). A standalone glass is a plain paint: a warm `.equatable()` occurrence hits and the scene's
/// backdrop bytes equal the unretained window's. **Mutation:** omit the record from the paint log (the replay loses
/// the record).
@Test @MainActor func aStandaloneGlassReplaysItsRecordUnderRetention() throws {
    func make(retained: Bool) throws -> TestWindow {
        let w = try harnessWindow { VStack(spacing: 0) { StandaloneGlassHolder(tag: 1).equatable() } }
        w.window.testingRetainedSubtrees = retained
        for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
        return w
    }
    let on = try make(retained: true), off = try make(retained: false)
    on.window.setNeedsRedraw(); on.tick()
    #expect(on.lastFrameWork.retainedHits >= 1, "the occurrence replayed: \(on.lastFrameWork.retainedHits)")
    func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
    #expect(!on.scene.backdrops.isEmpty, "the glass drew a record")
    #expect(bytes(on.scene.backdrops) == bytes(off.scene.backdrops), "the replay is a fresh frame's record")
}

// MARK: - 30, 32b

/// **30** (`LG-J`). A pressed `.glass` button lifts its record's tint: `press` is 1 while the primary press is held
/// over it and 0 after the release, and `pressLift` is nonzero. **Mutation:** read hover only (press 1 before the
/// press, or never 0).
@Test @MainActor func aPressedGlassButtonLiftsItsTint() throws {
    let window = try harnessWindow { VStack(spacing: 0) { Button("Go") {}.buttonStyle(.glass) } }
    window.tick()
    let center = try window.element(label: "Go").frame
    let point = pt(center.origin.x.value + center.size.width.value / 2, center.origin.y.value + center.size.height.value / 2)
    window.hover(at: point)
    let hovered = try #require(window.scene.backdrops.first)
    #expect(hovered.press == 0, "hover alone does not press: \(hovered.press)")
    _ = window.send(.mouseDown(MouseEvent(position: point)))
    window.tick()
    let pressed = try #require(window.scene.backdrops.first)
    #expect(pressed.press == 1 && pressed.pressLift > 0, "press \(pressed.press) lift \(pressed.pressLift)")
    _ = window.send(.mouseUp(MouseEvent(position: point)))
    window.tick()
    #expect(try #require(window.scene.backdrops.first).press == 0, "released")
}

/// **32b** (`LG-M`). A glass button keeps the button's keyboard and focus: Tab reaches it and Space fires it.
/// **Mutation:** the glass style drops the focus registration.
@Test @MainActor func aGlassButtonKeepsItsKeyboardAndFocus() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        VStack(spacing: 0) { Button("Go") { log.add("go") }.buttonStyle(.glass) }
    }
    window.typeKey(.tab)
    #expect(try window.focusedElement?.label == "Go", "Tab reaches it")
    window.typeKey(.space)
    #expect(log.entries == ["go"], "Space fires it: \(log.entries)")
}

// MARK: - 33

@MainActor private final class NamespaceLog { var ids: [[AnyHashable]] = [] }

private struct NamespaceHolder: Component {
    @Namespace var first
    @Namespace var second
    let log: NamespaceLog
    var content: some ElementGroup {
        log.ids.append([AnyHashable(first), AnyHashable(second)])
        return VStack(spacing: 0) { Color.clear.frame(width: gpx(10), height: gpx(10)) }
    }
}

/// **33** (`LG-K`; probe arm A10, `glassEffectID(_:in:)` over a namespace). A `Namespace.ID` is stable across frames and distinct per declaration (two `@Namespace`s in one
/// component, and two components), with no eighth reserved slot (`theSevenRetentionSlotsAreMutuallyDistinct` is run
/// unfiltered). **Mutation:** a per-frame id.
@Test @MainActor func aNamespaceIdIsStableAcrossFramesAndDistinctPerDeclaration() throws {
    let a = NamespaceLog(), b = NamespaceLog()
    let window = try harnessWindow {
        VStack(spacing: 0) { NamespaceHolder(log: a); NamespaceHolder(log: b) }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let first = try #require(a.ids.last), later = try #require(a.ids.dropLast(2).last)
    #expect(first == later, "stable across frames")
    #expect(a.ids.count >= 3)
    #expect(first[0] != first[1], "two declarations in one component are two ids")
    let other = try #require(b.ids.last)
    #expect(Set(first + other).count == 4, "four declarations, four ids: \(first) \(other)")
}

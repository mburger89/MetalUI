import Foundation
import Metal
import Observation
import Testing
import MetalUICore
@testable import MetalUILayout
import MetalUIPlatform
@testable import MetalUI
@testable import MetalUIDemoContent

// Plan task 7, stage 1, lane 5 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
// §6 lane 5; rulings LR-K, LR-Q, LR-AA): what happens AFTER layout — click
// dispatch, focus, the keymap, the accessibility tree, `@State` slots and
// animation, driven through a real `Window` (until stage 9 one per authority, a
// `WindowPair`, compared; since then one, against literals: `LR-FE` item 4,
// record §51 lane 1) — and the lowering's own cost: its native work on a
// branching tree, and the native depth guard's boundary under lowering.
//
// **Red before.** 5.4–5.6 did not compile on lane 4's tree (`Window` had no
// element bounds log); 5.7's literals were derived by hand before the first run;
// 5.8 and 5.9 pin the existing guard. What proves each can fail is its mutation
// (spec §6's lane-5 table; the record names what each reddened).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int, _ name: String? = nil) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: name.map { ElementID($0) })
}

/// Where the counter element sits: named, like the demo's, the one child of a
/// 400-wide `Column` under the harness root (`counterColumn()`).
private let counterElementID = child(child(rootID, 0), 0, "counter")

@MainActor
private func click(_ platform: FakePlatformWindow, at position: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: position)))
    platform.simulateInput(.mouseUp(MouseEvent(position: position)))
}

private func keyDown(_ characters: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                      modifiers: [], timestamp: 0))
}

/// The demo's own `CounterPanel()`, imported from `MetalUIDemoContent` (ruling
/// LR-S), in a 400-wide `Column` (its centring default).
///
/// **Stage 2 replaced the lane-5 copy** (`LowerableCounter`, which cleared the
/// chrome's `.alignSelf(.flexStart)` because stage 1 could not lower it; ruling
/// LR-AA item 2). The chrome's `alignSelf` is an item field, lowered by its parent
/// (ruling LR-AD), so the panel needs a lowered flex parent: directly under the
/// harness root — a proposal overlay — its record is unconsumed and reports
/// `box.alignSelf.unconsumed` (ruling LR-AQ). The column declares its width, so its
/// greedy alignment frame (divergence X14) and the legacy column agree at 400; the
/// chrome sits at x 0 under both.
@MainActor
private func counterColumn() -> some ElementGroup {
    Column { CounterPanel() }.cssWidth(px(400))
}

/// The count `CounterPanel` holds in `window`'s state table.
@MainActor
private func count(in window: Window) -> Int? {
    window.stateTable.peek(child(counterElementID, 0, "$state0"), as: Int.self)
}

// MARK: - 5.4 — clicks, focus and keys

/// **5.4.** Through a real `Window`, the counter — the demo's `CounterPanel()` in
/// a 400-wide column inside `DifferentialRoot` (400×400) — dispatches clicks,
/// focus and a keymap action to the right elements:
///
/// 1. the first frame: 12 elements since stage 8 (root, column, counter, three
///    `.frame` layers, three boxes, three texts), the chrome at (0, 0) 260×60 and
///    "+" at (212, 12) 36×36, and exactly the two buttons' hitboxes;
/// 2. "+" clicked twice at its centre (230, 30): count 2;
/// 3. `window.focus(counter)`: the counter is focused;
/// 4. "=" (bound to the library's `Increment` in context `"Counter"`, as
///    `runDemo` binds it): count 3, the readout drawing its eight glyphs
///    (`-`, `Count 3` less its space, `+`).
///
/// And nothing trapped, which a production frame would have if the tree did not
/// lower. Until stage 9 each step also compared the legacy window's element
/// bounds, scene, hitboxes and state ids with this one's (`WindowPair`); the
/// literals above are what that comparison carried (`LR-FE` items 2 and 4).
///
/// Mutations that must redden it: **M5d**, lowered stack spacing + 50 (the chrome
/// is 360 wide, "+" at x 312, and the click at 230 lands on the readout: count 0);
/// **M1n** (stage 2, lane 1), the chrome's alignment frame aliased as its rect
/// (the chrome's bounds widen to the column's 400).
///
/// **Renamed at stage 9** from `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`
/// (`LR-FE` item 6).
@MainActor
@Test func aLoweredWindowDispatchesClicksFocusAndKeys() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeLoweredWindow(device: device, size: 400) { counterColumn() }
    window.keymap = Keymap { KeyBinding("=", Increment(), context: "Counter") }
    window.drawFrameIfNeeded()
    // 12 since stage 8 (`LR-EZ`): the counter's three squares each gained a
    // `.frame` layer, one identity level apiece (`LR-ES`'s R7) — 9 + 3.
    try #require(window.lastElementBounds.count == 12, "\(window.lastElementBounds.count)")
    #expect(window.lastElementBounds[counterElementID] == bounds(0, 0, 260, 60))
    #expect(window.lastElementBounds[child(counterElementID, 2)] == bounds(212, 12, 36, 36))
    #expect(window.lastHitboxes.map(\.bounds) == [bounds(12, 12, 36, 36), bounds(212, 12, 36, 36)],
            "\(window.lastHitboxes.map(\.bounds))")

    click(platform, at: pt(230, 30))
    window.drawFrameIfNeeded()
    click(platform, at: pt(230, 30))
    window.drawFrameIfNeeded()
    #expect(count(in: window) == 2)

    window.focus(counterElementID)
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == counterElementID)

    #expect(platform.simulateInput(keyDown("=")), "the keymap claims '='")
    window.drawFrameIfNeeded()
    #expect(count(in: window) == 3)
    #expect(window.lastScene.glyphs.count == 8, "\(window.lastScene.glyphs.count)")
}

// MARK: - 5.5 — the accessibility tree

/// **5.5.** The root publishes its accessibility tree: activated (`.activate`),
/// drawn, then after a click on "+" and a focus move. The tree is not empty: it
/// holds the "Decrement" and "Increment" buttons with their frames at (12, 12)
/// and (212, 12), at least two trees were published, and the window records 12
/// elements (a `try #require`, stage 2 lane 1; 12 since stage 8). Until stage 9
/// every tree was compared, in order, with the legacy window's (`WindowPair`).
///
/// Mutations that must redden it: **M5d** (the buttons' geometry moves); **M1n**
/// (the counter's accessibility frame widens to the column's 400).
///
/// **Renamed at stage 9** from `aLoweredWindowPublishesTheSameAccessibilityTree`
/// (`LR-FE` item 6).
@MainActor
@Test func aLoweredWindowPublishesItsAccessibilityTree() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeLoweredWindow(device: device, size: 400) { counterColumn() }
    #expect(platform.simulateAccessibilityRequest(.activate))
    window.drawFrameIfNeeded()
    click(platform, at: pt(230, 30))
    window.drawFrameIfNeeded()
    window.focus(counterElementID)
    window.drawFrameIfNeeded()
    let trees = platform.publishedAccessibilityTrees
    try #require(trees.count >= 2, "\(trees.count)")
    let last = try #require(trees.last)
    let frames = last.nodes.compactMap { id, node -> Bounds<Pixels>? in
        guard node.label == "Increment" || node.label == "Decrement" else { return nil }
        return last.geometry[id]?.frame
    }
    #expect(Set(frames.map { "\($0)" }) == Set([bounds(12, 12, 36, 36), bounds(212, 12, 36, 36)].map { "\($0)" }))
    // 12 since stage 8 (`LR-EZ`), as in 5.4 above.
    try #require(window.lastElementBounds.count == 12, "\(window.lastElementBounds.count)")
}

// MARK: - 5.6 — state slots and animation

@Observable
private final class WidthModel {
    var wide = false
}

/// **5.6.** The root mints its `StateTable` ids — `CounterPanel()`'s (in
/// `counterColumn()`, stage 2 lane 1) `$state0` (written by a click on "+"; an unwritten count had no entry when this
/// was first run), `$focus` and `$anim` slots, and the "+" button's `$ax` slot
/// (its declared label; a synthesized node is a record, never a slot, `AB-U`, so
/// the unlabelled counter has none — also found by the first run) — and animates
/// its widths (under both authorities until stage 9, whose windows' ids were
/// compared).
///
/// A `.flexStart` column in `DifferentialRoot` (400×400) over a `Box` whose width
/// animates 196 → 320 and a 20×10 box under a `.frame(width:height: 20)` layer
/// whose width does the same, one `withAnimation(.linear(duration: 1))` driven
/// through the display link: at t = 100 (before), t = 100 (the frame that starts
/// the transaction) and t = 100.5, both widths read **196, 196, 258** (the
/// prototype measured the `Box`, record §18 P1).
///
/// Mutation that must redden it: **M5e**, `Box` hands `lowerLegacyNode` the style
/// captured before `animated(…)` (the lowered box reads 320 at the transaction's
/// start).
///
/// **Renamed at stage 9** from `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`
/// (`LR-FE` item 6).
@MainActor
@Test func aLoweredTreeMintsItsStateSlotsAndAnimatesItsWidths() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (counter, counterPlatform) = try makeLoweredWindow(device: device, size: 400) { counterColumn() }
    #expect(counterPlatform.simulateAccessibilityRequest(.activate))
    counter.drawFrameIfNeeded()
    click(counterPlatform, at: pt(230, 30))
    counter.drawFrameIfNeeded()
    counter.focus(counterElementID)
    counter.drawFrameIfNeeded()
    let ids = counter.stateTable.ids
    let plus = child(counterElementID, 2)
    for (owner, slot) in [(counterElementID, "$state0"), (counterElementID, "$focus"),
                          (counterElementID, "$anim"), (plus, "$ax")] {
        #expect(ids.contains { $0.parent == owner && $0.component == .named(ElementID(slot)) }, "slot \(slot)")
    }

    func animatedColumn(_ width: Float) -> some ElementGroup {
        Column {
            Box().cssWidth(px(width)).cssHeight(px(20)).background(.accent)
            Box().cssWidth(px(20)).cssHeight(px(10)).frame(width: px(width), height: px(20))
        }
        .alignItems(.flexStart)
    }
    // The pre-flight `makeLoweredWindow` runs, for both ends of the animation: a
    // report here would otherwise trap inside the window below and end the run.
    for width: Float in [196, 320] {
        let preflight = LayoutDifferential.report(width: 400, height: 400) { animatedColumn(width) }
        try #require(preflight.unlowerable.isEmpty, "\(width): \(preflight.unlowerable)")
    }
    let column = child(rootID, 0)
    let model = WidthModel()
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        DifferentialRoot(width: 400, height: 400) { animatedColumn(model.wide ? 320 : 196) }
    }
    window.recordsElementBounds = true
    func read() -> [Float] {
        [child(column, 0), child(column, 1)].map { window.lastElementBounds[$0]?.size.width.value ?? -1 }
    }
    platform.simulateTick(timestamp: 100)
    var series = [read()]
    withAnimation(.linear(duration: 1)) { model.wide = true }
    platform.simulateTick(timestamp: 100)
    series.append(read())
    platform.simulateTick(timestamp: 100.5)
    series.append(read())
    #expect(series == [[196, 196], [196, 196], [258, 258]], "\(series)")
}

// MARK: - 5.7 — native work on a branching tree

/// **5.7** (`SA-M`'s method). `Column { Row { a; b }; Row { c; Box { d }.padding(4) } }`
/// of fixed leaves — a 10×20, b 30×10, c 20×10, d 10×10, every gap 0 — inside a
/// 200×100 harness root under the proposal authority: the native node count and
/// the one layout call's `lastNativeLayoutWork`, as literals **derived by hand
/// before the run**.
///
/// **The registered tree (16 nodes).** A fixed leaf is a 0×0 leaf `L` in a fixed
/// `.topLeading` frame `F` (2 each: `La/Fa`, `Lb/Fb`, `Lc/Fc`, `Ld/Fd`). Each row is
/// one horizontal stack (`S1` over `Fa, Fb`; `S2` over `Fc, P`), the column one
/// vertical stack `SC` over `S1, S2`. `Box { d }` is one horizontal stack `SB` over
/// `Fd` (one child, no cross size: its stretch is lowerable); its `.padding(4)`
/// layer is a one-child container — a horizontal stack `SP` over `SB` — in a native
/// padding `P`. The harness root is an overlay `O` in a fixed 200×100 frame `R`.
/// 8 + 2 + 1 + 1 + 2 + 2 = **16**.
///
/// **Measurement** (a miss runs a body; a hit finds its key; a call is a leaf
/// closure). `R` → `O` → `SC` at (200, 100): 3 misses. `SC` probes `S1` and `S2`
/// at (200, ∞) and (200, 0), then offers `S1` 50 (→ 20 tall) and `S2` 80.
///
/// - `S1` at (200, c): its miss, then `Fa` and `Fb` each at (∞, c), (0, c) and
///   their offers (100, c) / (190, c) — 6 misses — each asking its leaf at its
///   fixed size (6 lookups). At c = ∞ the two leaves miss and are called once
///   each: **9 misses, 4 hits, 2 calls**; at c = 0 and 50: **7 misses, 6 hits**.
///   Total 23 / 16 / 2.
/// - `S2` at (200, c), with c′ = max(0, c − 8): its miss; `Fc` at (∞, c), (0, c),
///   (100, c) — 3 misses, 3 leaf lookups; `P` at (∞, c), (0, c), (180, c), each a
///   chain `P` → `SP` (∞ / 0 / 172, c′) → `SB` → `Fd` — 12 misses, 3 leaf lookups.
///   At c = ∞: **18 misses, 4 hits, 2 calls**; at c = 0 and 80 (c′ 0, 72): **16
///   misses, 6 hits**. Total 50 / 16 / 2.
///
/// Measurement: **76 misses, 32 hits, 4 calls.**
///
/// **Placement.** `R` re-asks `O` (1 hit) and places it at its answer, 40×38 (the
/// row widths 40 and 38; heights 20 + 18). `O` proposes `SC` its own size, (40, 38):
/// a new key, so `SC` is solved again —
///
/// - `S1` at (40, ∞) and (40, 0): the four probes hit, `Fa` (20, c) and `Fb` (30, c)
///   miss, their leaves hit: 3 misses, 6 hits each; `S1` at (40, 19), a new cross:
///   7 misses, 6 hits;
/// - `S2` at (40, ∞) and (40, 0): four probe hits, `Fc` (20, c) misses, the chain
///   `P` (20, c) → `SP` (12, c′) → `SB` → `Fd` misses 4, two leaf hits: 6 misses,
///   6 hits each; `S2` at (40, 18), c′ = 10: 16 misses, 6 hits;
///
/// with `SC`'s own miss: **42 misses, 36 hits**. Then placing `SC` re-solves at
/// (40, 38): 6 hits; `S1` re-solves at (40, 19): 6 hits, and its frames re-ask
/// their leaves: 2; `S2` re-solves at (40, 18): 6 hits, `Fc`'s leaf 1, `P` asks `SP`
/// at (12, 10), `SP` asks `SB`, `SB` asks `Fd`, `Fd` asks `Ld`: 4. Placement: **42
/// misses, 62 hits, 0 calls.**
///
/// **Totals: 118 misses, 94 hits, 4 calls.**
///
/// Mutation that must redden it: **M5f**, every lowered node wrapped in an extra
/// native `padding(0)` (the node count and every figure move).
@MainActor
@Test func aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork() throws {
    let frame = LayoutDifferential.render(width: 200, height: 100) {
        Column {
            Row { Box().cssWidth(px(10)).cssHeight(px(20)); Box().cssWidth(px(30)).cssHeight(px(10)) }
            Row { Box().cssWidth(px(20)).cssHeight(px(10)); Box { Box().cssWidth(px(10)).cssHeight(px(10)) }.padding(px(4)) }
        }
    }
    try #require(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
    #expect(frame.tree.nodeCount == 16)
    let work = frame.tree.lastNativeLayoutWork
    #expect(work.cacheMisses == 118, "cacheMisses")
    #expect(work.cacheHits == 94, "cacheHits")
    #expect(work.measureCalls == 4, "measureCalls")
    // The placement the derivation assumed: the column 40×38, the second row at
    // (1, 20), the padded box's frame at (25, 24).
    let column = child(rootID, 0)
    #expect(frame.elementBounds[column] == bounds(0, 0, 40, 38))
    #expect(frame.elementBounds[child(column, 1)] == bounds(1, 20, 38, 18))
    #expect(frame.elementBounds[child(child(child(child(column, 1), 1), 0), 0)] == bounds(25, 24, 10, 10))
}

// MARK: - 5.8, 5.9 — the native depth guard under lowering

/// `n` nested `Box`es, outermost first, each with `Style.padding` 1, `.flexStart`
/// cross alignment and a declared size just large enough for its content (the
/// innermost 2×2, each parent 2 larger), so no `padding.floor` is reported. Each
/// lowers to three native levels — content (a linear stack, or the innermost's
/// 0×0 leaf) → padding → fixed frame — counted by hand against
/// `NativeLayoutRun.enter`, which every `measureNative` and `placeNative` call
/// enters: measuring the outermost frame enters frame, padding, stack, then the
/// next box's frame, …, the innermost's leaf at depth 3n. The inner `n − 1` are
/// built through `AnyElement`, which adds no node and no native level; the
/// outermost is a concrete `Box`, because a frame's root must be an `Element`.
@MainActor
private func nestedPaddedBoxes(_ n: Int) -> Box<AnyElement> {
    func style(_ side: Int) -> Style {
        var s = Style()
        s.padding = Edges(all: .pixels(px(1)))
        s.alignItems = .flexStart
        s.size = Size(width: .length(.pixels(px(Float(side)))), height: .length(.pixels(px(Float(side)))))
        return s
    }
    var element = AnyElement(Box(style: style(2)))
    for level in 1..<(n - 1) {
        let inner = element
        element = AnyElement(Box(style: style(2 + 2 * level)) { inner })
    }
    let inner = element
    return Box(style: style(2 * n)) { inner }
}

/// **5.8** (`LR-Q`, re-derived by stage 6b's lane 1 for `LR-DK`'s 72). A chain of
/// **24** such `Box`es — **72** native levels, exactly `NativeLayoutRun.maxDepth`
/// (which itself is allowed; 29 boxes / 87 levels against the old 88, which
/// bracketed rather than pinned the limit) — laid out as a **production**
/// frame's root (no harness root, whose overlay and frame would add two levels)
/// under the proposal authority. **An exit test whose child expects success**, so
/// a mutation that makes it trap reddens this test by name instead of ending the
/// run with no summary line.
///
/// The child prints the node count (72, three per `Box`) and the run's deepest native
/// level with the limit (`LayoutTree.lastNativeLayoutDeepestLevel`, `LR-DK`): both
/// 72, so a limit moved either way reddens this arm.
///
/// Mutation that must redden it: **M5g**, the lowering emits a fourth native level
/// per `Box` (an extra `padding(0)`: 96 levels, the child traps).
@Test func aLoweredChainAtTheNativeDepthLimitLaysOut() async {
    let result = await #expect(processExitsWith: .success,
                               observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            var root = nestedPaddedBoxes(24)
            let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1)
            frame.render(&root)
            let line = "LANE5-5.8 nodes=\(frame.tree.nodeCount) deepest=\(frame.tree.lastNativeLayoutDeepestLevel)"
                + " limit=\(NativeLayoutRun.maxDepth)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
    }
    let out = String(decoding: result?.standardOutputContent ?? [], as: UTF8.self)
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(out.contains("LANE5-5.8 nodes=72 deepest=72 limit=72\n"), "stdout:\n\(out)\nstderr:\n\(err)")
}

/// **5.9** (`LR-Q`, re-derived for `LR-DK`). The same chain one `Box` longer —
/// **25**, 75 native levels — traps with `SA-L`'s message, as an exit test.
///
/// Mutation that must redden it: **M5h**, `NativeLayoutRun.maxDepth` raised to 80
/// (the child succeeds); **M3e** (stage 6b), back to 88.
@Test func aLoweredChainOneLevelPastTheNativeDepthLimitTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = nestedPaddedBoxes(25)
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1).render(&root)
        }
    }
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(err.contains("native layout recursion exceeded 72 levels"), "stderr:\n\(err)")
}

// MARK: - Stage 2, lane 2 — 2.14, the depth guard with three item wrappers per level

/// A chain of `rows` nested `Row`s (plan task 7, stage 2, spec 2.14; ruling LR-AB as
/// amended): the outermost a production root declaring 100×100; each inner row the
/// first of its parent's two children (the second a fixed 10×10), declaring
/// `flexShrink(0)`, `flexGrow(1)` and `alignSelf(.flexEnd)`. In a centring `Row` with
/// an `auto` main size, those three are the three item wrappers a parent registers
/// around the child, innermost first: `fixedSize` (horizontal), the greedy item frame
/// W, and the alignment frame (vertical, factor 1 against the row's ½). The innermost
/// row's first child declares the same three fields and is
///
/// - (`containerInnermost` false) `Box().height(10)` with `Style.padding` 1: its own
///   fixed frame over a native padding over its 0×0 leaf — 3 native levels;
/// - (true) a `Box` with `Style.padding` 1 over `Box().height(10)`: a native padding
///   over its linear stack over the child's frame over its leaf — 4 levels.
///
/// **Native depth, by hand** (`NativeLayoutRun.enter` on every `measureNative` and
/// `placeNative`, one counter): the root's fixed frame is 1 and its stack 2; each of
/// the 16 inner rows adds its parent's three wrappers and its own stack, 4 levels, so
/// the 17th row's stack is at 2 + 16·4 = 66; its first child's three wrappers reach
/// 69, and the child's own nodes **72** (3 levels) or **73** (4). (20 inner rows,
/// 88 / 89, until stage 6b's lane 1 moved the limit to 72, `LR-DK`.) No axis is proposed
/// `nil` on a cross axis anywhere in the chain (the root proposes 100 tall, and W and
/// the alignment frame pass concrete proposals through), so no stack re-measures
/// itself during placement at one level deeper than its measurement.
///
/// **Nodes, by hand**: 17 rows × (a stack + the fixed sibling's frame and leaf) = 51;
/// the root's frame 1; 16 inner rows' wrappers 48; the innermost child's wrappers 3 and
/// its own nodes 3 (or 4): **106** (or **107**). (130 / 131 at 20 inner rows.)
@MainActor
private func itemChain(containerInnermost: Bool) -> some Element {
    var padded = Style()
    padded.padding = Edges(all: .pixels(px(1)))
    var element = containerInnermost
        ? AnyElement(Box(style: padded) { Box().cssHeight(px(10)) }.flexShrink(0).flexGrow(1).alignSelf(.flexEnd))
        : AnyElement(Box(style: padded).cssHeight(px(10)).flexShrink(0).flexGrow(1).alignSelf(.flexEnd))
    for _ in 0..<16 {
        let inner = element
        element = AnyElement(Row { inner; Box().cssWidth(px(10)).cssHeight(px(10)) }
            .flexShrink(0).flexGrow(1).alignSelf(.flexEnd))
    }
    let inner = element
    return Row { inner; Box().cssWidth(px(10)).cssHeight(px(10)) }.cssWidth(px(100)).cssHeight(px(100))
}

/// **2.14, limit** (`LR-AB` as amended, `SA-L`). `itemChain(containerInnermost: false)`
/// — 72 native levels, `NativeLayoutRun.maxDepth` itself, every level of the 16 inner
/// rows carrying three item wrappers — lays out as a production frame's root under the
/// proposal authority, in a child process that must exit successfully and print the
/// node count derived by hand (106) and the run's deepest level with the limit (72,
/// 72). With 2.14's trap arm this pins the boundary at exactly 72 / 73.
///
/// **Red before** (lane 1): the chain's `flexGrow` and `flexShrink` are reported, and a
/// production frame traps on the first.
@Test func aLoweredItemChainWithThreeWrappersPerLevelAtTheNativeDepthLimitLaysOut() async {
    let result = await #expect(processExitsWith: .success,
                               observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            var root = itemChain(containerInnermost: false)
            let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1)
            frame.render(&root)
            FileHandle.standardOutput.write(Data(("LANE2-2.14 nodes=\(frame.tree.nodeCount)"
                + " deepest=\(frame.tree.lastNativeLayoutDeepestLevel) limit=\(NativeLayoutRun.maxDepth)\n").utf8))
        }
    }
    let out = String(decoding: result?.standardOutputContent ?? [], as: UTF8.self)
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(out.contains("LANE2-2.14 nodes=106 deepest=72 limit=72\n"), "stdout:\n\(out)\nstderr:\n\(err)")
}

/// **2.14, one past** (`SA-L`). `itemChain(containerInnermost: true)` — 73 native
/// levels — traps with `SA-L`'s message, as an exit test.
///
/// Mutation that must redden it: **M2q** `NativeLayoutRun.maxDepth` raised by 8 (the
/// child succeeds).
@Test func aLoweredItemChainWithThreeWrappersPerLevelOnePastTheNativeDepthLimitTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = itemChain(containerInnermost: true)
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1).render(&root)
        }
    }
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(err.contains("native layout recursion exceeded 72 levels"), "stderr:\n\(err)")
}

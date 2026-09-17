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
// §6 lane 5; rulings LR-K, LR-Q, LR-AA): what happens AFTER layout is the same
// under both layout authorities — click dispatch, focus, the keymap, the
// accessibility tree, `@State` slots and animation, each driven through a real
// `Window` per authority (`WindowPair`, `LayoutDifferential.swift`) — and the
// lowering's own cost: its native work on a branching tree, and the native depth
// guard's boundary under lowering.
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

/// Where the counter element sits under the harness root: named, like the demo's.
private let counterElementID = child(rootID, 0, "counter")

@MainActor
private func click(_ platform: FakePlatformWindow, at position: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: position)))
    platform.simulateInput(.mouseUp(MouseEvent(position: position)))
}

private func keyDown(_ characters: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                      modifiers: [], timestamp: 0))
}

/// The demo's `CounterPanel`, over the corpus's lowerable chrome
/// (`StageOneCorpus.counterChrome`: the library's `CounterPanel.chrome` minus its
/// `.alignSelf(.flexStart)`, ruling LR-AA).
///
/// **The one copy in this lane, and why.** `CounterPanel` itself applies
/// `.alignSelf(.flexStart)` inside `requestLayout`, which traps under the
/// proposal authority in a `Window` (a production frame). This element repeats
/// its `requestLayout` wiring — one `@State` count, the chrome's minus and plus
/// closures and the two `onAction` handlers capturing the same `State` — and
/// drops only what is the demo's rather than the counter's: publishing
/// `counterID` and focusing itself on the first frame (the test focuses by the
/// same id instead). Stage 2, which lowers `alignSelf`, replaces this with
/// `CounterPanel()` itself.
@MainActor
private struct LowerableCounter: Element {
    @State var count = 0

    var elementID: ElementID? { ElementID("counter") }

    private var built: Box<CounterPanel.Chrome> = StageOneCorpus.counterChrome()

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Box<CounterPanel.Chrome>.Layout) {
        let state = _count
        var box = StageOneCorpus.counterChrome(count: state.wrappedValue,
                                               minus: { state.wrappedValue -= 1 },
                                               plus: { state.wrappedValue += 1 })
        box = box
            .onAction(Increment.self) { _ in state.wrappedValue += 1 }
            .onAction(Decrement.self) { _ in state.wrappedValue -= 1 }
        let result = box.requestLayout(id, pass: &pass)
        built = box
        return result
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Box<CounterPanel.Chrome>.Layout,
                           pass: inout PrepaintPass) -> CounterPanel.Chrome.GroupPrepaint {
        built.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Box<CounterPanel.Chrome>.Layout,
                        prepaint: inout CounterPanel.Chrome.GroupPrepaint,
                        pass: inout PaintPass) {
        built.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// The count `LowerableCounter` holds in `window`'s state table.
@MainActor
private func count(in window: Window) -> Int? {
    window.stateTable.peek(child(counterElementID, 0, "$state0"), as: Int.self)
}

/// Every whole-frame observation of a window pair agrees.
@MainActor
private func expectWindowAgreement(_ r: LayoutDifferential.Report, _ step: String,
                                   sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.disagreeing.isEmpty, "\(step): \(r.disagreeing)", sourceLocation: sourceLocation)
    #expect(r.legacyOnly.isEmpty && r.loweredOnly.isEmpty,
            "\(step): legacyOnly \(r.legacyOnly) loweredOnly \(r.loweredOnly)", sourceLocation: sourceLocation)
    #expect(r.scenesEqual, "\(step): scenes", sourceLocation: sourceLocation)
    #expect(r.hitboxesEqual, "\(step): hitboxes", sourceLocation: sourceLocation)
    #expect(r.accessibilityEqual, "\(step): accessibility", sourceLocation: sourceLocation)
    #expect(r.stateSlotsEqual, "\(step): state slots", sourceLocation: sourceLocation)
}

// MARK: - 5.4 — clicks, focus and keys

/// **5.4.** Through a real `Window` per authority, the counter — the demo's chrome
/// inside `DifferentialRoot` (400×400) — dispatches clicks, focus and a keymap
/// action to the same elements:
///
/// 1. the first frame: 8 elements (root, counter, three boxes, three texts), all
///    agreeing, the chrome at (0, 0) 260×60 and "+" at (212, 12) 36×36;
/// 2. "+" clicked twice at its centre (230, 30): count 2 under both;
/// 3. `window.focus(counter)`: the counter is focused under both (its
///    `focusBackground` paints — the scenes still agree);
/// 4. "=" (bound to the library's `Increment` in context `"Counter"`, as
///    `runDemo` binds it): count 3 under both, and the readout's glyphs agree.
///
/// After every step: element bounds, the finalized scene, hitboxes, the state
/// table's ids — and nothing trapped, which a production frame would have if the
/// tree did not lower.
///
/// Mutation that must redden it: **M5d**, lowered stack spacing + 50 (the chrome
/// is 360 wide, "+" at x 312, and the click at 230 lands on the readout: count 0).
@MainActor
@Test func aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let pair = try WindowPair(device: device, size: 400) { LowerableCounter() }
    pair.both { window, _ in
        window.keymap = Keymap { KeyBinding("=", Increment(), context: "Counter") }
        window.drawFrameIfNeeded()
    }
    let first = pair.report()
    try #require(first.elements == 8, "\(first.elements)")
    expectWindowAgreement(first, "first frame")
    #expect(pair.lowered.window.lastElementBounds[counterElementID] == bounds(0, 0, 260, 60))
    #expect(pair.lowered.window.lastElementBounds[child(counterElementID, 2)] == bounds(212, 12, 36, 36))

    pair.both { window, platform in
        click(platform, at: pt(230, 30))
        window.drawFrameIfNeeded()
        click(platform, at: pt(230, 30))
        window.drawFrameIfNeeded()
    }
    #expect(count(in: pair.legacy.window) == 2)
    #expect(count(in: pair.lowered.window) == 2)
    expectWindowAgreement(pair.report(), "two clicks")

    pair.both { window, _ in
        window.focus(counterElementID)
        window.drawFrameIfNeeded()
    }
    #expect(pair.legacy.window.focusedElement == counterElementID)
    #expect(pair.lowered.window.focusedElement == counterElementID)
    expectWindowAgreement(pair.report(), "focused")

    pair.both { window, platform in
        #expect(platform.simulateInput(keyDown("=")), "the keymap claims '='")
        window.drawFrameIfNeeded()
    }
    #expect(count(in: pair.legacy.window) == 3)
    #expect(count(in: pair.lowered.window) == 3)
    expectWindowAgreement(pair.report(), "Increment")
}

// MARK: - 5.5 — the accessibility tree

/// **5.5.** The same root publishes the same accessibility tree under both
/// authorities: activated (`.activate`), drawn, then after a click on "+" and a
/// focus move — every tree each window published, compared in order
/// (`AccessibilityTree` is `Equatable`: nodes, geometry, hierarchy, focus). The
/// tree is not empty: it holds the "Decrement" and "Increment" buttons with their
/// frames at (12, 12) and (212, 12).
///
/// Mutation that must redden it: **M5d** (the buttons' geometry moves).
@MainActor
@Test func aLoweredWindowPublishesTheSameAccessibilityTree() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let pair = try WindowPair(device: device, size: 400) { LowerableCounter() }
    pair.both { window, platform in
        #expect(platform.simulateAccessibilityRequest(.activate))
        window.drawFrameIfNeeded()
        click(platform, at: pt(230, 30))
        window.drawFrameIfNeeded()
        window.focus(counterElementID)
        window.drawFrameIfNeeded()
    }
    let legacyTrees = pair.legacy.platform.publishedAccessibilityTrees
    try #require(legacyTrees.count >= 2, "\(legacyTrees.count)")
    try #require(pair.lowered.platform.publishedAccessibilityTrees.count == legacyTrees.count)
    let last = try #require(pair.lowered.platform.publishedAccessibilityTrees.last)
    let frames = last.nodes.compactMap { id, node -> Bounds<Pixels>? in
        guard node.label == "Increment" || node.label == "Decrement" else { return nil }
        return last.geometry[id]?.frame
    }
    #expect(Set(frames.map { "\($0)" }) == Set([bounds(12, 12, 36, 36), bounds(212, 12, 36, 36)].map { "\($0)" }))
    expectWindowAgreement(pair.report(), "accessibility")
}

// MARK: - 5.6 — state slots and animation

@Observable
private final class WidthModel {
    var wide = false
}

/// **5.6.** The same root mints the same `StateTable` ids — the counter's
/// `$state0` (written by a click on "+"; an unwritten count had no entry when this
/// was first run), `$focus` and `$anim` slots, and the "+" button's `$ax` slot
/// (its declared label; a synthesized node is a record, never a slot, `AB-U`, so
/// the unlabelled counter has none — also found by the first run) — and animates
/// the same widths under both authorities.
///
/// A `.flexStart` column in `DifferentialRoot` (400×400) over a `Box` whose width
/// animates 196 → 320 and a 20×10 box under a `.frame(width:height: 20)` layer
/// whose width does the same, one `withAnimation(.linear(duration: 1))` driven
/// through the display link: at t = 100 (before), t = 100 (the frame that starts
/// the transaction) and t = 100.5, both widths read **196, 196, 258** under both
/// authorities (the prototype measured the `Box`, record §18 P1).
///
/// Mutation that must redden it: **M5e**, `Box` hands `lowerLegacyNode` the style
/// captured before `animated(…)` (the lowered box reads 320 at the transaction's
/// start).
@MainActor
@Test func aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let counter = try WindowPair(device: device, size: 400) { LowerableCounter() }
    counter.both { window, platform in
        #expect(platform.simulateAccessibilityRequest(.activate))
        window.drawFrameIfNeeded()
        click(platform, at: pt(230, 30))
        window.drawFrameIfNeeded()
        window.focus(counterElementID)
        window.drawFrameIfNeeded()
    }
    let ids = counter.lowered.window.stateTable.ids
    let plus = child(counterElementID, 2)
    for (owner, slot) in [(counterElementID, "$state0"), (counterElementID, "$focus"),
                          (counterElementID, "$anim"), (plus, "$ax")] {
        #expect(ids.contains { $0.parent == owner && $0.component == .named(ElementID(slot)) }, "slot \(slot)")
    }
    #expect(counter.legacy.window.stateTable.ids == ids)

    var models: [WidthModel] = []
    let column = child(rootID, 0)
    var widths: [LayoutAuthority: [[Float]]] = [:]
    for authority in [LayoutAuthority.legacy, .proposal] {
        let model = WidthModel()
        models.append(model)
        let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
            DifferentialRoot(width: 400, height: 400) {
                Column {
                    Box().width(px(model.wide ? 320 : 196)).height(px(20)).background(.accent)
                    Box().width(px(20)).height(px(10)).frame(width: px(model.wide ? 320 : 196), height: px(20))
                }
                .alignItems(.flexStart)
            }
        }
        window.layoutAuthority = authority
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
        widths[authority] = series
    }
    let expected: [[Float]] = [[196, 196], [196, 196], [258, 258]]
    #expect(widths[.legacy] == expected, "legacy \(String(describing: widths[.legacy]))")
    #expect(widths[.proposal] == expected, "proposal \(String(describing: widths[.proposal]))")
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
    let frame = LayoutDifferential.render(authority: .proposal, width: 200, height: 100) {
        Column {
            Row { Box().width(px(10)).height(px(20)); Box().width(px(30)).height(px(10)) }
            Row { Box().width(px(20)).height(px(10)); Box { Box().width(px(10)).height(px(10)) }.padding(px(4)) }
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

/// **5.8** (`LR-Q`). A chain of **29** such `Box`es — 87 native levels, the
/// deepest `NativeLayoutRun.maxDepth` (88) allows — laid out as a **production**
/// frame's root (no harness root, whose overlay and frame would add two levels)
/// under the proposal authority. **An exit test whose child expects success**, so
/// a mutation that makes it trap reddens this test by name instead of ending the
/// run with no summary line.
///
/// Mutation that must redden it: **M5g**, the lowering emits a fourth native level
/// per `Box` (an extra `padding(0)`: 116 levels, the child traps).
@Test func aLoweredChainAtTheNativeDepthLimitLaysOut() async {
    let result = await #expect(processExitsWith: .success,
                               observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            var root = nestedPaddedBoxes(29)
            let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                              layoutAuthority: .proposal)
            frame.render(&root)
            let line = "LANE5-5.8 nodes=\(frame.tree.nodeCount)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
    }
    let out = String(decoding: result?.standardOutputContent ?? [], as: UTF8.self)
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(out.contains("LANE5-5.8 nodes=87\n"), "stdout:\n\(out)\nstderr:\n\(err)")
}

/// **5.9** (`LR-Q`). The same chain one `Box` longer — **30**, 90 native levels —
/// traps with `SA-L`'s message, as an exit test.
///
/// Mutation that must redden it: **M5h**, `NativeLayoutRun.maxDepth` raised to 96
/// (the child succeeds).
@Test func aLoweredChainOneLevelPastTheNativeDepthLimitTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = nestedPaddedBoxes(30)
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
        }
    }
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(err.contains("native layout recursion exceeded 88 levels"), "stderr:\n\(err)")
}

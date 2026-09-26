import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 10 part 1, lane 2 — `Binding<Value>` (ruling `DD-D`) and the
// `TextField`/`TextEditor` binding initialisers (`DD-E`). Spec
// `docs/superpowers/specs/2026-09-25-data-and-scrolling-design.md`, tests
// 2.1–2.10; SwiftUI's side is `docs/probes/swiftui-data-and-scrolling.swift`,
// arms B1–B6.
//
// **No red-before run**: every test here is of new API, which cannot compile
// before it exists. Each one's proof is its named mutation (M2a…M2j), run
// against the finished implementation and recorded in record §57.

// MARK: - Fixtures

@MainActor
private func slot(_ id: GlobalElementID, _ ordinal: Int) -> GlobalElementID {
    GlobalElementID.child(of: id, at: ordinal, name: ElementID("$state\(ordinal)"))
}

@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor
private func centre(_ bounds: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: bounds.origin.x + Pixels(bounds.size.width.value / 2),
          y: bounds.origin.y + Pixels(bounds.size.height.value / 2))
}

@MainActor private func drawUntilClean(_ window: Window, limit: Int = 5) {
    for _ in 0..<limit where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// What each frame's owner body read, in order.
@MainActor
private final class Reads { var values: [Int] = [] }

/// The leaf: a 20 × 20 clickable box writing `value = 5` through its binding.
private struct Grandchild: Component {
    @Binding var value: Int
    var content: some ElementGroup {
        Box().cssWidth(Pixels(20)).cssHeight(Pixels(20)).onClick { value = 5 }
    }
}

/// One `@Binding` hop: passes its own projection on.
private struct Middle: Component {
    @Binding var value: Int
    var content: some ElementGroup { Grandchild(value: $value) }
}

/// The owner: records what it reads each frame, and hands `$n` down.
private struct Owner: Component {
    @State var n = 0
    let reads: Reads
    var content: some ElementGroup {
        reads.values.append(n)
        return Middle(value: $n)
    }
}

// MARK: - 2.1–2.7: Binding's semantics (B1–B6)

/// **2.1 (B1).** A grandchild's click writes 5 through `@Binding` →
/// `@Binding` → `$n`, and the owner reads 5 on the next frame. M2a
/// (`State.projectedValue`'s setter a no-op).
@Test @MainActor
func aStateProjectionWritesTheOwnersStateThroughTwoLevels() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let reads = Reads()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Row { Owner(reads: reads) }
    }
    window.drawFrameIfNeeded()
    try #require(reads.values == [0], "control: the owner's first frame reads its initial value")
    let hit = try #require(window.lastHitboxes.last { $0.handlers.onClick != nil })

    click(platform, at: centre(hit.bounds))
    #expect(window.needsRedraw, "a binding write is a @State write: it dirties the window")
    drawUntilClean(window)
    #expect(reads.values.last == 5,
            "the owner reads what the grandchild wrote two binding hops down")
}

/// **2.2 (B2).** `.constant(3)`: a write of 5 is dropped; it reads 3. M2b
/// (`.constant` stores into a box and reads it back).
@Test @MainActor
func aConstantBindingIgnoresWrites() {
    let b = Binding.constant(3)
    #expect(b.wrappedValue == 3)
    b.wrappedValue = 5
    #expect(b.wrappedValue == 3, "a constant binding drops every write")
    let hop = b.projectedValue
    hop.wrappedValue = 7
    #expect(b.wrappedValue == 3 && hop.wrappedValue == 3, "and so does its projection")
}

private struct Model { var name: String; var count: Int }

/// **2.3 (B3).** `$model.name = "b"` writes the name and leaves the count. M2c
/// (the dynamic-member setter drops the write).
@Test @MainActor
func aKeyPathBindingWritesOneFieldAndLeavesTheOthers() {
    var storage = Model(name: "a", count: 1)
    var writes = 0
    let model = Binding(get: { storage }, set: { storage = $0; writes += 1 })
    let name = model.name
    #expect(name.wrappedValue == "a")
    name.wrappedValue = "b"
    #expect(storage.name == "b", "the one field is written")
    #expect(storage.count == 1, "the other field is left as it was")
    #expect(writes == 1, "through one write of the whole value")
}

/// **2.3b (B3).** Two derived bindings made before either writes — two
/// `TextField`s bound to `$model.name` and `$model.count` with composed edits
/// between frames — write one after the other, and both fields land: each
/// write reads the base's CURRENT value. **Red under V6** (the subscript
/// snapshots the base when the derived binding is made): the second write
/// reverts the first field.
@Test @MainActor
func twoKeyPathBindingsMadeTogetherEachWriteOverTheOthersWrite() {
    var storage = Model(name: "a", count: 1)
    let model = Binding(get: { storage }, set: { storage = $0 })
    let name = model.name
    let count = model.count
    name.wrappedValue = "b"
    count.wrappedValue = 2
    #expect(storage.name == "b", "the first write survives the second")
    #expect(storage.count == 2, "and the second lands")
}

/// **2.4 (B4).** `init(get:set:)`: read 1, write 4, read 4; the setter runs
/// once per write. M2d (`wrappedValue`'s setter calls `set` twice).
@Test @MainActor
func aGetSetBindingCallsTheSetterOncePerWrite() {
    var storage = 1
    var setterCalls = 0
    let b = Binding(get: { storage }, set: { storage = $0; setterCalls += 1 })
    #expect(b.wrappedValue == 1)
    b.wrappedValue = 4
    #expect(b.wrappedValue == 4)
    #expect(setterCalls == 1, "one write, one setter call (B4)")
}

/// **2.5 (B5).** `init?(Binding<Value?>)` is nil over nil and writes through
/// over 3 → 9; `init(Binding<V>)` as `V?` ignores a nil write and writes 6.
/// M2e (`init?` returns a binding over nil, falling back to a default).
@Test @MainActor
func theOptionalBindingInitialisersMatchSwiftUI() throws {
    var absent: Int? = nil
    let overNil = Binding<Int?>(get: { absent }, set: { absent = $0 })
    #expect(Binding<Int>(overNil) == nil, "an unwrapped binding over nil is nil (B5)")

    var present: Int? = 3
    let overValue = Binding<Int?>(get: { present }, set: { present = $0 })
    let unwrapped = try #require(Binding<Int>(overValue), "over a value it is a binding")
    #expect(unwrapped.wrappedValue == 3)
    unwrapped.wrappedValue = 9
    #expect(present == 9, "and writes through")
    present = 5
    #expect(unwrapped.wrappedValue == 5, "it reads the base's current value (V5)")
    present = nil
    #expect(unwrapped.wrappedValue == 5,
            "and once the base goes nil, the last non-nil value it read (MetalUI's answer, unprobed; DD-D item 2)")

    var plain = 2
    let base = Binding(get: { plain }, set: { plain = $0 })
    let lifted = Binding<Int?>(base)
    #expect(lifted.wrappedValue == 2)
    lifted.wrappedValue = nil
    #expect(plain == 2, "a lifted binding ignores a nil write (B5)")
    lifted.wrappedValue = 6
    #expect(plain == 6, "and writes a value through")
}

/// Keeps the `$n` its body made, so the test can use it after the frame.
@MainActor
private final class Kept { var binding: Binding<Int>?; var state: State<Int>? }

private struct Keeper: Component {
    @State var n = 0
    let kept: Kept
    var content: some ElementGroup {
        if kept.binding == nil { kept.binding = $n }
        kept.state = _n
        return EmptyGroup()
    }
}

/// **2.6 (B6).** A `$n` kept from frame 1 reads the state after something
/// else set it to 7, and its own write of 11 lands. M2f (`projectedValue`
/// captures the value at creation — a snapshot getter).
@Test @MainActor
func aKeptBindingReadsAndWritesTheCurrentState() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let kept = Kept()
    let (window, _) = try makeFakeWindow(device: device, size: 100) { Row { Keeper(kept: kept) } }
    window.drawFrameIfNeeded()
    let binding = try #require(kept.binding)
    try #require(binding.wrappedValue == 0)

    // "Another handler" writes 7 straight through the state wrapper.
    let state = try #require(kept.state)
    state.wrappedValue = 7
    drawUntilClean(window)
    #expect(binding.wrappedValue == 7, "a kept binding is live: it reads the current state (B6)")

    binding.wrappedValue = 11
    drawUntilClean(window)
    #expect(state.wrappedValue == 11, "and its write lands in the slot the wrapper reads")
}

/// The twice-placed parent: owns `n`, passes `$n` to a clickable child.
private struct Parent: Component {
    @State var n = 0
    var content: some ElementGroup { Grandchild(value: $n) }
}

/// **2.7 (`ID-F`).** One `Parent` value placed twice, each passing `$n` down:
/// a click in occurrence 0's child moves only occurrence 0's slot. M2g (the
/// projection writes `box.slotID`, the last-bound occurrence, instead of
/// `resolvedSlot`).
@Test @MainActor
func aBindingWrittenFromADispatchedHandlerReachesItsOwnOccurrence() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        let parent = Parent()
        return Row { parent; parent }
    }
    window.drawFrameIfNeeded()
    let hits = window.lastHitboxes.filter { $0.handlers.onClick != nil }
    try #require(hits.count == 2, "each occurrence's child registers a hitbox")
    // Each occurrence is where the two hitboxes' ancestor chains first part.
    func chain(_ id: GlobalElementID) -> [GlobalElementID] {
        var out = [id]
        while let p = out.last!.parent { out.append(p) }
        return out.reversed()
    }
    let chains = hits.map { chain($0.id) }
    let fork = try #require(Array(zip(chains[0], chains[1])).firstIndex { $0.0 != $0.1 })
    let parents = [chains[0][fork], chains[1][fork]]
    try #require(parents[0] != parents[1], "control: two occurrences, two ids")
    func counts() -> [Int] {
        parents.map { window.stateTable.peek(slot($0, 0), as: Int.self) ?? 0 }
    }

    click(platform, at: centre(hits[0].bounds))
    #expect(counts() == [5, 0],
            "occurrence 0's child was clicked; the last-bound occurrence would read [0, 5]")
}

// MARK: - 2.8–2.10: TextField and TextEditor bound to state (DD-E)

@MainActor
private final class FieldProbe { var value = ""; var shown: [String] = [] }

private struct BoundField: Component {
    @State var s = ""
    let probe: FieldProbe
    let editor: Bool
    let constant: Bool
    var content: some ElementGroup {
        probe.value = s
        let binding = constant ? Binding.constant("x") : $s
        return Box {
            if editor {
                TextEditor(text: binding).frame(height: Pixels(100))
            } else {
                TextField("p", text: binding)
            }
        }
    }
}

/// Focuses the window's one text-input element by clicking it, then sends two
/// `.textInput` edits with no frame between them, then draws.
@MainActor
private func typeTwice(_ window: Window, _ platform: FakePlatformWindow) throws -> String? {
    window.drawFrameIfNeeded()
    let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    click(platform, at: centre(field.bounds))
    try #require(window.focusedElement != nil, "control: a press focuses the field (TI-B)")
    platform.simulateInput(.textInput("a"))
    platform.simulateInput(.textInput("b"))
    drawUntilClean(window)
    let target = window.lastHitboxes.first { $0.handlers.textInput != nil }?.handlers.textInput
    return target?.text
}

@MainActor
private func boundWindow(editor: Bool, constant: Bool) throws
    -> (Window, FakePlatformWindow, FieldProbe) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let probe = FieldProbe()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Row { BoundField(probe: probe, editor: editor, constant: constant) }
    }
    return (window, platform, probe)
}

/// **2.8.** A focused `TextField("p", text: $s)`: two edits between frames
/// compose (`Window.editedText`), `s == "ab"` and the field shows it; bound to
/// `.constant("x")` it keeps "x". M2h (the binding initialiser's `onChange`
/// ignores the edit).
@Test @MainActor
func aTextFieldBoundToStateUpdatesItOnEveryEdit() throws {
    let (window, platform, probe) = try boundWindow(editor: false, constant: false)
    let shown = try typeTwice(window, platform)
    #expect(probe.value == "ab", "the bound state holds both edits")
    #expect(shown == "ab", "and the field shows it")

    let (cWindow, cPlatform, _) = try boundWindow(editor: false, constant: true)
    #expect(try typeTwice(cWindow, cPlatform) == "x", "bound to .constant, every edit is dropped")
}

/// **2.9.** The same for `TextEditor(text: $s)`. M2i (M2h's twin in
/// `TextEditor`).
@Test @MainActor
func aTextEditorBoundToStateUpdatesItOnEveryEdit() throws {
    let (window, platform, probe) = try boundWindow(editor: true, constant: false)
    let shown = try typeTwice(window, platform)
    #expect(probe.value == "ab", "the bound state holds both edits")
    #expect(shown == "ab", "and the editor shows it")

    let (cWindow, cPlatform, _) = try boundWindow(editor: true, constant: true)
    #expect(try typeTwice(cWindow, cPlatform) == "x", "bound to .constant, every edit is dropped")
}

@MainActor
private func sceneBytes<E: Element>(_ make: () -> E) -> [[UInt8]] {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(120)), scaleFactor: 1)
    var root = make()
    frame.render(&root)
    let scene = frame.finalizedScene()
    return [scene.rects.withUnsafeBytes { Array($0) }, scene.glyphs.withUnsafeBytes { Array($0) }]
}

/// **2.10.** The bound and the controlled spellings build the same element:
/// equal scenes for `TextField` and for `TextEditor`. The text is empty so the
/// placeholder draws — the parameter M2j (the binding initialiser passes `""`
/// as the placeholder) drops.
@Test @MainActor
func aBoundTextFieldDrawsTheSameSceneAsAControlledOne() {
    var s = ""
    let binding = Binding(get: { s }, set: { s = $0 })
    let bound = sceneBytes { Box { TextField("placeholder", text: binding) } }
    let controlled = sceneBytes { Box { TextField("placeholder", text: s) { s = $0 } } }
    #expect(!bound[1].isEmpty, "control: the placeholder draws glyphs")
    #expect(bound == controlled, "TextField: the binding initialiser builds the controlled element")

    let boundEditor = sceneBytes { Box { TextEditor("notes", text: binding).frame(height: Pixels(100)) } }
    let controlledEditor = sceneBytes {
        Box { TextEditor("notes", text: s) { s = $0 }.frame(height: Pixels(100)) }
    }
    #expect(!boundEditor[1].isEmpty, "control: the editor's placeholder draws glyphs")
    #expect(boundEditor == controlledEditor, "TextEditor: likewise")
}

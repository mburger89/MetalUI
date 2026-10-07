import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Spec `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §4.2,
// tests 2.6–2.11 (ruling `MD-H` in
// `docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`; probe
// `docs/probes/swiftui-environment-object.swift`, arms `N0`–`N3`, `O1`/`O2`,
// `K1`–`K2b`, `W1`, `R`, `T`): `@Environment(Type.self)` reads an
// `@Observable` object provided by `.environment(_:)`, keyed by the static
// type it was written as; a missing object traps.

@Observable
private final class Model {
    var count = 0
    var other = 0
    let name: String
    init(_ name: String) { self.name = name }
}

@Observable
private final class Second {
    let name: String
    init(_ name: String) { self.name = name }
}

@Observable
private class Base {
    let name: String
    init(_ name: String) { self.name = name }
}

private final class Sub: Base {}

/// What each reader saw, by label, per phase.
@MainActor
private final class Seen {
    var layout: [String: String] = [:]
    var paint: [String: String] = [:]
}

/// A leaf reading `@Environment(Model.self)` optionally in layout and paint;
/// "nil" when absent.
private struct OptionalReader: Element {
    @Environment(Model.self) var model: Model?
    let label: String
    let seen: Seen

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        seen.layout[label] = model?.name ?? "nil"
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        seen.paint[label] = model?.name ?? "nil"
    }
}

/// A leaf reading the non-optional form — it traps without a writer.
private struct Reader: Element {
    @Environment(Model.self) var model
    let label: String
    let seen: Seen

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        seen.layout[label] = model.name
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        seen.paint[label] = model.name
    }
}

/// Reads two types at once.
private struct SecondReader: Element {
    @Environment(Second.self) var second: Second?
    @Environment(Model.self) var model: Model?
    let label: String
    let seen: Seen

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        seen.layout[label] = "\(model?.name ?? "nil")+\(second?.name ?? "nil")"
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// A `Component` reading the object while building its content, in layout
/// (`EV-M`).
private struct ComponentReader: Component {
    @Environment(Model.self) var model
    let seen: Seen
    var content: some ElementGroup {
        seen.layout["component"] = model.name
        return Box().cssWidth(Pixels(1)).cssHeight(Pixels(1))
    }
}

/// Reads `Base?` and `Sub?`.
private struct KeyReader: Element {
    @Environment(Base.self) var base: Base?
    @Environment(Sub.self) var sub: Sub?
    let label: String
    let seen: Seen

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        seen.layout[label] = "base=\(base?.name ?? "nil") sub=\(sub?.name ?? "nil")"
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor
private func render<E: Element>(_ root: E) {
    var root = root
    Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1).render(&root)
}

// MARK: - 2.6 position and the nearest writer

/// **2.6** (`MD-H` items 1–3; probe `N0`–`N3`, `O1`, `O2`). An object written
/// by `.environment(_:)` is read below it by an `Element` (layout and paint)
/// and a `Component`; of two writers of one type the nearer wins; two types
/// coexist; a sibling outside the writer, and any reader with no writer, reads
/// `nil` through the optional form.
///
/// Red before: does not compile. M2.6 (the scope's write keeps an existing
/// entry) reddens the nearest-writer arm.
@Test @MainActor func anEnvironmentObjectIsReadAtItsPositionAndTheNearestWriterWins() {
    let seen = Seen()
    let a = Model("a"), b = Model("b")
    render(Row {
        Reader(label: "N0", seen: seen).environment(a)
        ComponentReader(seen: seen).environment(a)
        OptionalReader(label: "N1", seen: seen).environment(b).environment(a)
        SecondReader(label: "N2", seen: seen).environment(Second("s")).environment(a)
        OptionalReader(label: "N3", seen: seen)
    })
    #expect(seen.layout["N0"] == "a" && seen.paint["N0"] == "a", "N0: read below its writer, layout and paint")
    #expect(seen.layout["component"] == "a", "a Component reads it while building")
    #expect(seen.layout["N1"] == "b" && seen.paint["N1"] == "b", "M2.6 — N1: the nearer writer wins")
    #expect(seen.layout["N2"] == "a+s", "N2: two types coexist")
    #expect(seen.layout["N3"] == "nil" && seen.paint["N3"] == "nil", "N3/O1: a sibling outside the writer reads nil")
}

// MARK: - 2.7 keyed by static type

/// **2.7** (`MD-H` item 2; probe `K1`, `K1b`, `K2`, `K2b`). An object is found
/// by the static type it was written as: written as `Sub` it is found as
/// `Sub` and not as `Base`; written `as Base` it is found as `Base` and not as
/// `Sub`.
///
/// Red before: does not compile. M2.7 (key by `type(of: object)`) reddens the
/// `as Base` arm.
@Test @MainActor func anObjectIsKeyedByTheTypeItWasWrittenAs() {
    let seen = Seen()
    render(Row {
        KeyReader(label: "K1", seen: seen).environment(Sub("s"))
        KeyReader(label: "K2", seen: seen).environment(Sub("t") as Base)
    })
    #expect(seen.layout["K1"] == "base=nil sub=s", "K1/K1b: written as Sub: \(seen.layout["K1"] ?? "-")")
    #expect(seen.layout["K2"] == "base=t sub=nil", "M2.7 — K2/K2b: written as Base: \(seen.layout["K2"] ?? "-")")
}

// MARK: - 2.8 nil clears

/// **2.8** (`MD-H` item 2; probe `W1`). `.environment(nil as Model?)` below a
/// writer clears the object for its content.
///
/// Red before: does not compile. M2.8 (a nil write is a no-op) reddens it.
@Test @MainActor func writingNilClearsAnObject() {
    let seen = Seen()
    render(Row {
        OptionalReader(label: "W1", seen: seen).environment(nil as Model?).environment(Model("a"))
    })
    #expect(seen.layout["W1"] == "nil" && seen.paint["W1"] == "nil", "M2.8 — W1: a nil write clears")
}

// MARK: - 2.9 a missing object traps

/// **2.9** (`MD-H` item 4; probe `T`: SwiftUI's "No Observable object of type
/// Base found. A View.environmentObject(_:) for Base may be missing as an
/// ancestor of this view."; divergence 134). A non-optional read with no
/// writer, and an unbound wrapper's read outside any frame, each trap with
/// MetalUI's sentence naming the type.
///
/// Red before: does not compile. M2.9 (the message's type name dropped)
/// reddens both.
@Test func aMissingObjectTrapsWithItsTypeInTheMessage() async {
    let expected = "No Observable object of type Model found. An .environment(_:) for Model may be missing "
        + "as an ancestor of this element."
    let inFrame = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            render(Row { Reader(label: "T", seen: Seen()) })
        }
    }
    let frameErr = String(decoding: inFrame?.standardErrorContent ?? [], as: UTF8.self)
    #expect(frameErr.contains(expected), "M2.9 — in a frame:\n\(frameErr)")

    let unbound = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = Reader(label: "T", seen: Seen()).model
        }
    }
    let unboundErr = String(decoding: unbound?.standardErrorContent ?? [], as: UTF8.self)
    #expect(unboundErr.contains(expected), "unbound:\n\(unboundErr)")
}

// MARK: - 2.10 observation

/// Shows the object's `count` as a text whose glyph count is the number's
/// digits — read through `@Environment` while the Component builds.
private struct CountLabel: Component {
    @Environment(Model.self) var model
    var content: some ElementGroup {
        Text(String(repeating: "x", count: model.count + 1))
    }
}

/// **2.10** (`MD-H` item 5; `RX-K`; probe `R`: a body re-runs on a write to a
/// property it read, not to one it did not). In a window, a `Component`
/// reading `model.count` through `@Environment`: a write to `model.other`
/// requests no redraw; a write to `model.count` does, and the next frame
/// draws the new value.
///
/// Red before: does not compile. M2.10 (the object's property read at bind,
/// outside tracking — the reader caches a value) reddens the new-value arm.
@Test @MainActor func anEnvironmentObjectsReadPropertyDirtiesTheWindowAndAnUnreadOneDoesNot() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let model = Model("m")
    let (window, _) = try makeFakeWindow(device: device, size: 200) {
        Row { CountLabel().environment(model) }
    }
    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw, "set up: clean")
    #expect(window.lastScene.glyphs.count == 1, "count 0: one glyph")
    model.other += 1
    #expect(!window.needsRedraw, "an unread property is not a dependency")
    model.count = 2
    #expect(window.needsRedraw, "a read property dirties the window")
    window.drawFrameIfNeeded()
    #expect(window.lastScene.glyphs.count == 3, "M2.10 — the next frame draws count 2: three glyphs")
}

// MARK: - 2.11 Component, AnyElement, Deferred, popover

/// **2.11** (`MD-H` item 3; `MD-U` item 5: `LR-CS` in layout, `EV-G` in
/// paint). Readers inside a `Component`, an `AnyElement`, a `Deferred`
/// presentation and a presented `.popover` each read the declaring scope's
/// object, in layout and paint.
///
/// Red before: does not compile. M2.11 (`AnyElementBox`'s layout bind
/// skipped) reddens the `AnyElement` arm.
@Test @MainActor func anEnvironmentObjectReachesComponentAnyElementDeferredAndPopoverContent() throws {
    let seen = Seen()
    let model = Model("scope")
    // A window, two frames: a popover is presented against its anchor's bounds
    // from the frame before (`MN-`), so a bare one-frame render shows none.
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, _) = try makeFakeWindow(device: device, size: 200) {
        Row {
            Row {
                ComponentReader(seen: seen)
                AnyElement(OptionalReader(label: "any", seen: seen))
                Deferred { Box { OptionalReader(label: "deferred", seen: seen) }.position(.absolute).inset(Pixels(0)) }
                Box().cssWidth(Pixels(10)).cssHeight(Pixels(10))
                    .popover(isPresented: .constant(true)) { OptionalReader(label: "popover", seen: seen) }
            }.environment(model)
        }
    }
    window.drawFrameIfNeeded()
    controlRedraw(window)
    #expect(seen.layout["component"] == "scope", "Component")
    for label in ["any", "deferred", "popover"] {
        #expect(seen.layout[label] == "scope", "\(label): layout reads the declaring scope's object")
        #expect(seen.paint[label] == "scope", "\(label): paint reads the declaring scope's object")
    }
}

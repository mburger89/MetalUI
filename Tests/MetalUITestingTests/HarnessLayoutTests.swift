import MetalUI
import MetalUITesting
import Testing

// Spec §4.1 tests 1.25–1.27 (MG-12 item 3): laid-out frames by `.id`, gpui's
// `debug_bounds` (ruling `HT-G` item 2) — window content space, logical
// points, from the last build. Literals are derived from the stack rule
// before the run: `HStack(spacing: 0)` of fixed boxes answers the sum of the
// widths and the tallest height, and the root is centred at its answer in the
// 400 × 300 window (`CN-J`).

/// 1.25 — 120 + 80 = 200 wide, 50 tall, centred: origin ((400 − 200) / 2,
/// (300 − 50) / 2) = (100, 125); `a` at (100, 125, 120, 50) and `b` at
/// (220, 125, 80, 50). Mutation: `testingRecordsElementBounds` not set.
@Test @MainActor func frameOfIDReadsLaidOutRects() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(120), height: Pixels(50)).id("a")
            Box().frame(width: Pixels(80), height: Pixels(50)).id("b")
        }
    }
    #expect(try window.frame(ofID: "a") == rect(100, 125, 120, 50))
    #expect(try window.frame(ofID: "b") == rect(220, 125, 80, 50))
    #expect(throws: TestHarnessError.noElement("id \"c\"")) { try window.frame(ofID: "c") }
}

/// 1.26 — one name under two parents is two elements: `frame(ofID:)` throws
/// ambiguous naming the count and `frames(ofID:)` lists both, top to bottom
/// then left to right. The `HStack` of two 40 × 40 columns is 80 × 40 at
/// (160, 130). Mutation: `frames(ofID:)` returns the first only.
@Test @MainActor func frameOfAnAmbiguousIDThrowsAndFramesOfIDListsBoth() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            VStack { Box().frame(width: Pixels(40), height: Pixels(40)).id("x") }
            VStack { Box().frame(width: Pixels(40), height: Pixels(40)).id("x") }
        }
    }
    #expect(throws: TestHarnessError.ambiguous("id \"x\"", count: 2)) { try window.frame(ofID: "x") }
    #expect(try window.frames(ofID: "x") == [rect(160, 130, 40, 40), rect(200, 130, 40, 40)])
}

/// 1.27 — a window opened with `recordsLayout: false` (a benchmark's) records
/// nothing and says so. Mutation: always record.
@Test @MainActor func aWindowNotRecordingLayoutThrowsNotRecorded() throws {
    let window = try harnessWindow(recordsLayout: false) {
        Box().frame(width: Pixels(40), height: Pixels(40)).id("a")
    }
    #expect(throws: TestHarnessError.notRecorded("layout")) { try window.frame(ofID: "a") }
}

// C30 (`TW-A`…`TW-C`, record §108): `frame(ofID:)` finds an `.id` written on proposal
// content — a `Rectangle`, a `GPUSurface` frame, a `ZStack` in a `Component` — which is an
// `IdentifiedGroup` (layout-transparent: an identity level and no node, `ID-G`). Rows are
// the union of the nodes the content hands its parent (`TW-B`). Literals derived by hand in
// the 400 × 300 window: a lone child of a `VStack` is centred at its own answer (`CN-J`).

/// A two-node component under one `.id`: 40 × 20 over 60 × 10 in a zero-spacing stack.
struct IdentifiedPair: Component {
    var content: some ElementGroup {
        Rectangle().frame(width: Pixels(40), height: Pixels(20))
        Rectangle().frame(width: Pixels(60), height: Pixels(10))
    }
}

/// A component whose content is empty.
struct IdentifiedNothing: Component {
    let show: Bool
    var content: some ElementGroup {
        if show { Rectangle().frame(width: Pixels(40), height: Pixels(20)) }
    }
}

/// The DG-T shape: a `ZStack` named inside a `Component`.
struct IdentifiedPanel: Component {
    var content: some ElementGroup {
        ZStack { Rectangle().frame(width: Pixels(40), height: Pixels(20)) }.id("stack")
    }
}

/// 1.30 — `Rectangle().frame(40 × 20).id("r")` alone in a `VStack`: (180, 140, 40, 20).
/// Red on d279f34d: `noElement(id "r")`. Mutation: delete the `recordIdentifiedBounds` call.
@Test @MainActor func frameOfIDFindsAnIDOnARectangle() throws {
    let window = try harnessWindow {
        VStack { Rectangle().frame(width: Pixels(40), height: Pixels(20)).id("r") }
    }
    #expect(try window.frame(ofID: "r") == rect(180, 140, 40, 20))
}

/// 1.31 — a `GPUSurface` with a frame, then `.id`: (150, 130, 100, 40). Same mutation.
@Test @MainActor func frameOfIDFindsAnIDOnAGPUSurface() throws {
    let window = try harnessWindow {
        VStack {
            GPUSurface(redraw: .onDemand, value: 0) { _ in }
                .frame(width: Pixels(100), height: Pixels(40)).id("surface")
        }
    }
    #expect(try window.frame(ofID: "surface") == rect(150, 130, 100, 40))
}

/// 1.32 — a `ZStack` named inside a `Component` (DG-T): (180, 140, 40, 20). Same mutation.
@Test @MainActor func frameOfIDFindsAnIDOnAZStackInsideAComponent() throws {
    let window = try harnessWindow { VStack { IdentifiedPanel() } }
    #expect(try window.frame(ofID: "stack") == rect(180, 140, 40, 20))
}

/// 1.33 — a modifier chain answers its outermost layer: 40 × 20 padded by 5 is 50 × 30 at
/// (175, 135). Mutation: record the innermost node's rect (reads 40 × 20).
@Test @MainActor func frameOfIDAnswersTheOutermostLayerOfAModifiedChain() throws {
    let window = try harnessWindow {
        VStack {
            Rectangle().frame(width: Pixels(40), height: Pixels(20)).padding(Pixels(5))
                .background(Color.red).id("p")
        }
    }
    #expect(try window.frame(ofID: "p") == rect(175, 135, 50, 30))
}

/// 1.34 — two nodes under one `.id` answer their union: 40 × 20 over 60 × 10, centred in a
/// 60 × 30 stack at (170, 135): union (170, 135, 60, 30). Mutation: first node only
/// (reads 180, 135, 40, 20).
@Test @MainActor func frameOfIDAnswersTheUnionOfAGroupsNodes() throws {
    let window = try harnessWindow { VStack(spacing: 0) { IdentifiedPair().id("pair") } }
    #expect(try window.frame(ofID: "pair") == rect(170, 135, 60, 30))
}

/// 1.35 — `Text` and `Box` ids are still found beside a `Rectangle` id, each once.
/// Mutation: record the identified row under a wrong key (reddens 1.30–1.34 only).
@Test @MainActor func frameOfIDStillFindsTextAndBoxIDs() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(30), height: Pixels(20)).id("box")
            Rectangle().frame(width: Pixels(40), height: Pixels(20)).id("rect")
            Text("hi").id("text")
        }
    }
    #expect(try window.frame(ofID: "box").size == sz(30, 20))
    #expect(try window.frame(ofID: "rect").size == sz(40, 20))
    #expect(try window.frame(ofID: "text").size.height > 0)
}

/// 1.36 — an `.id` on a group with no nodes is `noElement`, not a trap and not a zero rect.
/// Mutation: record `Bounds.zero` for an empty list.
@Test @MainActor func frameOfIDOnAnEmptyIdentifiedGroupIsNoElement() throws {
    let window = try harnessWindow { VStack { IdentifiedNothing(show: false).id("e") } }
    #expect(throws: TestHarnessError.noElement("id \"e\"")) { try window.frame(ofID: "e") }
}

/// 1.37 — the same `Rectangle().id` adopted whole by a legacy `Column` (through
/// `LegacyContent`, `PE-C`) is found too: the untyped entry sets the nodes as the typed one
/// does. A lone child of a centring `Column` is centred at its answer: (180, 140, 40, 20).
/// Mutation: skip the untyped entry's `nodes` assignment.
@Test @MainActor func anIDInALegacyParentIsFoundToo() throws {
    let window = try harnessWindow {
        Column { Rectangle().frame(width: Pixels(40), height: Pixels(20)).id("r") }
    }
    #expect(try window.frame(ofID: "r").size == sz(40, 20))
}

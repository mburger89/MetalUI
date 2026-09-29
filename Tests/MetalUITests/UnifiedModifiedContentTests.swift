import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Lane 1 of plan task 7 stage 11 (spec
// `docs/superpowers/specs/2026-09-25-engine-stage-11-design.md` §3, §7 lane 1;
// ruling `LR-FV`): ONE flat `ModifiedContent<Content, Modifier>` for both
// modifier vocabularies. `N1.1` pins the proposal chain's flatness and its
// identities against the nested shape it replaced; `N1.2` pins a legacy wrapper
// absorbing a proposal chain as its innermost layers (`LR-FV` item 4).
//
// Red runs and mutations are in record §54's lane-1 section.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// The root id `Frame.render` builds for an unnamed root element.
private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

/// Everything one rendered frame lets a test compare: every recorded element
/// bound (by id), the tree's node count, the native work counters and every
/// emitted rect with its fill.
private struct Observation: Equatable {
    var bounds: [GlobalElementID: Bounds<Pixels>]
    var nodeCount: Int
    var work: [Int]
    var rects: [[Float]]
}

@MainActor
private func observe<Root: Element>(_ make: () -> Root) -> Observation {
    var root = make()
    let frame = Frame(contentSize: Size(width: px(200), height: px(160)), scaleFactor: 1,
                      recordsElementBounds: true)
    frame.render(&root)
    let work = frame.tree.lastNativeLayoutWork
    return Observation(
        bounds: frame.elementBounds,
        nodeCount: frame.tree.nodeCount,
        work: [work.measureCalls, work.cacheHits, work.cacheMisses],
        rects: frame.finalizedScene().rects.map {
            [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height,
             $0.background.h, $0.background.s, $0.background.l, $0.background.a]
        })
}

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: px(x), y: px(y)), size: Size(width: px(w), height: px(h)))
}

@MainActor
private func leaf() -> Rectangle { Rectangle(width: px(20), height: px(10), color: .surface) }

private let insets = Edges(all: Pixels(4))

/// A legacy `.frame` written in generic code: over a proposal chain the only
/// way to reach `_wrap` (a concrete receiver resolves the proposal `.frame`,
/// the more specialized overload, and the legacy `.padding` is on
/// `StyledElement`, which a proposal chain is not — `LR-GB`).
@MainActor
private func legacyFrame<T: ElementGroup>(_ t: T) -> ModifiedElement<T.LayerBase> {
    t.frame(width: px(40), height: px(30))
}

/// **N1.1 — a proposal chain is one flat `ModifiedContent<Base,
/// LayoutModifier>` whose identities are the nested chain's** (ruling `LR-FV`
/// items 1 and 3, spec §3.3 item 2).
///
/// `leaf().padding(e).frame(width: 60).background(.accent)` against the same
/// three modifiers built with three nested explicit
/// `ModifiedContent(content:modifier:)` inits — the one-parameter shape of
/// `47c0d98`, whose every level is its own element entered at cursor 0 with a
/// `nil` name — compared on every recorded element bound (key and rect), the
/// node count, the native work counters and every emitted rect.
///
/// **The disagreeing oracle** — the chain with its middle `.frame` removed —
/// is `try #require`d to disagree with the nested one before the agreement is
/// read (practices shape 15). The literals (4 nodes, work 2/2/7, five recorded
/// bounds) were taken at `47c0d98` on the nested chain.
///
/// Red before: does not compile at `47c0d98` (`ModifiedContent` takes one
/// argument). Mutations (record §54): **M1a** `typealias ProposalBase =
/// Content` deleted (chains nest: the type assertion); **M1b** a proposal inner
/// layer's id `at: 1` (bounds keys); **M1i** `recordElementBounds` skipped for
/// an inner proposal layer (bounds keys).
@Test @MainActor func aProposalChainIsOneFlatModifiedContentWithTheNestedChainsIdentities() throws {
    let value = leaf().padding(insets).frame(width: px(60)).background(.accent)
    #expect(type(of: value) == ModifiedContent<Rectangle, LayoutModifier>.self,
            "a proposal chain must be ONE flat ModifiedContent; got \(type(of: value))")
    #expect(value.layerCount == 3 && value.prefix.isEmpty, "layers \(value.layerCount)")

    let flat = observe { ZStack { leaf().padding(insets).frame(width: px(60)).background(.accent) } }
    let nested = observe {
        ZStack {
            ModifiedContent(content: ModifiedContent(content: ModifiedContent(content: leaf(),
                                                                              modifier: .padding(insets)),
                                                     modifier: .frame(width: px(60))),
                            modifier: .background(.accent))
        }
    }
    let middleRemoved = observe { ZStack { leaf().padding(insets).background(.accent) } }

    try #require(middleRemoved.bounds != nested.bounds && middleRemoved.nodeCount != nested.nodeCount
                 && middleRemoved.rects != nested.rects,
                 "the disagreeing oracle must disagree: \(middleRemoved) vs \(nested)")
    #expect(nested.nodeCount == 4 && nested.work == [2, 2, 7] && nested.bounds.count == 5,
            "the nested chain's 47c0d98 literals: \(nested)")
    #expect(flat.bounds == nested.bounds, "bounds: flat \(flat.bounds) vs nested \(nested.bounds)")
    #expect(flat.nodeCount == nested.nodeCount, "nodes: flat \(flat.nodeCount) vs nested \(nested.nodeCount)")
    #expect(flat.work == nested.work, "work: flat \(flat.work) vs nested \(nested.work)")
    #expect(flat.rects == nested.rects, "rects: flat \(flat.rects) vs nested \(nested.rects)")
}

/// **N1.2 — a legacy wrapper after a proposal chain absorbs it as its
/// innermost layers** (ruling `LR-FV` item 4, spec §3.3 item 3), with the id
/// path `ModifiedElement<ModifiedContent<Rectangle>>` had at `47c0d98`.
///
/// `legacyFrame(leaf().padding(e)).background(.accent)` — spelled through a
/// generic `.frame` because that is the only route to `_wrap` on a proposal
/// chain (`LR-GB`; the spec's `.padding(Pixels(8))` spelling never compiled on
/// a proposal chain): type `ModifiedContent<Rectangle, ModifierLayer>`, prefix
/// `[.padding(e)]`; the legacy frame layer at the root, the absorbed padding at
/// `.child(root, 0)`, the content at `.child(.child(root, 0), 0)`; the fill at
/// the frame layer's 40×30 box. The literals (bounds, 3 nodes, work 1/2/3,
/// rects) were taken at `47c0d98` from the nested spelling.
///
/// **Arm 2** adds a legacy `.padding(Pixels(8))` after the frame, so the chain
/// holds an absorbed prefix, an inner legacy layer and an outermost one: the
/// prefix must sit inside the inner legacy layer, where the nested shape put it
/// (literals taken at `47c0d98` the same way).
///
/// Red before: does not compile at `47c0d98` (`prefix`, two-argument type).
/// Mutations (record §54): **M1d** `LayoutModifier._legacyStack` drops the
/// prefix (node count, keys, rects); **M1d′** the prefix walked after the
/// inner legacy layers in `wrapLayers` (arm 2's rects).
@Test @MainActor func aLegacyWrapperAfterAProposalChainAbsorbsItAsItsInnermostLayers() throws {
    let value = legacyFrame(leaf().padding(insets)).background(.accent)
    #expect(type(of: value) == ModifiedContent<Rectangle, ModifierLayer>.self,
            "a legacy wrapper over a proposal chain must be the legacy vocabulary's flat chain; got \(type(of: value))")
    #expect(value.prefix.count == 1 && value.inner.isEmpty,
            "prefix \(value.prefix.count), inner \(value.inner.count)")

    let absorbed = observe { legacyFrame(leaf().padding(insets)).background(.accent) }
    let middle = GlobalElementID.child(of: rootID, at: 0, name: nil)
    let content = GlobalElementID.child(of: middle, at: 0, name: nil)
    #expect(absorbed.bounds == [rootID: bounds(80, 65, 40, 30),
                                middle: bounds(86, 71, 28, 18),
                                content: bounds(90, 75, 20, 10)],
            "bounds: \(absorbed.bounds)")
    #expect(absorbed.nodeCount == 3 && absorbed.work == [1, 2, 3],
            "nodes \(absorbed.nodeCount), work \(absorbed.work)")
    #expect(absorbed.rects.map { Array($0[0..<4]) } == [[80, 65, 40, 30], [90, 75, 20, 10]],
            "the fill must cover the frame layer's box, then the leaf: \(absorbed.rects)")

    let withInner = observe { legacyFrame(leaf().padding(insets)).background(.accent).padding(px(8)) }
    let armInner = GlobalElementID.child(of: rootID, at: 0, name: nil)
    let armPrefix = GlobalElementID.child(of: armInner, at: 0, name: nil)
    let armContent = GlobalElementID.child(of: armPrefix, at: 0, name: nil)
    #expect(withInner.bounds == [rootID: bounds(72, 57, 56, 46), armInner: bounds(80, 65, 40, 30),
                                 armPrefix: bounds(86, 71, 28, 18), armContent: bounds(90, 75, 20, 10)],
            "arm 2 bounds: \(withInner.bounds)")
    #expect(withInner.nodeCount == 5 && withInner.work == [1, 4, 5],
            "arm 2 nodes \(withInner.nodeCount), work \(withInner.work)")
    #expect(withInner.rects.map { Array($0[0..<4]) } == [[80, 65, 40, 30], [90, 75, 20, 10]], "arm 2 rects: \(withInner.rects)")
}

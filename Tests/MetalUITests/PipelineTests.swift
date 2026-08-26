import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// The runtime half of spec §4.1. `PhaseSeparationTests` pins what must not
// compile; this file pins what the three phases actually do when they run.

/// Records phase entries in order, and what each phase could see.
///
/// A **class**, held by reference from the probe element: `Element`'s phases are
/// `mutating` on a value type, so anything recorded into the struct itself would
/// be observed on whichever copy the driver happened to keep.
@MainActor
final class PhaseLog {
    var phases: [String] = []
    var boundsSeenInPrepaint: [Bounds<Pixels>] = []
    var boundsSeenInPaint: Bounds<Pixels>?
}

/// A row container with two fixed, **differently sized** children.
///
/// Deliberately not square and not uniform: a 400x100 root with a 100x40 and a
/// 60x20 child distinguishes width from height, the first child from the second,
/// and an absolute origin from a relative one. A symmetric probe would pass
/// against an engine that swapped either.
@MainActor
struct ProbeRow: Element {
    struct Layout {
        var root: LayoutNodeID
        var children: [LayoutNodeID]
    }
    struct Prepaint {
        var childBounds: [Bounds<Pixels>]
    }

    let log: PhaseLog

    func requestLayout(_ id: GlobalElementID?, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        log.phases.append("requestLayout")

        var rootStyle = Style()
        rootStyle.size = Size(width: .length(.pixels(Pixels(400))),
                              height: .length(.pixels(Pixels(100))))
        rootStyle.flexDirection = .row

        var first = Style()
        first.size = Size(width: .length(.pixels(Pixels(100))),
                          height: .length(.pixels(Pixels(40))))
        var second = Style()
        second.size = Size(width: .length(.pixels(Pixels(60))),
                           height: .length(.pixels(Pixels(20))))

        let children = [pass.requestNode(style: first, children: []),
                        pass.requestNode(style: second, children: [])]
        let root = pass.requestNode(style: rootStyle, children: children)
        return (root, Layout(root: root, children: children))
    }

    func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                  layout: inout Layout, pass: inout PrepaintPass) -> Prepaint {
        log.phases.append("prepaint")
        let childBounds = layout.children.map { pass.bounds(of: $0) }
        log.boundsSeenInPrepaint = childBounds
        return Prepaint(childBounds: childBounds)
    }

    func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
               layout: inout Layout, prepaint: inout Prepaint, pass: inout PaintPass) {
        log.phases.append("paint")
        log.boundsSeenInPaint = bounds
        for child in prepaint.childBounds {
            pass.fill(child, color: .white)
        }
    }
}

@MainActor
@Test func theThreePhasesRunInOrder() {
    let log = PhaseLog()
    var element = ProbeRow(log: log)
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(100)), scaleFactor: 1)

    frame.render(&element)

    #expect(log.phases == ["requestLayout", "prepaint", "paint"])
}

@MainActor
@Test func prepaintSeesBoundsTheEngineResolvedBetweenTheFirstTwoPhases() {
    // The engine runs *between* requestLayout and prepaint. If it did not, every
    // rect would still be the zero `LayoutTree.newNode` initialised it with —
    // which is a silent wrong answer, not a crash, and is why prepaint is the
    // first phase allowed to ask.
    let log = PhaseLog()
    var element = ProbeRow(log: log)
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(100)), scaleFactor: 1)

    frame.render(&element)

    #expect(log.boundsSeenInPrepaint.count == 2)
    let first = log.boundsSeenInPrepaint[0]
    let second = log.boundsSeenInPrepaint[1]

    // Every field asserted separately, with a distinct value in each: a single
    // `== Bounds(...)` on uniform numbers passes against a transposition.
    #expect(first.origin.x == Pixels(0))
    #expect(first.origin.y == Pixels(0))
    #expect(first.size.width == Pixels(100))
    #expect(first.size.height == Pixels(40))

    // The second child's origin is what makes this more than "the engine ran":
    // rects are absolute to the root, so `x` is the first child's width.
    #expect(second.origin.x == Pixels(100))
    #expect(second.origin.y == Pixels(0))
    #expect(second.size.width == Pixels(60))
    #expect(second.size.height == Pixels(20))
}

@MainActor
@Test func paintReceivesTheRootBoundsAndEmitsIntoTheFramesScene() throws {
    let log = PhaseLog()
    var element = ProbeRow(log: log)
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(100)), scaleFactor: 1)

    frame.render(&element)

    let root = try #require(log.boundsSeenInPaint)
    #expect(root.size.width == Pixels(400))
    #expect(root.size.height == Pixels(100))
    #expect(frame.scene.rects.count == 2)
}

@MainActor
@Test func fillScalesEveryComponentOfTheBoundsByTheDisplayFactor() throws {
    // Origin as well as size, and a non-square box at a factor that is not 1:
    // scaling the size alone leaves everything but the top-left item in the
    // wrong place on a Retina display, and a square box cannot tell width from
    // height.
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(100)), scaleFactor: 2)
    frame.fill(Bounds(origin: Point(x: Pixels(3), y: Pixels(7)),
                      size: Size(width: Pixels(40), height: Pixels(25))),
               color: .white)

    let rect = try #require(frame.scene.rects.first)
    #expect(rect.bounds.origin.x == 6)
    #expect(rect.bounds.origin.y == 14)
    #expect(rect.bounds.size.width == 80)
    #expect(rect.bounds.size.height == 50)
}

@MainActor
@Test func eachFrameOwnsItsOwnStateSoNothingLeaksBetweenFrames() {
    // §4.1: the tree is rebuilt from scratch every frame, with no diffing and no
    // persistent node graph. Two frames over the same element must produce the
    // same scene, not an accumulating one.
    let contentSize = Size(width: Pixels(400), height: Pixels(100))
    var element = ProbeRow(log: PhaseLog())

    let first = Frame(contentSize: contentSize, scaleFactor: 1)
    first.render(&element)
    let second = Frame(contentSize: contentSize, scaleFactor: 1)
    second.render(&element)

    #expect(first.scene.rects.count == 2)
    #expect(second.scene.rects.count == 2)
    #expect(first.tree.nodeCount == second.tree.nodeCount)
}

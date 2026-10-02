import Testing
import MetalUI

// MetalView lane 1, tests 1.4–1.10 (ruling `MV-E`; spec
// `docs/superpowers/specs/2026-10-01-metal-view-design.md` §4, §8). The one
// portable implementation of a surface's render-target lifecycle,
// `SurfaceTargetTable<Handle>` (`MetalUIPlatform`), generic over the
// backend's handle so the Metal and SDL renderers cannot drift. Portable: runs
// on Linux and Windows CI too. Handles here are plain `Int`s minted by the
// `create` closure; `released` logs what `release` was handed.

@MainActor
private final class Backend {
    var nextHandle = 100
    var created: [SurfaceTarget] = []
    var released: [Int] = []
    var failsCreate = false

    func create(_ target: SurfaceTarget) -> Int? {
        guard !failsCreate else { return nil }
        created.append(target)
        nextHandle += 1
        return nextHandle
    }

    func release(_ handle: Int) { released.append(handle) }
}

private func target(_ id: UInt64, _ w: Int = 20, _ h: Int = 10) -> SurfaceTarget {
    SurfaceTarget(id: SurfaceID(rawValue: id), width: w, height: h)
}

@MainActor
private func request(_ target: SurfaceTarget, scale: Float = 1, policy: RedrawPolicy = .onDemand,
                     value: AnyHashable? = nil) -> SurfaceDrawRequest {
    SurfaceDrawRequest(target: target, scaleFactor: scale, time: 0, policy: policy, value: value,
                       draw: { _ in })
}

/// One frame: `update`, then `didDraw` for everything it returned, as a
/// renderer does. Answers the ids drawn and whether each was new.
@MainActor
private func frame(_ table: inout SurfaceTargetTable<Int>, _ backend: Backend,
                   references: [SurfaceTarget], requests: [SurfaceDrawRequest]) -> [(UInt64, Bool)] {
    let toDraw = table.update(references: references, requests: requests,
                              create: { backend.create($0) }, release: { backend.release($0) })
    for item in toDraw { table.didDraw(item.request) }
    return toDraw.map { ($0.request.target.id.rawValue, $0.isNew) }
}

private func ids(_ drawn: [(UInt64, Bool)]) -> [UInt64] { drawn.map(\.0) }

/// **1.4** (`MV-E` item 1, `MV-G` item 2). A requested target is created once,
/// drawn as new, then reused: the same request next frame creates nothing and
/// draws nothing (spec §7.7's common case — the window redraws for another
/// reason and composites the last contents).
///
/// Mutation **M1e**: drop the value comparison (always draw).
@Test @MainActor func aRequestedTargetIsCreatedAndDrawnOnceThenReused() throws {
    var table = SurfaceTargetTable<Int>()
    let backend = Backend()
    let a = target(1)
    let first = frame(&table, backend, references: [a], requests: [request(a, value: 7)])
    try #require(first.count == 1, "the first frame draws the new target")
    #expect(first[0].0 == 1 && first[0].1, "drawn as new")
    #expect(table.handle(for: a.id) == 101)
    let second = frame(&table, backend, references: [a], requests: [request(a, value: 7)])
    #expect(second.isEmpty, "an unchanged .onDemand request is not redrawn: \(ids(second))")
    #expect(backend.created == [a] && backend.released.isEmpty)
    #expect(table.createdCount == 1 && table.drawnCount == 1 && table.liveCount == 1
            && table.releasedCount == 0)
}

/// **1.5** (`MV-G` item 2). A changed `value:` redraws into the same target;
/// an unchanged one does not.
///
/// Mutation **M1f**: `didDraw` does not store the value.
@Test @MainActor func aChangedValueRedrawsAndAnUnchangedOneDoesNot() throws {
    var table = SurfaceTargetTable<Int>()
    let backend = Backend()
    let a = target(1)
    _ = frame(&table, backend, references: [a], requests: [request(a, value: 1)])
    let same = frame(&table, backend, references: [a], requests: [request(a, value: 1)])
    let changed = frame(&table, backend, references: [a], requests: [request(a, value: 2)])
    let again = frame(&table, backend, references: [a], requests: [request(a, value: 2)])
    #expect(same.isEmpty, "unchanged: \(ids(same))")
    try #require(changed.count == 1, "a changed value redraws")
    #expect(!changed[0].1, "into the same target, not a new one")
    #expect(again.isEmpty, "and not again: \(ids(again))")
    #expect(table.createdCount == 1 && table.drawnCount == 2)
}

/// **1.6** (`MV-G` item 3; probe D1's `MTKView` draws continuously). A
/// `.continuous` request draws every frame, never reallocating.
///
/// Mutation **M1g**: treat `.continuous` as `.onDemand`.
@Test @MainActor func aContinuousRequestDrawsEveryFrame() throws {
    var table = SurfaceTargetTable<Int>()
    let backend = Backend()
    let a = target(1)
    let drawn = (0..<3).map { _ in
        frame(&table, backend, references: [a], requests: [request(a, policy: .continuous)]).count
    }
    #expect(drawn == [1, 1, 1])
    #expect(table.createdCount == 1 && table.drawnCount == 3)
}

/// **1.7** (`MV-E` item 1, `MV-G` item 2). A pixel-size change on either axis
/// releases the old target and creates a new one (drawn as new); a scale
/// change at the same pixel size redraws into the same target.
///
/// Mutations **M1h**: compare only width (the height-only resize keeps the old
/// target); **M1i**: ignore scale (the rescale draws nothing).
@Test @MainActor func aResizeReplacesTheTargetAndARescaleRedrawsWithoutReallocating() throws {
    var table = SurfaceTargetTable<Int>()
    let backend = Backend()
    _ = frame(&table, backend, references: [target(1, 20, 10)], requests: [request(target(1, 20, 10))])
    let wider = frame(&table, backend, references: [target(1, 30, 10)], requests: [request(target(1, 30, 10))])
    let taller = frame(&table, backend, references: [target(1, 30, 12)], requests: [request(target(1, 30, 12))])
    #expect(wider.map(\.1) == [true], "a width change is a new target: \(wider)")
    #expect(taller.map(\.1) == [true], "a height change is a new target: \(taller)")
    #expect(backend.created.map { [$0.width, $0.height] } == [[20, 10], [30, 10], [30, 12]])
    #expect(backend.released == [101, 102], "each old target released")
    let rescaled = frame(&table, backend, references: [target(1, 30, 12)],
                         requests: [request(target(1, 30, 12), scale: 2)])
    #expect(rescaled.map(\.1) == [false], "a rescale at the same pixel size redraws in place: \(rescaled)")
    #expect(table.createdCount == 3 && table.releasedCount == 2 && table.liveCount == 1)
}

/// **1.8** (`MV-E` item 1). An entry no scene target references is released;
/// one referenced **without a request** — a transition ghost, a drag preview
/// replaying its last snapshot — is kept and not drawn, so the ghost shows the
/// last contents.
///
/// Mutations **M1j**: release every entry without a request (the ghost's
/// target goes in frame 2); **M1k**: never release (frame 3 keeps it).
@Test @MainActor func anUnreferencedTargetIsReleasedAndAGhostsTargetIsKeptUndrawn() throws {
    var table = SurfaceTargetTable<Int>()
    let backend = Backend()
    let a = target(1), b = target(2, 8, 8)
    _ = frame(&table, backend, references: [a, b], requests: [request(a), request(b, policy: .continuous)])
    let ghostFrame = frame(&table, backend, references: [a, b], requests: [request(b, policy: .continuous)])
    #expect(ids(ghostFrame) == [2], "the ghost's target is not drawn: \(ids(ghostFrame))")
    #expect(table.handle(for: a.id) == 101 && backend.released.isEmpty, "and is kept")
    _ = frame(&table, backend, references: [b], requests: [request(b, policy: .continuous)])
    #expect(backend.released == [101], "unreferenced: released")
    #expect(table.handle(for: a.id) == nil && table.liveCount == 1 && table.releasedCount == 1)
}

/// **1.9** (`MV-E` item 1, `MV-H` item 5). A reference with no entry and no
/// request — a headless `renderFrame` scene handed to a renderer — creates
/// nothing, and its run draws nothing. A `create` returning nil drops that
/// request this frame.
///
/// Mutation **M1l**: create on reference.
@Test @MainActor func aReferenceWithoutARequestOrEntryCreatesNothing() throws {
    var table = SurfaceTargetTable<Int>()
    let backend = Backend()
    let drawn = frame(&table, backend, references: [target(1)], requests: [])
    #expect(drawn.isEmpty && backend.created.isEmpty && table.liveCount == 0 && table.createdCount == 0)
    #expect(table.handle(for: SurfaceID(rawValue: 1)) == nil)
    backend.failsCreate = true
    let failed = frame(&table, backend, references: [target(2)], requests: [request(target(2))])
    #expect(failed.isEmpty && table.liveCount == 0, "a failed create draws nothing and keeps nothing")
}

/// **1.10** (`MV-E` item 1, `MV-L` item 1). Two requests naming one id in one
/// frame trap — one element, one paint; `Frame` guarantees it by keying its
/// `SurfaceRegistry` on (`GlobalElementID`, occurrence).
///
/// Mutation **M1m**: drop the precondition.
@Test func twoRequestsForOneSurfaceTrap() async {
    await #expect(processExitsWith: .failure) {
        await MainActor.run {
            var table = SurfaceTargetTable<Int>()
            let a = SurfaceTarget(id: SurfaceID(rawValue: 1), width: 4, height: 4)
            let twice = [a, a].map {
                SurfaceDrawRequest(target: $0, scaleFactor: 1, time: 0, policy: .onDemand, value: nil,
                                   draw: { _ in })
            }
            _ = table.update(references: [a], requests: twice, create: { _ in 1 }, release: { _ in })
        }
    }
}

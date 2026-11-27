@testable import MetalUI
import MetalUITesting
import MetalUITestSupport
import Testing

// `FrameWork.maskScopesPushed` and `FrameWork.groupsMasked` (record 436): `Frame`'s `CM-A` work counters, read through
// `BuildWork`, so an app's tests can guard that no full-viewport mask group is drawn (Alloy's regression guard). Both are 0 for
// a tree with no crossing rounded clip and no shape-clipped group. The fixture is a 100 x 60 island clipped to a rounded
// rectangle of radius 10 around a 92 x 60 child of two leaves that is clipped to the same radius and sits `leading` points in
// from the island's leading edge. Two rounded clips CROSS when neither lies inside the other (`Frame.clipsCross`, `CM-B`): at
// `leading` 0 the child lies inside the island (each of its corner discs inside the island's), at 10 it overhangs the
// trailing edge by 2 points, so its trailing corners leave the island's rounded corners. A child inset from the corner
// squares by 4 or by 10 is inside and crosses nothing; the child's overhang is what crosses.

@MainActor private func island(leading: Int) -> some Element {
    HStack(spacing: Pixels(0)) {
        Color(.accent).frame(width: Pixels(46), height: Pixels(60))
        Color(.separator).frame(width: Pixels(46), height: Pixels(60))
    }
    .clipShape(RoundedRectangle(cornerRadius: Pixels(10)))
    .padding(Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(0), left: Pixels(Float(leading))))
    .frame(width: Pixels(100), height: Pixels(60), alignment: .topLeading)
    .clipShape(RoundedRectangle(cornerRadius: Pixels(10)))
    .frame(width: Pixels(200), height: Pixels(100))
}

@MainActor private func settled(leading: Int) async throws -> TestWindow {
    let w = try harnessWindow(size: sz(200, 100)) { island(leading: leading) }
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); w.tick()
    return w
}

/// **M1** A child inside the island (`leading` 0) crosses nothing, so no
/// mask scope is pushed and no group masked (`CM-A`, `CM-B`). Mutation: `maskScopesPushed` or `groupsMasked` initialised to 1
/// on `Frame`.
@Test @MainActor func aClipNothingCrossesPushesNoMaskScope() async throws {
    let w = try await settled(leading: 0)
    let all = w.frameWork.reduce(FrameWork(), +)
    #expect(all.builds > 0)
    #expect(all.maskScopesPushed == 0, "scopes \(all.maskScopesPushed)")
    #expect(all.groupsMasked == 0, "groups \(all.groupsMasked)")
    #expect(w.lastFrameWork.maskScopesPushed == 0 && w.lastFrameWork.groupsMasked == 0)
}

/// **M2** The same island with the child shifted 10 pt in, so it overhangs the trailing edge by 2 pt and its corners cross the island's, which is
/// drawn as a mask. Observed on a presented frame: exactly 1 mask scope and 1 masked group. One scope, because the island's clip is the
/// only shape clip and a mask scope is pushed once per clip (prepaint and paint together count it once: only paint pushes
/// it); one group, because the child is a single leaf whose captures the scope marks as one group (`CM-A`). Mutation: the
/// field wired to 0 in `testingOnFrameAdopted`.
@Test @MainActor func aChildCrossingTheCornerPushesOneMaskScopeAndMasksOneGroup() async throws {
    let w = try await settled(leading: 10)
    let f = w.lastFrameWork
    print("FrameWork mask counters, leading 10: scopes \(f.maskScopesPushed) groups \(f.groupsMasked)")
    #expect(f.maskScopesPushed == 1, "scopes \(f.maskScopesPushed)")
    #expect(f.groupsMasked == 1, "groups \(f.groupsMasked)")
}

/// **M3** An idle frame of the island costs what it did before the fields existed: five element requests and the allocations
/// below, all measured on master `eb25ea24` (324 allocations, 25,906 bytes) before this change; the fields are integer reads
/// of counters `Frame` already keeps. The allocation count is pinned exactly; the bytes rise by 16, the two `Int`s that every
/// stored `FrameWork` element now holds in the harness's `frameWork` array, and nothing else. Mutation: a `[String: Int]` built per frame in `testingOnFrameAdopted` (the allocation
/// count rises).
@Test @MainActor func theMaskCountersAddNothingToAnIdleFrame() async throws {
    let w = try await settled(leading: 0)
    w.resetFrameWork()
    #if canImport(Darwin)
    let seen = countAllocatedBytes { w.window.setNeedsRedraw(); w.tick() }
    let measured = try #require(seen)
    print("FrameWork mask counters, idle: requests \(w.lastFrameWork.elementRequests) allocations \(measured.allocations) bytes \(measured.bytes)")
    #expect(measured.allocations == 324, "allocations \(measured.allocations)")
    #expect(measured.bytes <= 25_906 + 16, "bytes \(measured.bytes)")
    #else
    w.window.setNeedsRedraw(); w.tick()
    #endif
    #expect(w.lastFrameWork.elementRequests == 5, "requests \(w.lastFrameWork.elementRequests)")
}

/// **M4** The sum carries both fields, and `+=` too. Mutation: either field dropped from `+`.
@Test func theSumOfTwoRecordsAddsTheMaskCounters() {
    let a = FrameWork(maskScopesPushed: 2, groupsMasked: 1)
    let b = FrameWork(maskScopesPushed: 3, groupsMasked: 5)
    let sum = a + b
    #expect(sum.maskScopesPushed == 5 && sum.groupsMasked == 6, "\(sum.maskScopesPushed) \(sum.groupsMasked)")
    var c = a
    c += b
    #expect(c == sum)
    #expect(FrameWork().maskScopesPushed == 0 && FrameWork().groupsMasked == 0)
}

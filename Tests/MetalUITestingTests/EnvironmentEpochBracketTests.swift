import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14-c lane 2 (`EE-J`, record §120): the bracket window's `.environment` and `.environmentObject` arms against the
// `.value` arm. Tests B1 and B3 of `docs/superpowers/specs/2026-10-14-environment-epoch-design.md` §4; B2 is the
// re-counted `.environment` row of `baselineArms` in `RetainedSubtreesBaselineTests`. Counts, never time.

/// The work counters of a drag frame two arms must share when an `@Environment` reader costs what a value does.
private struct EEWork: Equatable, CustomStringConvertible {
    let refusals: Int, evaluations: Int, skips: Int
    let requests: Int, prepaints: Int, paints: Int
    let hits: Int, misses: Int, ineligible: Int
    init(_ f: FrameWork) {
        refusals = f.contentRefusals; evaluations = f.contentEvaluations; skips = f.contentSkips
        requests = f.elementRequests; prepaints = f.elementPrepaints; paints = f.elementPaints
        hits = f.retainedHits; misses = f.retainedMisses; ineligible = f.retainedIneligible
    }
    var description: String {
        "refusals \(refusals) evaluations \(evaluations) skips \(skips) requests \(requests) prepaints \(prepaints) paints \(paints) hits \(hits) misses \(misses) ineligible \(ineligible)"
    }
}

/// One drag frame's counters, mid-drag, and the user-level node bodies over the whole drag, for a configuration.
@MainActor private func eeArm(_ arm: BracketArm, retained: Bool, prepaint: Bool, graft: Bool) throws -> (EEWork, Int) {
    let r = try bracketDragFrames(arm: arm, steps: 20, retained: retained, prepaint: prepaint, graft: graft)
    try #require(r.frames.count == 21)
    return (EEWork(r.frames[10]), BracketStats.nodeBodies)
}

/// The three configurations the arms are compared in: retention off, paint and prepaint replay, and the graft too.
private let eeConfigurations: [(name: String, retained: Bool, prepaint: Bool, graft: Bool)] = [
    ("retention off", false, false, false), ("replay", true, true, false), ("graft", true, true, true),
]

/// B1 — in every configuration the `.environment` arm's mid-drag frame counts what the `.value` arm's does: no
/// refusal, the same evaluations and skips, the same element requests, prepaints and paints, the same replays, and
/// the same 20 node bodies over the drag. **Red before (6273e3a4):** 11 refusals against 0, 231 node bodies against
/// 20, and element counts apart. Mutation: `memoShape` refuses on `hasEnvironment` again (the three configurations).
@Test(arguments: eeConfigurations.indices) @MainActor
func theEnvironmentArmCostsWhatTheValueArmCosts(index: Int) throws {
    let c = eeConfigurations[index]
    let (value, valueBodies) = try eeArm(.value, retained: c.retained, prepaint: c.prepaint, graft: c.graft)
    let (environment, environmentBodies) = try eeArm(.environment, retained: c.retained, prepaint: c.prepaint, graft: c.graft)
    #expect(environment == value, "\(c.name): .environment \(environment) vs .value \(value)")
    #expect(environment.refusals == 0, "\(c.name): refusals \(environment.refusals)")
    #expect(environmentBodies == valueBodies && environmentBodies == 20, "\(c.name): node bodies \(environmentBodies) vs \(valueBodies)")
}

/// B3 — the `.environmentObject` arm (an `@Observable` store read through `@Environment(Type.self)`, MetalCreator's
/// shape) is not refused and evaluates only the nodes that moved: no refusal, the `.value` arm's evaluations and skips
/// and node bodies. Its element counters are its own (the per-node scope is one more element). **Red before:** 11
/// refusals, 231 node bodies. Mutation: as B1.
@Test(arguments: eeConfigurations.indices) @MainActor
func theEnvironmentObjectArmCostsWhatTheValueArmCosts(index: Int) throws {
    let c = eeConfigurations[index]
    let (value, valueBodies) = try eeArm(.value, retained: c.retained, prepaint: c.prepaint, graft: c.graft)
    let (object, objectBodies) = try eeArm(.environmentObject, retained: c.retained, prepaint: c.prepaint, graft: c.graft)
    #expect(object.refusals == 0, "\(c.name): refusals \(object.refusals)")
    #expect(object.evaluations == value.evaluations && object.skips == value.skips, "\(c.name): .environmentObject \(object) vs .value \(value)")
    #expect(object.hits == value.hits && object.misses == value.misses && object.ineligible == value.ineligible, "\(c.name): replays \(object) vs \(value)")
    #expect(objectBodies == valueBodies && objectBodies == 20, "\(c.name): node bodies \(objectBodies) vs \(valueBodies)")
}

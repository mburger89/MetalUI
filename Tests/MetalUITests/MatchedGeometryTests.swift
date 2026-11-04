import Foundation
import Testing
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
@testable import MetalUI

// Round 3, item R3-2 — `matchedGeometryEffect` and the `Transition` protocol (ruling family `MG-`,
// `docs/superpowers/2026-10-31-matched-geometry-decisions.md`). SwiftUI's side is
// `docs/probes/swiftui-matched-geometry.swift` (arms MG1…, S1…, P1…, TP1…).
//
// **No test sleeps.** Every arm renders headless `Frame`s over one shared `StateTable` and `AnimationStore`
// at chosen timestamps (`TransitionHarness`): a resting frame at 0, the change at 0 under `linear(1)`, 0.5
// half-way, 1.0 landed.
//
// The stage: a `Column` of two 200 × 100 stacks. The first holds the 50 × 30 tile A at its top-leading corner
// under `if !flag`; the second holds the 100 × 60 tile B at its bottom-trailing corner under `if flag`. A is
// at (50, 50, 50, 30), B at (150, 190, 100, 60): they differ in origin and in size and sit under different
// parents.

private let linear1 = Animation.linear(duration: 1)
private let space = Namespace.ID(owner: .child(of: nil, at: 77, name: nil))
private let otherSpace = Namespace.ID(owner: .child(of: nil, at: 78, name: nil))

@MainActor private func isAccent(_ c: MUIHsla) -> Bool {
    let accent = Theme.light[.accent]
    return abs(c.h - accent.h) < 0.001 && abs(c.s - accent.s) < 0.001 && abs(c.l - accent.l) < 0.001
}

@MainActor private func accents(_ frame: Frame) -> [MUIRect] {
    frame.scene.rects.filter { isAccent($0.background) }
}

private struct R: Equatable, CustomStringConvertible {
    var x, y, w, h: Float
    var description: String { "(\(x), \(y), \(w)×\(h))" }
    init(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { (self.x, self.y, self.w, self.h) = (x, y, w, h) }
    init(_ r: MUIRect) { self.init(r.bounds.origin.x, r.bounds.origin.y, r.bounds.size.width, r.bounds.size.height) }
    func near(_ o: R, _ tol: Float = 0.01) -> Bool {
        abs(x - o.x) < tol && abs(y - o.y) < tol && abs(w - o.w) < tol && abs(h - o.h) < tol
    }
}

/// The accent rect `frame` painted for the view that arrives (the stage paints exactly one tile at rest and once a
/// flight has landed). **While the leaver fades there are two** (R4-3 PR C, `XF-M`: the leaver's ghost moves and fades,
/// the newcomer fades in while it flies): the newcomer is the one drawn last when it sits in the lower container (a swap
/// A -> B) and the first when it sits in the upper one (B -> A, `newcomerIsLast: false`), the leaver's ghost being the
/// first sublayer of its own container's run.
@MainActor private func one(_ frame: Frame, newcomerIsLast: Bool = true) -> R? {
    let all = accents(frame)
    guard !all.isEmpty, all.count <= 2 else { return nil }
    return R(newcomerIsLast ? all[all.count - 1] : all[0])
}

private let rectA = R(50, 50, 50, 30)
private let rectB = R(150, 190, 100, 60)

@MainActor private func tileA(_ w: Float = 50, _ h: Float = 30) -> some StyledElement {
    Box().frame(width: Pixels(w), height: Pixels(h)).background(.accent)
}

@MainActor private func tileB() -> some StyledElement {
    Box().frame(width: Pixels(100), height: Pixels(60)).background(.accent)
}

private struct MGOptions {
    var oldProperties: MatchedGeometryProperties = .frame
    var newProperties: MatchedGeometryProperties = .frame
    var oldSource = true
    var newSource = true
    var newAnchor: UnitPoint = .center
    var oldID = "hero"
    var newID = "hero"
    var oldSpace = space
    var newSpace = space
    var oldTransition: AnyTransition?
    var newTransition: AnyTransition?
    /// Both tiles present at once, whatever `flag` says.
    var both = false
}

@MainActor private func stage(_ flag: Bool, _ o: MGOptions = MGOptions()) -> some Element {
    // A transition written on the content must be the outermost group of what the `if` produces, so the
    // two spellings are two trees rather than a nested conditional.
    Column {
        if o.oldTransition != nil || o.newTransition != nil {
            stageWithTransitions(flag, o)
        } else {
            stagePlain(flag, o)
        }
    }
}

@MainActor private func stagePlain(_ flag: Bool, _ o: MGOptions) -> some Element {
    Column {
        Stack(alignment: .topLeading) {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if o.both || !flag {
                tileA().matchedGeometryEffect(id: o.oldID, in: o.oldSpace, properties: o.oldProperties, isSource: o.oldSource)
            }
        }
        Stack(alignment: .bottomTrailing) {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if o.both || flag {
                tileB().matchedGeometryEffect(id: o.newID, in: o.newSpace, properties: o.newProperties,
                                              anchor: o.newAnchor, isSource: o.newSource)
            }
        }
    }
}

@MainActor private func stageWithTransitions(_ flag: Bool, _ o: MGOptions) -> some Element {
    Column {
        Stack(alignment: .topLeading) {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if o.both || !flag {
                tileA().matchedGeometryEffect(id: o.oldID, in: o.oldSpace, properties: o.oldProperties, isSource: o.oldSource)
                    .transition(o.oldTransition ?? .identity)
            }
        }
        Stack(alignment: .bottomTrailing) {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if o.both || flag {
                tileB().matchedGeometryEffect(id: o.newID, in: o.newSpace, properties: o.newProperties,
                                              anchor: o.newAnchor, isSource: o.newSource)
                    .transition(o.newTransition ?? .identity)
            }
        }
    }
}

/// A swap A → B: rest at 0 (A), the change at 0 under `animation`, then 0.5 and 1.0 and 2.0.
@MainActor private func swap(_ o: MGOptions = MGOptions(), animation: Animation? = linear1)
    -> (rest: R?, start: R?, mid: R?, end: R?, settled: R?, harness: TransitionHarness) {
    let h = TransitionHarness()
    let rest = one(h.frame(0, nil, stage(false, o)))
    let start = one(h.frame(0, animation, stage(true, o)))
    let mid = one(h.frame(0.5, nil, stage(true, o)))
    let end = one(h.frame(1.0, nil, stage(true, o)))
    let settled = one(h.frame(2.0, nil, stage(true, o)))
    return (rest, start, mid, end, settled, h)
}

// MARK: - T-A: the handoff

/// **T-A (probe S1, S3, MG1).** When a view with an id leaves and another with the same id in the same
/// namespace appears in one transaction, the newcomer starts at the leaver's frame — position **and** size —
/// and lands on its own at the end of the animation. Red before: does not compile. Mutation **M-A**: never
/// start a flight (the newcomer paints at its own frame at 0).
@Test @MainActor func aNewcomerFliesFromTheLeaversFrameToItsOwn() throws {
    let r = swap()
    try #require(r.rest == rectA && r.settled == rectB, "set up: A at rest \(String(describing: r.rest)), B settled \(String(describing: r.settled))")
    #expect(r.start == rectA, "the frame that starts the change paints B at A's frame: \(String(describing: r.start))")
    let mid = R(100, 120, 75, 45)
    #expect(r.mid?.near(mid) == true, "half-way: B's frame is half-way between A's and its own, \(mid): \(String(describing: r.mid))")
    #expect(r.end == rectB, "landed at its own frame: \(String(describing: r.end))")
}

/// **T-B (probe MG1n).** No transaction, no flight: the newcomer is at its own frame at once.
/// Mutation **M-B**: ignore a missing animation (fly with the default).
@Test @MainActor func withoutATransactionTheNewcomerIsAtItsOwnFrameAtOnce() throws {
    let r = swap(animation: nil)
    #expect(r.start == rectB && r.mid == rectB, "instant: \(String(describing: r.start)), \(String(describing: r.mid))")
}

/// **T-C (probe S9, P5).** `.position` moves the newcomer's centre from the leaver's and keeps its own size;
/// `.size` keeps its centre and takes the leaver's size; both on the newcomer, as SwiftUI reads the effect on
/// the view that arrives. Mutation **M-C**: ignore `properties`.
@Test @MainActor func propertiesSelectWhichPartOfTheFrameIsHandedOver() throws {
    var o = MGOptions()
    o.newProperties = .position
    let position = swap(o)
    // Centre of A is (75, 65); B is 100 × 60: its frame starts at (25, 35).
    #expect(position.start == R(25, 35, 100, 60), ".position: A's centre, B's size: \(String(describing: position.start))")
    #expect(position.end == rectB, "landed: \(String(describing: position.end))")
    o.newProperties = .size
    let size = swap(o)
    // Centre of B is (200, 220): at A's size 50 × 30 its frame starts at (175, 205).
    #expect(size.start == R(175, 205, 50, 30), ".size: B's centre, A's size: \(String(describing: size.start))")
    #expect(size.end == rectB, "landed: \(String(describing: size.end))")
}

/// **T-D.** `anchor` picks the point of the newcomer's frame that is put at the leaver's: with `.position`
/// and `.topLeading` the newcomer's top-leading corner starts at the leaver's. MetalUI's own reading
/// (`MG-D`, SwiftUI's anchor is unprobed). Mutation **M-D**: ignore the anchor.
@Test @MainActor func anAnchorPicksTheCornerThatIsHandedOver() throws {
    var o = MGOptions()
    o.newProperties = .position
    o.newAnchor = .topLeading
    let r = swap(o)
    #expect(r.start == R(50, 50, 100, 60), "top-leading corner at A's: \(String(describing: r.start))")
}

/// **T-E (probe S2, S4–S8).** A leaver that SwiftUI removes at once — `.transition(.identity)` written on it —
/// hands nothing over: the newcomer is at its own frame. A leaver with a real removal transition does hand its
/// frame over, and its ghost is still drawn (S1, S7). Mutation **M-E**: hand over whatever the leaver's
/// transition.
@Test @MainActor func aLeaverRemovedByAnIdentityTransitionHandsNothingOver() throws {
    var o = MGOptions()
    o.oldTransition = .identity
    let identity = swap(o)
    #expect(identity.start == rectB, "an identity removal hands nothing over: \(String(describing: identity.start))")
    o.oldTransition = .opacity
    let h = TransitionHarness()
    h.frame(0, nil, stage(false, o))
    let started = accents(h.frame(0, linear1, stage(true, o)))
    #expect(started.count == 2, "with an opacity removal the ghost and the newcomer are both drawn: \(started.map(R.init))")
    #expect(started.map(R.init).contains(rectA), "the newcomer starts at A's frame: \(started.map(R.init))")
}

/// **T-F (probe S12, S13).** Only a leaver that is a source hands its frame over; a different id or a different
/// namespace matches nothing. Mutation **M-F**: match on the id alone / hand over from a non-source.
@Test @MainActor func onlyAMatchingSourceLeaverHandsItsFrameOver() throws {
    // R4-3 B2 (`XF-H`): with no handoff the unannotated leaver is no longer removed instantly but fades out in place
    // (SwiftUI's default, `XF3`) while the newcomer fades in at its own frame: **two accent rects, A's ghost and B**,
    // where these arms used to read the one rect B. A handoff (the last arm) still reads one rect, the flight.
    func cross(_ o: MGOptions) -> [R] {
        let h = TransitionHarness()
        h.frame(0, nil, stage(false, o))
        return accents(h.frame(0, linear1, stage(true, o))).map(R.init)
    }
    var nonSource = MGOptions()
    nonSource.oldSource = false
    #expect(cross(nonSource) == [rectA, rectB], "a non-source leaver hands nothing over (S12): it cross-fades in place")
    var otherID = MGOptions()
    otherID.newID = "other"
    #expect(cross(otherID) == [rectA, rectB], "a different id matches nothing")
    var otherNamespace = MGOptions()
    otherNamespace.newSpace = otherSpace
    #expect(cross(otherNamespace) == [rectA, rectB], "a different namespace matches nothing")
    var nonSourceNew = MGOptions()
    nonSourceNew.newSource = false
    #expect(swap(nonSourceNew).start == rectA, "a non-source newcomer still starts at the source leaver's frame (S11)")
}

// MARK: - T-G: sources and followers

/// **T-G (probe P1–P6).** Two live views with one id: the last source in tree order wins and every other view
/// is drawn at its frame (P1, P2, P3); with no source nothing is shared (P4). Mutation **M-G**: the first
/// source wins / a follower keeps its own frame.
@Test @MainActor func aFollowerIsDrawnAtTheSourcesFrame() throws {
    func painted(_ o: MGOptions) -> [R] {
        let h = TransitionHarness()
        return accents(h.frame(0, nil, stage(false, o))).map(R.init)
    }
    var both = MGOptions(); both.both = true
    #expect(painted(both).sorted { $0.x < $1.x } == [rectB, rectB], "P1: both sources, the later wins: \(painted(both))")
    var newFollows = both; newFollows.newSource = false
    #expect(painted(newFollows) == [rectA, rectA], "P2: B follows the source A: \(painted(newFollows))")
    var oldFollows = both; oldFollows.oldSource = false
    #expect(painted(oldFollows) == [rectB, rectB], "P3: A follows the source B: \(painted(oldFollows))")
    var neither = both; neither.oldSource = false; neither.newSource = false
    #expect(painted(neither).sorted { $0.x < $1.x } == [rectA, rectB], "P4: no source, nothing shared: \(painted(neither))")
    var position = newFollows; position.newProperties = .position
    #expect(painted(position).contains(R(25, 35, 100, 60)), "P5: .position follows the centre only: \(painted(position))")
}

// MARK: - T-H: what the flight does and does not touch

/// **T-H (rule `AN-AE` item 5 carried).** A flight is paint only: the newcomer's hitbox is at its final
/// geometry from the first frame, as an inserting transition's is. Mutation **M-H**: register the hitbox at
/// the flying rect.
@Test @MainActor func aFlyingViewIsHitAtItsFinalFrame() throws {
    func tree(_ flag: Bool) -> some Element {
        Column {
            Stack(alignment: .topLeading) {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if !flag { tileA().onClick {}.matchedGeometryEffect(id: "hero", in: space) }
            }
            Stack(alignment: .bottomTrailing) {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if flag { tileB().onClick {}.matchedGeometryEffect(id: "hero", in: space) }
            }
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    let started = h.frame(0, linear1, tree(true))
    let mid = h.frame(0.5, nil, tree(true))
    for (label, f) in [("start", started), ("mid", mid)] {
        #expect(f.hitboxes.contains { $0.bounds.origin.x.value == 150 && $0.bounds.origin.y.value == 190
                                      && $0.bounds.size.width.value == 100 },
                "\(label): the hitbox is at B's final frame: \(f.hitboxes.map(\.bounds))")
        #expect(!f.hitboxes.contains { $0.bounds.origin.x.value == 50 && $0.bounds.size.width.value == 50 },
                "\(label): nothing is hit at the flying or old frame")
    }
}

/// **T-I.** The modifier is identity- and layout-transparent: the same tree without it lays out and paints
/// the same at rest, and a flight in progress keeps the window's display link awake until it lands, then
/// leaves nothing in flight. Mutation **M-I**: omit `noteActiveAnimation()`.
@Test @MainActor func aFlightKeepsTheDisplayLinkAwakeThenLeavesNothing() throws {
    let model = MatchedModel()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 300, startsDisplayLink: true) {
        stage(model.flag)
    }
    platform.simulateTick(timestamp: 100)
    try #require(!window.hasActiveAnimations, "set up: nothing live at rest")
    withAnimation(.linear(duration: 1)) { model.flag = true }
    platform.simulateTick(timestamp: 100.1)
    #expect(window.hasActiveAnimations && window.animationStore.matched.liveCount == 1, "the first flying frame is live")
    platform.simulateTick(timestamp: 100.6)
    #expect(window.hasActiveAnimations, "half-way is live")
    platform.simulateTick(timestamp: 101.3)
    #expect(!window.hasActiveAnimations && window.animationStore.matched.liveCount == 0, "landed: nothing live")
    platform.simulateTick(timestamp: 101.4)
    #expect(platform.pauseCalls.last == true, "the display link pauses once it has landed")
}

@Observable @MainActor final class MatchedModel { var flag = false }

/// **T-J.** Adding the modifier moves no layout: a tree with it paints at rest exactly the rects the same tree
/// without it paints. Mutation **M-J**: wrap the content in a layout node.
@Test @MainActor func theModifierMovesNothingAtRest() throws {
    let with = TransitionHarness()
    let without = TransitionHarness()
    let a = accents(with.frame(0, nil, stage(true))).map(R.init)
    let b = accents(without.frame(0, nil, Column {
        Stack(alignment: .topLeading) { Box().frame(width: Pixels(200), height: Pixels(100)) }
        Stack(alignment: .bottomTrailing) { Box().frame(width: Pixels(200), height: Pixels(100)); tileB() }
    })).map(R.init)
    #expect(a == b && a == [rectB], "\(a) vs \(b)")
}

/// **T-K.** A flight that is interrupted by another swap in the same direction chain starts from where the
/// view was drawn, not from its layout frame: B → A → B mid-flight does not jump. Mutation **M-K**: start
/// from the leaver's layout frame.
@Test @MainActor func aFlightInterruptedByAnotherSwapStartsWhereTheViewWasDrawn() throws {
    let h = TransitionHarness()
    h.frame(0, nil, stage(false))
    h.frame(0, linear1, stage(true))
    let mid = one(h.frame(0.5, nil, stage(true)))
    try #require(mid?.near(R(100, 120, 75, 45)) == true, "set up: half-way \(String(describing: mid))")
    // Back to A at 0.5: A is the newcomer now and starts from where B was drawn.
    let back = one(h.frame(0.5, linear1, stage(false)), newcomerIsLast: false)
    #expect(back?.near(R(100, 120, 75, 45)) == true, "A starts where B was drawn: \(String(describing: back))")
    let end = one(h.frame(1.5, nil, stage(false)))
    #expect(end == rectA, "and lands on A: \(String(describing: end))")
}

// MARK: - The Transition protocol

/// SwiftUI's own example shape: scale and fade.
private struct Scaler: Transition {
    func body(content: TransitionContent, phase: TransitionPhase) -> TransitionContent {
        content.scaleEffect(phase.isIdentity ? 1 : 0.5).opacity(phase.isIdentity ? 1 : 0)
    }
}

private struct Mover: Transition {
    func body(content: TransitionContent, phase: TransitionPhase) -> TransitionContent {
        content.offset(x: Pixels(phase == .willAppear ? -40 : phase == .didDisappear ? 40 : 0))
    }
}

@MainActor private func transitionStage(_ shown: Bool, _ transition: AnyTransition) -> some Element {
    Column {
        Stack {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if shown { tileA().transition(transition) }
        }
    }
}

/// **T-L (probe TP1).** A custom `Transition` inserts with its `.willAppear` state moving to `.identity`:
/// scale ½ and alpha 0 at the start, the identity at the end. Red before: does not compile. Mutation
/// **T-L**: ignore the custom atoms.
@Test @MainActor func aCustomTransitionInsertsFromItsWillAppearState() throws {
    let h = TransitionHarness()
    h.frame(0, nil, transitionStage(false, AnyTransition(Scaler())))
    let start = accents(h.frame(0, linear1, transitionStage(true, AnyTransition(Scaler()))))
    let mid = accents(h.frame(0.5, nil, transitionStage(true, AnyTransition(Scaler()))))
    let end = accents(h.frame(1.0, nil, transitionStage(true, AnyTransition(Scaler()))))
    // The tile rests at (125, 135, 50, 30).
    try #require(end.count == 1 && R(end[0]) == R(125, 135, 50, 30), "set up: \(end.map(R.init))")
    #expect(start.count == 1 && start[0].background.a == 0 && R(start[0]).near(R(137.5, 142.5, 25, 15)),
            "willAppear: alpha 0, half scale about the centre: \(start.map(R.init)) a \(start.map(\.background.a))")
    #expect(mid.count == 1 && abs(mid[0].background.a - 0.5) < 0.001 && R(mid[0]).near(R(131.25, 138.75, 37.5, 22.5)),
            "half-way: \(mid.map(R.init)) a \(mid.map(\.background.a))")
}

/// **T-M (probe TP1 remove, TP2).** The same transition on removal plays `.didDisappear`: the ghost goes
/// to scale ½ and alpha 0, and an offset transition moves out to the opposite side of where it came in.
/// Mutation **M-M**: use `.willAppear` on removal.
@Test @MainActor func aCustomTransitionRemovesToItsDidDisappearState() throws {
    let h = TransitionHarness()
    h.frame(0, nil, transitionStage(true, AnyTransition(Mover())))
    let start = accents(h.frame(0, linear1, transitionStage(false, AnyTransition(Mover()))))
    let mid = accents(h.frame(0.5, nil, transitionStage(false, AnyTransition(Mover()))))
    #expect(start.map(R.init) == [R(125, 135, 50, 30)], "the ghost starts at rest: \(start.map(R.init))")
    #expect(mid.map(R.init) == [R(145, 135, 50, 30)], "didDisappear is +40 in x: half-way +20: \(mid.map(R.init))")
    let h2 = TransitionHarness()
    h2.frame(0, nil, transitionStage(false, AnyTransition(Mover())))
    let inStart = accents(h2.frame(0, linear1, transitionStage(true, AnyTransition(Mover()))))
    #expect(inStart.map(R.init) == [R(85, 135, 50, 30)], "willAppear is −40 in x: \(inStart.map(R.init))")
}

/// **T-N.** `body` is called with all three phases, and the resolved state is cached per frame: a transition
/// the store resolves reads `.willAppear` for the insertion and `.identity` for its end. Mutation **M-N**:
/// never call the identity phase.
@Test @MainActor func aCustomTransitionIsAskedForEveryPhase() throws {
    final class Seen: @unchecked Sendable { var phases: Set<TransitionPhase> = [] }
    struct Recording: Transition {
        let seen: Seen
        func body(content: TransitionContent, phase: TransitionPhase) -> TransitionContent {
            seen.phases.insert(phase)
            return content.opacity(phase.isIdentity ? 1 : 0)
        }
    }
    let seen = Seen()
    let t = AnyTransition(Recording(seen: seen))
    let h = TransitionHarness()
    h.frame(0, nil, transitionStage(false, t))
    h.frame(0, linear1, transitionStage(true, t))
    h.frame(2, nil, transitionStage(true, t))
    h.frame(2, linear1, transitionStage(false, t))
    #expect(seen.phases == [.willAppear, .identity, .didDisappear], "\(seen.phases)")
    #expect(TransitionPhase.willAppear.value == -1 && TransitionPhase.identity.value == 0
            && TransitionPhase.didDisappear.value == 1 && TransitionPhase.identity.isIdentity && !TransitionPhase.willAppear.isIdentity)
}

/// **T-O (rule `AN-AD`).** Reduce Motion turns a custom transition into an opacity one, as it does every
/// built-in but `.identity`. Mutation **M-O**: skip the substitution for custom transitions.
@Test @MainActor func reduceMotionTurnsACustomTransitionIntoAFade() throws {
    func stageRM(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tileA().transition(AnyTransition(Mover())) }
            }
            .environment(\.accessibilityReduceMotion, true)
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, stageRM(false))
    let mid = accents(h.frame(0.0, linear1, stageRM(true)))
    let half = accents(h.frame(0.5, nil, stageRM(true)))
    #expect(mid.map(R.init) == [R(125, 135, 50, 30)] && half.map(R.init) == [R(125, 135, 50, 30)] && half[0].background.a == 0.5,
            "faded in place: \(half.map(R.init)) a \(half.map(\.background.a))")
}

// MARK: - T-P: inside the retained machinery

/// A component that is equal while `flag` is: a still sibling of the one that flies.
private struct HeroStage: Component, @MainActor Equatable {
    let flag: Bool
    let id: String
    var content: some ElementGroup {
        Column {
            Stack(alignment: .topLeading) {
                Box().frame(width: Pixels(100), height: Pixels(40))
                if !flag { tileA().matchedGeometryEffect(id: id, in: space) }
            }
            Stack(alignment: .bottomTrailing) {
                Box().frame(width: Pixels(100), height: Pixels(40))
                if flag { tileB().matchedGeometryEffect(id: id, in: space) }
            }
        }
    }
    static func == (l: HeroStage, r: HeroStage) -> Bool { l.flag == r.flag && l.id == r.id }
}

/// A still pair in one occurrence: a source and a follower, both live, the follower drawn at the source's frame.
private struct StillPair: Component, @MainActor Equatable {
    let tag: Int
    var content: some ElementGroup {
        Column {
            Stack(alignment: .topLeading) {
                Box().frame(width: Pixels(100), height: Pixels(40))
                tileA().matchedGeometryEffect(id: "pair", in: otherSpace)
            }
            Stack(alignment: .bottomTrailing) {
                Box().frame(width: Pixels(100), height: Pixels(40))
                tileB().matchedGeometryEffect(id: "pair", in: otherSpace, isSource: false)
            }
        }
    }
}

/// **T-P.** Inside `.equatable()` occurrences, with a still sibling that the retained machinery skips while
/// another flies: the flight runs, the still one is not mistaken for a leaver, and landing leaves nothing in
/// flight. The `METALUI_VERIFY_RETAINED=1` oracle covers every frame (run the suite under it). Mutation
/// **M-P**: leave `buildActivity` at 0 (a grafted occurrence skips its claim and the sibling flies).
@Test @MainActor func aFlightInsideRetainedOccurrencesLeavesTheStillSiblingAlone() throws {
    let model = MatchedModel()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 400, startsDisplayLink: true) {
        Row {
            HeroStage(flag: model.flag, id: "left").equatable()
            HeroStage(flag: false, id: "still").equatable()
            StillPair(tag: 1).equatable()
        }
    }
    var grafts = 0
    var reasons: [String: Int] = [:]
    window.testingOnFrameAdopted { work in
        grafts += work.retained.grafts
        for (k, v) in work.retained.ineligibleReasons { reasons[k, default: 0] += v }
    }
    func pairRects() -> [R] {
        // The pair's tiles are the only 100 × 60 (follower) and 50 × 30 (source) accents sharing an origin.
        let rects = window.lastScene.rects.filter { isAccent($0.background) }.map(R.init)
        return rects.filter { r in rects.filter { $0.x == r.x && $0.y == r.y }.count == 2 }
    }
    platform.simulateTick(timestamp: 100)
    let first = pairRects()
    platform.simulateTick(timestamp: 100.05)
    platform.simulateTick(timestamp: 100.06)
    platform.simulateTick(timestamp: 100.07)
    try #require(first.count == 2, "set up: the follower is drawn on the source's frame, \(first)")
    #expect(pairRects() == first, "and stays there while its occurrence is retained: \(pairRects()) vs \(first)")
    try #require(window.animationStore.matched.liveCount == 0, "set up: nothing flies at rest")
    withAnimation(.linear(duration: 1)) { model.flag = true }
    platform.simulateTick(timestamp: 100.1)
    #expect(window.animationStore.matched.liveCount == 1, "exactly the changed occurrence flies")
    platform.simulateTick(timestamp: 100.6)
    platform.simulateTick(timestamp: 101.3)
    platform.simulateTick(timestamp: 101.4)
    #expect(window.animationStore.matched.liveCount == 0 && !window.hasActiveAnimations, "landed")
    #expect(reasons["matchedGeometry", default: 0] > 0 && grafts == 0,
            "an occurrence with a matched group is refused a graft by name: grafts \(grafts), reasons \(reasons)")
}

// MARK: - R4-3 PR C: the leaver moves as it fades (`XF-M`, divergence 897)
//
// SwiftUI's side: `docs/probes/swiftui-matched-geometry.swift` S1 (both cross-fade; the leaver moves with its own
// size), S12 (a non-source leaver moves to the source's centre), S9 (`.position`: same), S10 (`.size` alone: no motion),
// S13 (no source: no motion), S2 (`.identity`: no ghost). The stage is the swap above: A (50, 50, 50, 30), centre
// (75, 65), leaves for B (150, 190, 100, 60), centre (200, 220); the animation is `linear(1)`, read at 0.5.

/// The accent rects of `frame` as (rect, alpha), the leaver's ghost being the one of A's size.
@MainActor private func leaverAndNewcomer(_ frame: Frame, leaverWidth: Float = 50) -> (leaver: (R, Float)?, newcomer: (R, Float)?) {
    let all = accents(frame)
    func read(_ r: MUIRect) -> (R, Float) { (R(r), r.background.a) }
    return (all.first { $0.bounds.size.width == leaverWidth }.map(read), all.first { $0.bounds.size.width != leaverWidth }.map(read))
}

/// A swap mid-fade: the frame at 0.5 after the change at 0 under `linear(1)`.
@MainActor private func midSwap(_ o: MGOptions = MGOptions()) -> Frame {
    let h = TransitionHarness()
    h.frame(0, nil, stage(false, o))
    h.frame(0, linear1, stage(true, o))
    return h.frame(0.5, nil, stage(true, o))
}

/// **The leaver moves toward the source as it fades** (`S1`): half-way, A's ghost has travelled half the way from its
/// centre (75, 65) to B's (200, 220), keeping its own 50 × 30, at alpha 0.5. Mutations **MC1** (the full-frame map: the
/// leaver also takes B's size), **MC3** (the move is dropped for a source leaver), **MC4** (the whole unit's ghost is
/// translated), **MC6** (the move is never handed to the store).
@Test @MainActor func aLeaverMovesToTheSourceAsItFades() throws {
    let (leaver, newcomer) = leaverAndNewcomer(midSwap())
    try #require(leaver != nil && newcomer != nil, "set up: both are drawn")
    #expect(leaver!.0.near(R(112.5, 127.5, 50, 30)), "centre half-way to B's, own size: \(leaver!.0)")
    #expect(abs(leaver!.1 - 0.5) < 0.01, "and half faded: \(leaver!.1)")
    let start = leaverAndNewcomer({
        let h = TransitionHarness()
        h.frame(0, nil, stage(false))
        return h.frame(0, linear1, stage(true))
    }())
    #expect(start.leaver?.0 == rectA && start.leaver?.1 == 1, "the first frame draws it where it was, opaque: \(String(describing: start.leaver))")
}

/// **The newcomer fades while it flies** (`S1`; `XF-K` dropped its default insertion until this PR): half-way it is at the
/// flight's half-way frame at alpha 0.5, and it was transparent at the first frame. Mutation **MC5** (the newcomer's
/// default insertion is dropped on a flight again: alpha 1).
@Test @MainActor func theNewcomerFadesWhileItFlies() throws {
    let (_, newcomer) = leaverAndNewcomer(midSwap())
    try #require(newcomer != nil, "set up")
    #expect(newcomer!.0.near(R(100, 120, 75, 45)) && abs(newcomer!.1 - 0.5) < 0.01, "flying and half faded: \(newcomer!)")
    let h = TransitionHarness()
    h.frame(0, nil, stage(false))
    let first = accents(h.frame(0, linear1, stage(true)))
    #expect(first.count == 2 && first[1].background.a == 0, "transparent at the first frame: \(first.map { ($0.bounds.origin.x, $0.background.a) })")
    let end = one(h.frame(1.0, nil, stage(true)))
    #expect(end == rectB, "and opaque, alone, at its own frame at the end: \(String(describing: end))")
    #expect(accents(h.frame(1.0, nil, stage(true))).first.map(\.background.a) == 1)
}

/// **A non-source leaver moves too** (`S12`): the newcomer is at its own frame at once (no handoff) and A's ghost, which is
/// not a source, travels to B's centre keeping its size. Mutation **MC3** (only a source leaver moves).
@Test @MainActor func aNonSourceLeaverMovesToo() throws {
    var o = MGOptions()
    o.oldSource = false
    let (leaver, newcomer) = leaverAndNewcomer(midSwap(o))
    try #require(leaver != nil && newcomer != nil, "set up")
    #expect(leaver!.0.near(R(112.5, 127.5, 50, 30)), "S12: A's ghost half-way to B's centre: \(leaver!.0)")
    #expect(newcomer!.0 == rectB, "the newcomer is at its own frame: \(newcomer!.0)")
}

/// **`.position` moves the leaver, `.size` alone does not** (`S9`, `S10`). Mutation **MC2** (`properties` ignored).
@Test @MainActor func aSizeOnlyLeaverStays() throws {
    var position = MGOptions()
    position.oldProperties = .position; position.newProperties = .position
    let moved = leaverAndNewcomer(midSwap(position))
    #expect(moved.leaver?.0.near(R(112.5, 127.5, 50, 30)) == true, "S9: \(String(describing: moved.leaver))")
    var size = MGOptions()
    size.oldProperties = .size; size.newProperties = .size
    let stays = leaverAndNewcomer(midSwap(size), leaverWidth: 50)
    #expect(stays.leaver?.0 == rectA, "S10: the leaver stays where it was: \(String(describing: stays.leaver))")
}

/// **No source, no motion** (`S13`). Mutation **MC3**' (the leaver is moved toward its own frame / a missing source
/// treated as the newcomer).
@Test @MainActor func noSourceNoMotion() throws {
    var o = MGOptions()
    o.oldSource = false; o.newSource = false
    let (leaver, newcomer) = leaverAndNewcomer(midSwap(o))
    #expect(leaver?.0 == rectA && newcomer?.0 == rectB, "S13: nothing moves: \(String(describing: leaver)), \(String(describing: newcomer))")
}

/// **An `.identity` leaver has no ghost, so nothing moves and nothing is handed over** (`S2`).
@Test @MainActor func anIdentityLeaverHandsOverNothing() throws {
    var o = MGOptions()
    o.oldTransition = .identity
    let f = midSwap(o)
    #expect(accents(f).map(R.init) == [rectB], "S2: B alone, at its own frame: \(accents(f).map(R.init))")
}

/// **An annotated leaver that fades moves; one that does not fade stays** (`XF-M`): `.opacity` takes the translation
/// onto its own ghost; `.move(edge:)` has no opacity atom and keeps its transition alone.
@Test @MainActor func anAnnotatedLeaverMovesOnlyWhenItFades() throws {
    var fading = MGOptions()
    fading.oldTransition = .opacity; fading.newTransition = .identity
    let moved = leaverAndNewcomer(midSwap(fading))
    #expect(moved.leaver?.0.near(R(112.5, 127.5, 50, 30)) == true && abs((moved.leaver?.1 ?? 0) - 0.5) < 0.01,
            "an opacity leaver is ghosted, moved and faded: \(String(describing: moved.leaver))")
    var sliding = MGOptions()
    sliding.oldTransition = .move(edge: .leading); sliding.newTransition = .identity
    let slid = leaverAndNewcomer(midSwap(sliding))
    #expect(slid.leaver.map { $0.0.x < 50 && $0.0.y == 50 } == true,
            "a move leaver slides out by its own transition, not toward B: \(String(describing: slid.leaver))")
}

@MainActor private func unitStage(_ flag: Bool) -> some Element {
    Column {
        Stack(alignment: .topLeading) {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if !flag {
                tileA().matchedGeometryEffect(id: "hero", in: space)
                Box().frame(width: Pixels(20), height: Pixels(10)).background(.accent)
            }
        }
        Stack(alignment: .bottomTrailing) {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if flag { tileB().matchedGeometryEffect(id: "hero", in: space) }
        }
    }
}

/// **A multi-member unit moves only the matched member** (`XF4`-consistent): the unit `{ matched tile; plain 20 × 10 }`
/// fades as two members, and only the matched one travels. Mutation **MC4** (the whole unit's ghost translated).
@Test @MainActor func aMultiMemberUnitMovesOnlyTheMatchedMember() throws {
    let h = TransitionHarness()
    h.frame(0, nil, unitStage(false))
    h.frame(0, linear1, unitStage(true))
    let f = h.frame(0.5, nil, unitStage(true))
    let rects = accents(f)
    let plain = rects.first { $0.bounds.size.width == 20 }
    let tile = rects.first { $0.bounds.size.width == 50 && $0.bounds.size.height == 30 }
    try #require(plain != nil && tile != nil, "set up: \(rects.map(R.init))")
    #expect(R(tile!).near(R(112.5, 127.5, 50, 30)), "the matched tile travels: \(R(tile!))")
    #expect(R(plain!).x == 50 && R(plain!).y == 50, "the plain member fades in place: \(R(plain!))")
    #expect(abs(plain!.background.a - 0.5) < 0.01 && abs(tile!.background.a - 0.5) < 0.01, "both half faded")
}

private final class DisappearLog { var count = 0 }

/// **The moving leaver's ghost parks its `onDisappear`** (`XF-J` carried): the callback of the carved member waits for the
/// fade with the leaver's own ghost, not the unit's. Mutation **MC7** (the unit's ghost does not exempt the leaver's
/// position: the unit's ghost parks it, which here releases at the same tick, so the arm also reads the ghost count).
@Test @MainActor func aMovingLeaverStillParksItsDisappearAndLeavesTwoGhosts() throws {
    let model = MatchedModel()
    let log = DisappearLog()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 400, startsDisplayLink: true) {
        Column {
            Stack(alignment: .topLeading) {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if !model.flag {
                    tileA().matchedGeometryEffect(id: "hero", in: space).onDisappear { log.count += 1 }
                    Box().frame(width: Pixels(20), height: Pixels(10)).background(.accent)
                }
            }
            Stack(alignment: .bottomTrailing) {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if model.flag { tileB().matchedGeometryEffect(id: "hero", in: space) }
            }
        }
    }
    platform.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 1)) { model.flag = true }
    platform.simulateTick(timestamp: 100.1)
    #expect(window.animationStore.transitions.ghostCount == 2, "the unit's ghost and the leaver's own: \(window.animationStore.transitions.ghostCount)")
    #expect(log.count == 0 && window.animationStore.lifecycle.parkedCount == 1, "parked: \(log.count)")
    // The leaver's own ghost is the one that holds it: the unit's ghost carries the leaver's position as an exemption.
    let live = window.animationStore.transitions.liveGhosts
    #expect(window.animationStore.lifecycle.parkedOn == Set(live.filter { $0.exempt.isEmpty }.map(\.key)) && live.contains { !$0.exempt.isEmpty },
            "parked on the leaver's ghost, not the unit's: \(window.animationStore.lifecycle.parkedOn.count) of \(live.count)")
    platform.simulateTick(timestamp: 100.6)
    #expect(log.count == 0, "still waiting half-way")
    platform.simulateTick(timestamp: 101.3)
    platform.simulateTick(timestamp: 101.4)
    #expect(log.count == 1 && window.animationStore.transitions.ghostCount == 0, "released once at the end: \(log.count)")
}

/// **Re-inserting the unit during the fade takes the leaver's ghost down with the unit's** (`T4u` carried). Mutation
/// **MC8** (the leaver's ghost outlives its unit's).
@Test @MainActor func reinsertingTheUnitRemovesTheLeaversGhost() throws {
    let h = TransitionHarness()
    h.frame(0, nil, unitStage(false))
    h.frame(0, linear1, unitStage(true))
    try #require(h.store.transitions.ghostCount == 2, "set up: the unit's ghost and the leaver's")
    h.frame(0.5, nil, unitStage(true))
    h.frame(0.5, linear1, unitStage(false))
    // B, the newcomer of the first swap, is the leaver now: its own unit ghost and its own leaver ghost. A's two are gone.
    #expect(h.store.transitions.ghostCount == 2, "A's two ghosts went with the unit's return, B's two stand: \(h.store.transitions.ghostCount)")
}

/// **A leaver whose paint was a replay hands over as a fresh frame does** (`XF-N`, record 211; it was a pinned finding
/// until then). `MatchedGeometryStore` writes a record's `displayed` in `beginPaint` and its sequence range in
/// `noteSequences`, neither of which a paint replay runs. An `.equatable()` occurrence holding a matched group is built every
/// frame (refused a graft by name, `matchedGeometry`) but its **paint** is replayed once it has been steady for a few frames,
/// so the last frame's record had `displayed == nil`, the handoff's `old.displayed != nil` guard failed and no flight started.
/// A record now keeps the groups its paint window noted (`RetainedRecord.matched`, relative to its start) and `replayPaint`
/// re-notes them (`MatchedGeometryStore.renote`), as `XF-I` does the unit ranges. The oracle arm (retention off) is what every
/// arm must equal. Mutations **MR1** (`displayed` not re-noted: flights 0) and **MR2** (`sequences` not re-noted: ghosts 1).
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] != "1",
               "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts are not its to read"))
@MainActor func aLeaverInAReplayedOccurrenceHandsOverAsAFreshFrameDoes() throws {
    struct Panel: Component, @MainActor Equatable {
        let tag: Int
        var content: some ElementGroup { Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent) }
    }
    func run(retained: Bool, restFrames: Int) throws -> (flights: Int, ghosts: Int, hits: Int) {
        let model = MatchedModel()
        let w = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300))) {
            Row {
                HeroStage(flag: model.flag, id: "left").equatable()
                Panel(tag: 1).equatable()
            }
        }
        w.window.testingRetainedSubtrees = retained
        for _ in 0..<restFrames { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
        let hits = w.lastFrameWork.retainedHits
        withAnimation(.linear(duration: 1)) { model.flag = true }
        w.advance(by: 0.1)
        return (w.window.animationStore.matched.liveCount, w.window.animationStore.transitions.ghostCount, hits)
    }
    let steady = try run(retained: true, restFrames: 6)
    try #require(steady.hits > 0, "set up: the still panel's paint was a replay in the steady frames: \(steady.hits)")
    let oracle = try run(retained: false, restFrames: 6)
    #expect(oracle.flights == 1 && oracle.ghosts == 2, "the oracle (retention off): the flight starts and the leaver has its own ghost: \(oracle)")
    #expect(steady.flights == 1 && steady.ghosts == 2, "after replayed frames the handoff is the oracle's: \(steady)")
    let early = try run(retained: true, restFrames: 1)
    #expect(early.flights == 1 && early.ghosts == 2, "after one steady frame the paint is not yet a replay: \(early)")
}

/// **A leaver already at the source's centre has nothing to travel and stays in its unit's ghost** (`XF-M`): both tiles
/// share one centre in one container, so the move is zero and no second ghost is made. Mutation **MC13** (a zero move
/// still carves the leaver out: two ghosts).
@Test @MainActor func aLeaverAtTheSourcesCentreKeepsItsUnitsGhost() throws {
    func tree(_ flag: Bool) -> some Element {
        Stack(alignment: .center) {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if !flag { tileA().matchedGeometryEffect(id: "hero", in: space) }
            if flag { tileB().matchedGeometryEffect(id: "hero", in: space) }
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    let f = h.frame(0, linear1, tree(true))
    #expect(h.store.transitions.ghostCount == 1, "one ghost, the unit's: \(h.store.transitions.ghostCount) \(accents(f).map(R.init))")
}

// MARK: - R4-3c: a replayed occurrence re-notes its matched groups (`XF-N`, record 211)

@Observable @MainActor final class ReplayArmModel { var flag = false; var lead: Float = 10 }
private struct ReplayArmPanel: Component, @MainActor Equatable {
    let tag: Int
    var content: some ElementGroup { Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent) }
}
private struct ReplayArmOuter: Component, @MainActor Equatable {
    let flag: Bool
    var tick: Float = 0
    var content: some ElementGroup {
        Column { HeroStage(flag: flag, id: "n").equatable(); ReplayArmPanel(tag: 2).equatable() }
    }
}

/// What one run of an arm read: the retained hits before the flip, and per frame after it the flights, the ghosts and the
/// accent rectangles (sorted, with alpha).
private struct ReplayArmReading: Equatable {
    var hitsBefore = 0
    var frames: [String] = []
}

/// Runs `build` with retention on or off through six steady frames, `script`, then four frames of 0.1, 0.4, 0.4 and 0.4 s.
@MainActor private func replayArm(retained: Bool, build: @escaping (ReplayArmModel) -> some Element,
                                  script: (ReplayArmModel, TestWindow) -> Void = { m, _ in withAnimation(.linear(duration: 1)) { m.flag = true } }) throws -> ReplayArmReading {
    let m = ReplayArmModel()
    let w = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300))) { build(m) }
    w.window.testingRetainedSubtrees = retained
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    var out = ReplayArmReading(hitsBefore: w.lastFrameWork.retainedHits)
    script(m, w)
    for t in [0.1, 0.4, 0.4, 0.4] {
        w.advance(by: t)
        let rects = w.window.lastScene.rects.filter { isAccent($0.background) }.map { "\(R($0)) a=\(String(format: "%.2f", $0.background.a))" }
        out.frames.append("f\(w.window.animationStore.matched.liveCount) g\(w.window.animationStore.transitions.ghostCount) \(rects.sorted())")
    }
    return out
}

private let replayArmVerifying = ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1"

/// Reads an arm both ways, requires the retained run to have replayed (`METALUI_VERIFY_RETAINED=1` paints a hit as a miss, so
/// that set-up is its to skip) and equal the oracle frame for frame.
@MainActor private func replayArmPair(_ build: @escaping (ReplayArmModel) -> some Element,
                                      script: (ReplayArmModel, TestWindow) -> Void = { m, _ in withAnimation(.linear(duration: 1)) { m.flag = true } }) throws -> (on: ReplayArmReading, off: ReplayArmReading) {
    let on = try replayArm(retained: true, build: build, script: script)
    let off = try replayArm(retained: false, build: build, script: script)
    if !replayArmVerifying { try #require(on.hitsBefore > 0, "set up: the steady frames replayed paints: \(on.hitsBefore)") }
    #expect(on.frames == off.frames, "equal to the oracle (retention off):\n on  \(on.frames)\n off \(off.frames)")
    return (on, off)
}

@MainActor private func replayArmHero(_ m: ReplayArmModel) -> some Element {
    Row { HeroStage(flag: m.flag, id: "left").equatable(); ReplayArmPanel(tag: 1).equatable() }
}

/// **The plain arm** (`XF-N`): a hero occurrence and a still panel, six steady frames, a flip. The newcomer starts at the
/// leaver's frame and grows to its own, the leaver moves toward the source as it fades; the literals are the retention-off
/// frames. Mutations **MR1**, **MR2** (flights 1, ghosts 2 become 0 / 1).
@Test @MainActor func aReplayedLeaverFliesInThePlainArm() throws {
    let (on, _) = try replayArmPair(replayArmHero)
    let expected = [
        "f1 g2 [\"(130.0, 110.0, 50.0×30.0) a=0.00\", \"(130.0, 110.0, 50.0×30.0) a=1.00\", \"(230.0, 130.0, 40.0×40.0) a=1.00\"]",
        "f1 g2 [\"(130.0, 122.0, 70.0×42.0) a=0.40\", \"(140.0, 128.0, 50.0×30.0) a=0.60\", \"(230.0, 130.0, 40.0×40.0) a=1.00\"]",
        "f1 g2 [\"(130.0, 134.0, 90.0×54.0) a=0.80\", \"(150.0, 146.0, 50.0×30.0) a=0.20\", \"(230.0, 130.0, 40.0×40.0) a=1.00\"]",
        "f0 g0 [\"(130.0, 140.0, 100.0×60.0) a=1.00\", \"(230.0, 130.0, 40.0×40.0) a=1.00\"]",
    ]
    #expect(on.frames == expected, "\(on.frames)")
}

/// **A nested occurrence** (`XF-N`): the hero is an `.equatable()` inside an `.equatable()` outer one, so the outer record
/// holds what the inner replay re-noted (`renote` appends to `noted`). Mutation **MR4** (`renote` does not append: the outer
/// replay has nothing to re-note, flights 0).
@Test @MainActor func aReplayedLeaverFliesInANestedOccurrence() throws {
    let (on, _) = try replayArmPair { m in Row { ReplayArmOuter(flag: m.flag).equatable(); ReplayArmPanel(tag: 1).equatable() } }
    #expect(on.frames.first?.hasPrefix("f1 g2") == true && on.frames[1].contains("(130.0, 102.0, 70.0×42.0) a=0.40") && on.frames[1].contains("(140.0, 108.0, 50.0×30.0) a=0.60"),
            "\(on.frames)")
}

/// **A group that sits after painted content, and an outer occurrence that missed once with the inner one replaying** (`XF-N`): the
/// hero's sequence range is not at zero, so a re-note without the base arithmetic is wrong, and the outer record built on a frame
/// in which the inner one replayed holds the inner's re-noted group. Mutations **MR3** (no base) and **MR4** (`renote` does not append).
@Test @MainActor func aReplayedLeaverFliesAfterPaintedContentAndAnOuterMiss() throws {
    let (before, _) = try replayArmPair({ m in
        Row { Box().frame(width: Pixels(20), height: Pixels(20)).background(.red); HeroStage(flag: m.flag, id: "left").equatable(); ReplayArmPanel(tag: 1).equatable() }
    })
    #expect(before.frames[0].hasPrefix("f1 g2") && before.frames[1].contains("a=0.40") && before.frames[1].contains("a=0.60"), "\(before.frames)")
    let (nested, _) = try replayArmPair({ m in
        Row { ReplayArmOuter(flag: m.flag, tick: m.lead).equatable(); ReplayArmPanel(tag: 1).equatable() }
    }, script: { m, w in
        m.lead = 40
        for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
        withAnimation(.linear(duration: 1)) { m.flag = true }
    })
    #expect(nested.frames[0].hasPrefix("f1 g2") && nested.frames[1].contains("a=0.40") && nested.frames[1].contains("a=0.60"), "\(nested.frames)")
}

/// **A translated replay** (`XF-N`): the occurrence moved 30 points right while steady, so its record was `moved(to:)` and the
/// replay re-notes at the new origin; the flight starts at x 150 and the leaver reaches 160. Mutation **MR7** (`moved(to:)`
/// drops `matched`: flights 0).
@Test @MainActor func aReplayedLeaverFliesAfterATranslatedReplay() throws {
    let (on, _) = try replayArmPair({ m in
        Row { Box().frame(width: Pixels(m.lead), height: Pixels(10)); HeroStage(flag: m.flag, id: "left").equatable(); ReplayArmPanel(tag: 1).equatable() }
    }, script: { m, w in
        m.lead = 40
        for _ in 0..<2 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
        withAnimation(.linear(duration: 1)) { m.flag = true }
    })
    #expect(on.frames[0].hasPrefix("f1 g2") && on.frames[0].contains("(150.0, 110.0, 50.0×30.0) a=1.00") && on.frames[1].contains("(160.0, 128.0, 50.0×30.0) a=0.60"),
            "\(on.frames)")
}

/// **An interrupted flight and a second swap after landing equal the oracle** (`XF-N`): a live flight taints its recorder
/// (`noteActiveAnimation`), so `displayed = target` is never applied to a flight in progress. The interrupted arm starts no
/// flight in either run; the second swap starts from the first one's rest frame with the transaction half-way.
@Test @MainActor func aReplayedOccurrenceAfterAnInterruptedFlightOrALandingEqualsTheOracle() throws {
    let (interrupted, _) = try replayArmPair(replayArmHero, script: { m, w in
        withAnimation(.linear(duration: 1)) { m.flag = true }; w.advance(by: 0.5); withAnimation(.linear(duration: 1)) { m.flag = false }
    })
    #expect(interrupted.frames.last?.hasPrefix("f0 g0") == true, "settled: \(interrupted.frames)")
    let (second, _) = try replayArmPair(replayArmHero, script: { m, w in
        withAnimation(.linear(duration: 1)) { m.flag = true }; w.advance(by: 1.2)
        for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
        withAnimation(.linear(duration: 1)) { m.flag = false }
    })
    #expect(second.frames[0].hasPrefix("f1 g2") && second.frames[0].contains("(130.0, 119.0, 65.0×39.0) a=0.30"), "\(second.frames)")
}

/// **A replay that emits another count re-notes `displayed` but not the range** (`XF-N`, the `aDroppedReplayParksButDrawsNothing`
/// method: each standing record's `emitted` is broken by one, then one frame replays it): the group's sequence range would be
/// wrong, so the range is dropped and the leaver's own ghost carves nothing. Mutation **MR5** (the count check skipped).
@Test(.enabled(if: !replayArmVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts are not its to read"))
@MainActor func aReplayThatEmittedAnotherCountDropsTheMatchedRanges() throws {
    let m = ReplayArmModel()
    let w = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300))) {
        Row { HeroStage(flag: m.flag, id: "left").equatable(); ReplayArmPanel(tag: 1).equatable() }
    }
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    var broken = 0
    for entry in w.window.stateTable.contentMemos.allEntries where entry.record != nil {
        // The count is one over and the ranges one up, so a re-note that ignored the count would carve the wrong operations.
        entry.record?.emitted += 1
        entry.record?.matched = entry.record?.matched.map { (key: $0.key, range: ($0.range.lowerBound + 1)..<($0.range.upperBound + 1)) } ?? []
        broken += 1
    }
    try #require(broken > 0, "set up: records to break")
    w.window.setNeedsRedraw(); w.advance(by: 0.05)
    withAnimation(.linear(duration: 1)) { m.flag = true }
    w.advance(by: 0.1)
    let flights = w.window.animationStore.matched.liveCount, ghosts = w.window.animationStore.transitions.ghostCount
    #expect(flights == 1 && ghosts == 1, "the handoff runs and the leaver has no range of its own to carve: flights \(flights), ghosts \(ghosts)")
}

/// **`differences(from:)` names the matched groups** (`XF-N`): two records equal in everything else but the groups they hold are
/// not equal. Mutation **MR8** (`matched` ignored in `differences`).
@Test(.enabled(if: !replayArmVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: no standing record is read"))
@MainActor func twoRecordsDifferByTheirMatchedGroups() throws {
    let m = ReplayArmModel()
    let w = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300))) {
        Row { HeroStage(flag: m.flag, id: "left").equatable(); ReplayArmPanel(tag: 1).equatable() }
    }
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    let records = w.window.stateTable.contentMemos.allEntries.compactMap(\.record)
    let hero = try #require(records.first { !$0.matched.isEmpty }, "set up: the hero's record holds its matched groups")
    #expect(records.filter { !$0.matched.isEmpty }.count == 1, "and only the hero's does: \(records.map(\.matched.count))")
    let copy = hero.moved(to: hero.scene)
    #expect(hero.differences(from: copy, ignoringFinalStream: true) == nil, "set up: a copy is equal: \(String(describing: hero.differences(from: copy, ignoringFinalStream: true)))")
    copy.matched = []
    #expect(hero.differences(from: copy, ignoringFinalStream: true)?.hasPrefix("matched groups") == true, "\(String(describing: hero.differences(from: copy, ignoringFinalStream: true)))")
}

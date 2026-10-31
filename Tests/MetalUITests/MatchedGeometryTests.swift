import Testing
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
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

/// The one accent rect `frame` painted (the stage paints exactly one tile at rest and mid-flight).
@MainActor private func one(_ frame: Frame) -> R? {
    let all = accents(frame)
    return all.count == 1 ? R(all[0]) : nil
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
    var nonSource = MGOptions()
    nonSource.oldSource = false
    #expect(swap(nonSource).start == rectB, "a non-source leaver hands nothing over (S12)")
    var otherID = MGOptions()
    otherID.newID = "other"
    #expect(swap(otherID).start == rectB, "a different id matches nothing")
    var otherNamespace = MGOptions()
    otherNamespace.newSpace = otherSpace
    #expect(swap(otherNamespace).start == rectB, "a different namespace matches nothing")
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
    let back = one(h.frame(0.5, linear1, stage(false)))
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
        }
    }
    platform.simulateTick(timestamp: 100)
    platform.simulateTick(timestamp: 100.05)
    try #require(window.animationStore.matched.liveCount == 0, "set up: nothing flies at rest")
    withAnimation(.linear(duration: 1)) { model.flag = true }
    platform.simulateTick(timestamp: 100.1)
    #expect(window.animationStore.matched.liveCount == 1, "exactly the changed occurrence flies")
    platform.simulateTick(timestamp: 100.6)
    platform.simulateTick(timestamp: 101.3)
    platform.simulateTick(timestamp: 101.4)
    #expect(window.animationStore.matched.liveCount == 0 && !window.hasActiveAnimations, "landed")
}

import Foundation
import MetalUICore
import MetalUILayout

/// Whether the layout memo recomputes and compares every hit (`IV-J`): the
/// environment variable `METALUI_VERIFY_LAYOUT_MEMO` equal to `1`, read once.
let layoutMemoVerifiesFromEnvironment: Bool =
    ProcessInfo.processInfo.environment["METALUI_VERIFY_LAYOUT_MEMO"] == "1"

/// Animation state that must **not** be `StateTable` state (rulings `AN-AB`,
/// `AN-Y` item 5): `.animation(_:value:)`'s previous values now, and — lanes 2
/// and 3 of plan task 13 — proposal modifier tracks, a `Component`'s op
/// tracks, the legacy border-colour track and transitions (`transitions`); and
/// since C10 lane 2 each keyframe animator's record (`KeyframeRecord`, keyed
/// `$keyframes<depth>` under its position, `LK-I` item 9).
///
/// **Window-owned, one per window** (a fresh one per headless `renderFrame`
/// and per test-built `Frame`), handed to each `Frame`.
///
/// **Every entry a frame does not touch is dropped at the end of that frame**
/// (`endFrame()`). So content that leaves and returns starts fresh — the
/// answer `ID-C`/`DD-C` give the `$anim` slots — with no reset hook; a `List`
/// row out of its window is not evaluated, drops its entries and returns as a
/// first sighting, which snaps (as proposal content always has). And nothing
/// here adds a `StateTable` entry: no `TB-AH` threshold, pinned table count or
/// reserved name moves (`theSevenRetentionSlotsAreMutuallyDistinct` is
/// untouched). **The cost, stated** (`AN-AB`): a keyed value that is not
/// touched for ONE frame is gone, where a `StateTable` entry survives two
/// generations above 256 entries — SwiftUI's answer for a removed view.
///
/// Reading marks an entry touched as writing does, so a reader that finds its
/// value unchanged keeps it without rewriting it.
@MainActor
final class AnimationStore {
    private var entries: [GlobalElementID: Any] = [:]
    private var touched: Set<GlobalElementID> = []

    /// The entries touched this build, for verify mode's comparison of a graft with a fresh build (`RK-N`).
    var touchedIDs: Set<GlobalElementID> { touched }
    private var interpolationsThisFrame = 0

    /// The transition seam (spec §6.5): lane 1 of plan task 13 declares it as a
    /// stub the frame calls at three points; lane 3 fills it.
    let transitions = TransitionStore()

    /// `matchedGeometryEffect`'s records and flights (round 3 item R3-2, `MG-A`), beside the transitions.
    let matched = MatchedGeometryStore()

    /// The window's CPU rasters — paths and shadows (ruling `GX-K`), owned
    /// here so a `Window`'s frames share one and a headless frame gets its own.
    let rasters = RasterCache()

    /// The window's layout memo (`IV-E`), owned here as `rasters` is: a `Window`'s
    /// frames share one and a headless frame gets its own. **Not a `StateTable`
    /// entry** (the seven slots unmoved) and holds no node id.
    let layoutMemo = LayoutMemo(verifies: layoutMemoVerifiesFromEnvironment)

    /// The lifecycle modifiers' entries, parked disappearances and unrun
    /// events (ruling `LC-D`), owned here so a `Window`'s frames share one and
    /// a headless frame gets its own. **`endFrame()` does not close it**: the
    /// lifecycle's build ends after `StateTable.sweep()` (`Frame.render`), whose
    /// departed values its disappearances read (`LC-I`).
    let lifecycle = LifecycleStore()

    /// The window's `TimelineView` cursors and its one wake (ruling `KF-K`
    /// items 3–4), owned here so a `Window`'s frames share one and a headless
    /// frame gets its own; closed by `endFrame()` with the other entries.
    let timeline = TimelineStore()

    /// How many keyframe animators enclose the one being built (C10 lane 2,
    /// `LK-I` item 9): the `<depth>` of its `$keyframes<depth>` key, so two
    /// stacked at one position keep two records — `Frame.lifecycleDepth`'s
    /// shape, held here because the records are this store's.
    private(set) var keyframeDepth = 0

    /// Runs `body` one keyframe animator deeper.
    func withKeyframeScope<T>(_ body: () -> T) -> T {
        keyframeDepth += 1
        defer { keyframeDepth -= 1 }
        return body()
    }

    /// Interpolations performed by the last completed frame — a work counter
    /// (spec test 2.12), counted by `noteInterpolation()`.
    private(set) var lastFrameInterpolations = 0

    init() {}

    /// Border-width track keys (`"border.top"` …) built so far, a cumulative work counter (`HP-C`):
    /// a tree with nothing in flight and no changed border builds none.
    private(set) var borderKeyBuilds = 0
    func noteBorderKeyBuilds(_ n: Int) { borderKeyBuilds += n }

    /// Numeric-layer tracks (`animatedNumbers`) that took the slow path - a copy of the stored
    /// track, a rebuilt state and a comparison - so far, cumulative (`HP-C`). A settled layer whose
    /// declared numbers equal its baseline bit for bit takes the early return and counts nothing.
    private(set) var numberTrackRebuilds = 0
    func noteNumberTrackRebuild() { numberTrackRebuilds += 1 }

    /// How many entries survive — test observability (1.12).
    var count: Int { entries.count }

    /// The value stored at `id`, marking it touched this frame.
    func value(at id: GlobalElementID) -> Any? {
        buildJournal?.record(.animationTouch(id))
        retainLog?.touches.append(.touch(id))
        touched.insert(id)
        return entries[id]
    }

    /// The value stored at `id` as a `T`, marking it touched this frame.
    func value<T>(at id: GlobalElementID, as type: T.Type) -> T? {
        value(at: id) as? T
    }

    /// Stores `value` at `id`, marking it touched this frame.
    func set(_ value: Any, at id: GlobalElementID) {
        buildJournal?.record(.animationTouch(id))
        retainLog?.touches.append(.set(id, value))
        entries[id] = value
        touched.insert(id)
    }

    /// Counts one interpolation in the frame being built.
    func noteInterpolation() {
        interpolationsThisFrame += 1
        retainLog?.taint("interpolation")
    }

    /// Interpolations counted so far in the frame being built (`SB-`): a retained
    /// subtree's build window reads the difference.
    var interpolationsSoFar: Int { interpolationsThisFrame }

    /// The open recorders' log, set by `Frame` while any is open (`SB-D`).
    var retainLog: RetainLog?

    /// The window's build journal (`RK-F`): the memo store's, attached when a graft window first opens, and shared
    /// with the transition store.
    var buildJournal: BuildJournal?

    func attach(_ journal: BuildJournal) {
        buildJournal = journal
        transitions.buildJournal = journal
        lifecycle.buildJournal = journal
    }

    /// Keeps the entry at `id` for this frame without reading it (a graft standing for a build that read or set it).
    func touch(_ id: GlobalElementID) {
        buildJournal?.record(.animationTouch(id))
        touched.insert(id)
    }

    /// Whether an entry is stored at `id`.
    func hasEntry(_ id: GlobalElementID) -> Bool { entries[id] != nil }

    /// Replays a recorded touch: the entry stays alive; a recorded first sighting is stored
    /// again only if the entry was dropped meanwhile.
    func replay(_ touch: RetainLog.Touch) {
        switch touch {
        case .touch(let id):
            retainLog?.touches.append(touch)
            touched.insert(id)
        case .set(let id, let value):
            retainLog?.touches.append(touch)
            if entries[id] == nil { entries[id] = value }
            touched.insert(id)
        }
    }

    /// What a redo restores (`RK-M`): the entries, and the transition store's in-flight state. The lifecycle,
    /// timeline and surface stores hold only this build's accumulators, which are empty at its start.
    struct Checkpoint {
        let entries: [GlobalElementID: Any]
        let transitions: TransitionStore.Checkpoint
        let matched: MatchedGeometryStore.Checkpoint
    }

    func checkpoint() -> Checkpoint { Checkpoint(entries: entries, transitions: transitions.checkpoint(), matched: matched.checkpoint()) }

    /// Puts every channel a build mutates before adoption back to `saved` (`RK-M`): called by the window when a
    /// frame is abandoned for a redo, before the rebuild, so the rebuild is a build of the frame that never ran.
    func rollbackBuild(_ saved: Checkpoint) {
        entries = saved.entries
        touched.removeAll(keepingCapacity: true)
        interpolationsThisFrame = 0
        lifecycle.rollbackBuild()
        timeline.rollbackBuild()
        transitions.rollbackBuild(saved.transitions)
        matched.rollbackBuild(saved.matched)
    }

    /// Called by `Frame.render` before layout.
    func beginFrame() { interpolationsThisFrame = 0 }

    /// Called by `Frame.render` after paint: drops every entry this frame did
    /// not touch.
    func endFrame() {
        if touched.count != entries.count {
            entries = entries.filter { touched.contains($0.key) }
        }
        touched.removeAll(keepingCapacity: true)
        lastFrameInterpolations = interpolationsThisFrame
        timeline.endFrame()  // drops untouched timelines, (re)schedules or cancels the wake (KF-K item 3)
    }
}

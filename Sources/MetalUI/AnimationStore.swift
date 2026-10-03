import MetalUICore

/// Animation state that must **not** be `StateTable` state (rulings `AN-AB`,
/// `AN-Y` item 5): `.animation(_:value:)`'s previous values now, and — lanes 2
/// and 3 of plan task 13 — proposal modifier tracks, a `Component`'s op
/// tracks, the legacy border-colour track and transitions (`transitions`).
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
    private var interpolationsThisFrame = 0

    /// The transition seam (spec §6.5): lane 1 of plan task 13 declares it as a
    /// stub the frame calls at three points; lane 3 fills it.
    let transitions = TransitionStore()

    /// The window's CPU rasters — paths and shadows (ruling `GX-K`), owned
    /// here so a `Window`'s frames share one and a headless frame gets its own.
    let rasters = RasterCache()

    /// The lifecycle modifiers' entries, parked disappearances and unrun
    /// events (ruling `LC-D`), owned here so a `Window`'s frames share one and
    /// a headless frame gets its own. **`endFrame()` does not close it**: the
    /// lifecycle's build ends after `StateTable.sweep()` (`Frame.render`), whose
    /// departed values its disappearances read (`LC-I`).
    let lifecycle = LifecycleStore()

    /// Interpolations performed by the last completed frame — a work counter
    /// (spec test 2.12), counted by `noteInterpolation()`.
    private(set) var lastFrameInterpolations = 0

    init() {}

    /// How many entries survive — test observability (1.12).
    var count: Int { entries.count }

    /// The value stored at `id`, marking it touched this frame.
    func value(at id: GlobalElementID) -> Any? {
        touched.insert(id)
        return entries[id]
    }

    /// The value stored at `id` as a `T`, marking it touched this frame.
    func value<T>(at id: GlobalElementID, as type: T.Type) -> T? {
        value(at: id) as? T
    }

    /// Stores `value` at `id`, marking it touched this frame.
    func set(_ value: Any, at id: GlobalElementID) {
        entries[id] = value
        touched.insert(id)
    }

    /// Counts one interpolation in the frame being built.
    func noteInterpolation() { interpolationsThisFrame += 1 }

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
    }
}

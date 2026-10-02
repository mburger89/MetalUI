import MetalUICore
import MetalUIScene

/// A window's map from a painted app-owned surface to its `SurfaceID`
/// (MetalView, rulings `MV-E` item 6 and `MV-L` item 1): **window-owned, one per
/// window** beside `AnimationStore` (a fresh one per headless `renderFrame` and
/// per test-built `Frame`), handed to each `Frame`.
///
/// **Not a `StateTable` entry**: a render target is GPU state the renderer owns,
/// keyed by a window-minted `SurfaceID`, and the state table's identity rules
/// (`TB-AH`'s two generations) are wrong for it — a surface that is not painted
/// does no work and should not hold GPU memory. The seven reserved slot names
/// do not move (`theSevenRetentionSlotsAreMutuallyDistinct`).
///
/// **The key is (`GlobalElementID`, occurrence)**, the occurrence counting
/// surfaces with that id already painted this frame — so two siblings sharing
/// one `.id` (divergence 72) get two targets rather than two requests for one,
/// which a renderer's `SurfaceTargetTable` traps on (`MV-L` item 1). Each keeps
/// its target across frames while the paint order holds.
///
/// A surface minted on first sight keeps its id while it is painted every
/// frame; one not painted in a frame is dropped at ``endFrame()``, so coming
/// back is a new id — a new target, which redraws (`MV-G` item 4). Ids are
/// never reused within a window, so a transition ghost still holding an old
/// id never aliases a new surface.
@MainActor
final class SurfaceRegistry {
    private struct Key: Hashable {
        let element: GlobalElementID
        let occurrence: Int
    }

    private var ids: [Key: SurfaceID] = [:]
    private var occurrences: [GlobalElementID: Int] = [:]
    private var painted: Set<Key> = []
    private var nextID: UInt64 = 1

    init() {}

    /// How many surfaces hold an id — test observability.
    var count: Int { ids.count }

    /// The id of the next surface painted for `element` this frame, minted on
    /// first sight.
    func id(for element: GlobalElementID) -> SurfaceID {
        let occurrence = occurrences[element, default: 0]
        occurrences[element] = occurrence + 1
        let key = Key(element: element, occurrence: occurrence)
        painted.insert(key)
        if let id = ids[key] { return id }
        let id = SurfaceID(rawValue: nextID)
        nextID += 1
        ids[key] = id
        return id
    }

    /// Drops every surface this frame did not paint and starts the next
    /// frame's occurrence count.
    func endFrame() {
        ids = ids.filter { painted.contains($0.key) }
        painted.removeAll(keepingCapacity: true)
        occurrences.removeAll(keepingCapacity: true)
    }
}

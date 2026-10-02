import MetalUICore
import MetalUIScene

/// When an app-owned GPU surface redraws (MetalView, ruling `MV-G`; spec
/// §7.7's names).
///
/// - `.onDemand`: when its render target is new (first sight, a resize, a
///   rescale) or its `value:` differs from the one it last drew. A window
///   redraw for any other reason composites the last contents with no GPU work
///   for the surface.
/// - `.continuous`: every frame it paints, keeping the display link awake
///   through `Frame.noteActiveAnimation()` — never `requestAnotherFrame()`.
public enum RedrawPolicy: Sendable, Hashable {
    case onDemand, continuous
}

/// What an app-owned surface's `draw` closure receives (ruling `MV-F` item 4):
/// the portable half of the backend's draw context. App code downcasts to the
/// backend it encodes for — `MetalDrawContext` on the Metal renderer,
/// `SDLGPUDrawContext` on the SDL one — or uses ``clear(red:green:blue:alpha:)``,
/// the one portable operation.
///
/// **Main actor, inside the renderer's `finishFrame`**, after the frame's
/// command buffer exists and **before** MetalUI's own pass begins, so no
/// MetalUI encoder is open while app code runs (`MV-F` item 3). The app must
/// not commit, present, wait on or submit the command buffer, and must end
/// every pass it begins (`MV-F` item 5).
@MainActor
public protocol GPUSurfaceContext {
    /// The render target's size in device pixels — the element's bounds × the
    /// scale, rounded, clamped to 8192 (`MV-E` item 2).
    var pixelSize: Size<DevicePixels> { get }
    /// The window's scale factor this frame.
    var scaleFactor: Float { get }
    /// The frame's display-link target timestamp in seconds (spec §4.4) — the
    /// same instant every element of the frame sees.
    var time: Double { get }
    /// The renderer's count of finished frames.
    var frameIndex: UInt64 { get }
    /// Whether the target was created (cleared to transparent) this frame.
    var isNewTarget: Bool { get }
    /// Clears the whole target to a **premultiplied**, gamma-space colour in
    /// one load-op-clear pass (`MV-D`: the image pipeline composites a texel
    /// as premultiplied source-over in gamma space, §7.8).
    func clear(red: Float, green: Float, blue: Float, alpha: Float)
}

/// One surface's draw request for one frame (ruling `MV-F` item 2), handed by
/// `Window` to `WindowRenderer.finishFrame(scene:atlas:surfaces:)` in paint
/// order. Not part of the `Scene`, which stays `Sendable` data: a closure is
/// neither.
public struct SurfaceDrawRequest {
    /// The target the scene's quad samples — its id and device-pixel size.
    public let target: SurfaceTarget
    /// The frame's scale factor.
    public let scaleFactor: Float
    /// The frame's display-link timestamp (spec §4.4).
    public let time: Double
    /// When it redraws (`MV-G`).
    public let policy: RedrawPolicy
    /// The `value:` an `.onDemand` surface redraws on, `nil` without one.
    public let value: AnyHashable?
    /// The app's drawing, run by the renderer on the main actor.
    public let draw: @MainActor (any GPUSurfaceContext) -> Void

    /// A request for `target`.
    public init(target: SurfaceTarget, scaleFactor: Float, time: Double, policy: RedrawPolicy,
                value: AnyHashable?, draw: @escaping @MainActor (any GPUSurfaceContext) -> Void) {
        self.target = target
        self.scaleFactor = scaleFactor
        self.time = time
        self.policy = policy
        self.value = value
        self.draw = draw
    }
}

/// The one portable implementation of a surface render target's lifecycle
/// (ruling `MV-E` item 1), generic over the backend's texture handle so the
/// Metal and SDL renderers cannot drift. Owned **per window** by its
/// `WindowRenderer` (`MV-E` item 3): `SurfaceID`s are minted per window, so two
/// windows never evict each other's targets.
///
/// Each frame ``update(references:requests:create:release:)`` takes the
/// scene's `surfaceTargets` and the frame's requests and:
/// - releases every entry **no scene target references** (an element that
///   left, was hidden, scrolled out of a `List`'s window, went fully clipped or
///   transparent);
/// - creates an entry for a request with none, and replaces (releases, then
///   creates) one whose pixel size differs — either is a **new** target;
/// - keeps, **undrawn**, an entry referenced without a request (a transition
///   ghost, a drag preview), so it shows the last contents;
/// - creates nothing for a reference with no entry and no request (its run
///   draws nothing);
/// - returns the requests to draw this frame, in request (= paint) order:
///   new → draw; `.continuous` → draw; otherwise a `value:` or scale differing
///   from the last ``didDraw(_:)`` → draw.
///
/// A `create` returning `nil` drops that request this frame. Two requests
/// naming one id in one frame **trap** (one element, one paint — `Frame`
/// guarantees it by keying its `SurfaceRegistry` on (`GlobalElementID`,
/// occurrence), `MV-L` item 1).
///
/// Public because `Backends/SDL` is another package; its counters are
/// `package`, which does not cross that boundary, so `SDLWindowRenderer`
/// counts for itself (`MV-L` item 2).
public struct SurfaceTargetTable<Handle> {
    private struct Entry {
        var handle: Handle
        var width: Int
        var height: Int
        /// The `value:` and scale of the last draw; `nil` until one.
        var lastDrawn: (value: AnyHashable?, scale: Float)?
    }

    private var entries: [SurfaceID: Entry] = [:]

    /// Targets created, over the table's life.
    package private(set) var createdCount = 0
    /// Targets released, over the table's life.
    package private(set) var releasedCount = 0
    /// Draws recorded by ``didDraw(_:)``, over the table's life.
    package private(set) var drawnCount = 0
    /// Targets alive now.
    package var liveCount: Int { entries.count }

    /// An empty table.
    public init() {}

    /// Releases unreferenced entries, creates or replaces requested ones, and
    /// returns what to draw, in request order — see the type's doc.
    public mutating func update(references: [SurfaceTarget], requests: [SurfaceDrawRequest],
                                create: (SurfaceTarget) -> Handle?, release: (Handle) -> Void)
        -> [(request: SurfaceDrawRequest, handle: Handle, isNew: Bool)] {
        var requested = Set<SurfaceID>()
        for request in requests {
            precondition(requested.insert(request.target.id).inserted,
                         "SurfaceTargetTable: two draw requests for surface \(request.target.id.rawValue) "
                         + "in one frame — one element, one paint (MV-E, MV-L)")
        }
        let referenced = Set(references.map(\.id)).union(requested)
        for (id, entry) in entries where !referenced.contains(id) {
            release(entry.handle)
            releasedCount += 1
            entries[id] = nil
        }

        var toDraw: [(request: SurfaceDrawRequest, handle: Handle, isNew: Bool)] = []
        for request in requests {
            let target = request.target
            var isNew = false
            if let entry = entries[target.id], entry.width != target.width || entry.height != target.height {
                release(entry.handle)
                releasedCount += 1
                entries[target.id] = nil
            }
            if entries[target.id] == nil {
                guard let handle = create(target) else { continue }
                createdCount += 1
                entries[target.id] = Entry(handle: handle, width: target.width, height: target.height,
                                           lastDrawn: nil)
                isNew = true
            }
            guard let entry = entries[target.id] else { continue }
            let draws: Bool
            if isNew || request.policy == .continuous {
                draws = true
            } else if let last = entry.lastDrawn {
                draws = last.value != request.value || last.scale != request.scaleFactor
            } else {
                draws = true
            }
            if draws { toDraw.append((request, entry.handle, isNew)) }
        }
        return toDraw
    }

    /// Records that `request` was drawn: its `value:` and scale are what the
    /// next `.onDemand` frame compares against.
    public mutating func didDraw(_ request: SurfaceDrawRequest) {
        guard entries[request.target.id] != nil else { return }
        entries[request.target.id]?.lastDrawn = (request.value, request.scaleFactor)
        drawnCount += 1
    }

    /// The live handle for `id`, `nil` when it has none — what a renderer binds
    /// for a surface run.
    public func handle(for id: SurfaceID) -> Handle? { entries[id]?.handle }

    /// Every live handle — what a renderer releases when it goes away.
    public var handles: [Handle] { entries.values.map(\.handle) }
}

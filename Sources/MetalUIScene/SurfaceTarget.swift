/// A window-minted name for one app-owned GPU surface's render target
/// (MetalView, ruling `MV-C`). Opaque: no Metal, SDL or closure type enters
/// the scene (`PS-A`); each renderer resolves a `SurfaceID` to its own texture
/// through its `SurfaceTargetTable` (`MV-E`). Minted by `MetalUI`'s
/// `SurfaceRegistry`, monotonically, never reused within a window.
public struct SurfaceID: Hashable, Sendable {
    /// The window-local number.
    public let rawValue: UInt64
    /// A surface id of `rawValue`.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// One surface's render target as the scene carries it (ruling `MV-C`): its
/// id and its size in **device pixels** — the element's laid-out bounds × the
/// frame's scale, each side rounded and clamped to 8192 (`MV-E` item 2).
/// `Scene.surfaces`' quads index `Scene.surfaceTargets` through their
/// `texture` field, as an image quad indexes `Scene.textures`.
public struct SurfaceTarget: Hashable, Sendable {
    /// The surface this target belongs to.
    public let id: SurfaceID
    /// The width in device pixels, > 0.
    public let width: Int
    /// The height in device pixels, > 0.
    public let height: Int

    /// A zero or negative side traps: a renderer allocates exactly this many
    /// texels, and `Frame` emits nothing for a surface with a zero side
    /// (`MV-G` item 4).
    public init(id: SurfaceID, width: Int, height: Int) {
        precondition(width > 0 && height > 0,
                     "SurfaceTarget: \(width)×\(height) has a zero side (MV-C)")
        self.id = id
        self.width = width
        self.height = height
    }
}

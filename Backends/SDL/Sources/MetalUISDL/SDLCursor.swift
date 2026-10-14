// Compiled only under the `SDL` trait (ruling PX-H item 2).
#if SDL
import MetalUIPlatform
import MetalUIScene
import SDLBridge

/// The bounded cursor table (rulings `IC-E` 3, `IC-O`): at most `capacity` cursors, least recently
/// used out, **pure Swift over injected `create`/`destroy`** so its pins run on every video driver
/// (the offscreen one may create no cursor) — the shape of `SurfaceTargetTable`.
///
/// A cursor SDL currently shows is never destroyed on eviction (destroying it makes SDL fall back):
/// it is *parked* and destroyed by the next ``sweepParked(current:)`` that no longer shows it.
/// A refused creation (`create` returns `nil`) is not stored, so it is attempted again.
struct SDLImageCursorTable<Key: Hashable, Handle: Equatable> {
    let capacity: Int
    private let create: (Key) -> Handle?
    private let destroy: (Handle) -> Void
    /// Least recently used first.
    private var entries: [(key: Key, handle: Handle)] = []
    private var parked: [Handle] = []

    init(capacity: Int, create: @escaping (Key) -> Handle?, destroy: @escaping (Handle) -> Void) {
        self.capacity = capacity
        self.create = create
        self.destroy = destroy
    }

    /// How many cursors are held (parked ones not counted).
    var count: Int { entries.count }
    /// How many evicted cursors wait because SDL shows them.
    var parkedCount: Int { parked.count }

    /// The cursor for `key`: the held one (now most recently used), else a new one — evicting the
    /// least recently used past `capacity`, parking it when it is `current`. `nil` when `create`
    /// refuses. Also destroys parked cursors that are no longer `current`.
    mutating func handle(for key: Key, current: Handle?) -> Handle? {
        defer { sweepParked(current: current) }
        if let index = entries.firstIndex(where: { $0.key == key }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.handle
        }
        guard let handle = create(key) else { return nil }
        entries.append((key, handle))
        while entries.count > capacity {
            let victim = entries.removeFirst()
            if victim.handle == current { parked.append(victim.handle) } else { destroy(victim.handle) }
        }
        return handle
    }

    /// Destroys every parked cursor that `current` (what SDL shows now) is not.
    mutating func sweepParked(current: Handle?) {
        var kept: [Handle] = []
        for handle in parked {
            if handle == current { kept.append(handle) } else { destroy(handle) }
        }
        parked = kept
    }

    /// Destroys every cursor, parked ones included.
    mutating func removeAll() {
        for entry in entries { destroy(entry.handle) }
        for handle in parked { destroy(handle) }
        entries = []
        parked = []
    }
}

/// An image cursor's conversion to SDL (rulings `IC-E`, `AI-F`).
enum SDLCursorImage {
    /// A colour cursor for `image`, or `nil` when SDL cannot make one (the recorder counts the
    /// attempt). Pixels are straight alpha through `SDLIcon.straightRGBA` (`AI-F`). **An integer
    /// scale of 2 or more** makes the primary surface the point-size image (the bitmap
    /// box-downsampled by the scale) and adds the bitmap as an alternate, which SDL picks by display
    /// scale (SDL3 cursors are in 1x pixels); any other scale uses the bitmap as the one surface. The
    /// hot spot is in the primary's pixels, rounded and clamped onto it.
    static func make(_ image: PlatformCursorImage) -> UnsafeMutableRawPointer? {
        let texture = image.texture
        let factor = image.scale >= 2 && image.scale == image.scale.rounded() ? Int(image.scale) : 1
        let primaryWidth: Int, primaryHeight: Int
        let primaryBytes: [UInt8]
        let pixelsPerPoint: Float
        if factor > 1 {
            (primaryWidth, primaryHeight, primaryBytes) = downsampled(texture, by: factor)
            pixelsPerPoint = 1
        } else {
            primaryWidth = texture.width; primaryHeight = texture.height
            primaryBytes = SDLIcon.straightRGBA(texture)
            pixelsPerPoint = image.scale
        }
        guard let surface = makeSurface(width: primaryWidth, height: primaryHeight, bytes: primaryBytes) else {
            return nil
        }
        defer { mui_surface_destroy(surface) }   // the cursor copies it
        if factor > 1, let alternate = makeSurface(width: texture.width, height: texture.height,
                                               bytes: SDLIcon.straightRGBA(texture)) {
            _ = mui_icon_surface_add_alternate(surface, alternate)
            mui_surface_destroy(alternate)
        }
        let hotX = clamp(Int((image.hotSpotX * pixelsPerPoint).rounded()), primaryWidth)
        let hotY = clamp(Int((image.hotSpotY * pixelsPerPoint).rounded()), primaryHeight)
        return mui_cursor_create(surface, Int32(hotX), Int32(hotY))
    }

    private static func clamp(_ value: Int, _ extent: Int) -> Int { min(max(value, 0), extent - 1) }

    private static func makeSurface(width: Int, height: Int, bytes: [UInt8]) -> UnsafeMutableRawPointer? {
        bytes.withUnsafeBufferPointer { mui_icon_surface_create(Int32(width), Int32(height), $0.baseAddress) }
    }

    /// `texture` averaged over `factor` x `factor` blocks in premultiplied space (so a transparent
    /// texel adds no colour), then un-premultiplied; a block past the edge averages the texels it
    /// has. The result is `max(1, width / factor)` wide.
    static func downsampled(_ texture: ImageTexture, by factor: Int) -> (Int, Int, [UInt8]) {
        let width = max(1, texture.width / factor), height = max(1, texture.height / factor)
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var sums = [Int](repeating: 0, count: 4)
                var n = 0
                for dy in 0..<factor {
                    for dx in 0..<factor {
                        let sx = x * factor + dx, sy = y * factor + dy
                        guard sx < texture.width, sy < texture.height else { continue }
                        let i = (sy * texture.width + sx) * 4
                        for c in 0..<4 { sums[c] += Int(texture.pixels[i + c]) }
                        n += 1
                    }
                }
                let o = (y * width + x) * 4
                for c in 0..<4 { out[o + c] = UInt8((sums[c] + n / 2) / max(n, 1)) }
            }
        }
        return (width, height, SDLIcon.straightRGBA(premultiplied: out))
    }
}
#endif

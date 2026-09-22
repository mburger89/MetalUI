// A recorded frame: everything a backend needs to draw a finalized MetalUI
// Scene, plus the production Metal renderer's pixels for that frame.
// Standard library only — no Foundation, Metal, CoreText or MetalUI — so the
// replay side builds wherever SDL3 does.
//
// Layout (little-endian, no padding):
//   "MUIRPLY\0"  u32 version
//   u32 width, height, rectStride, glyphStride
//   u32 rectByteCount,  rect bytes
//   u32 glyphByteCount, glyph bytes
//   u32 runCount, runCount × (u32 kind, start, count)
//   u32 atlasWidth, atlasHeight, atlasWidth × atlasHeight R8 bytes
//   16 × f32 projection (column-major)
//   width × height × 4 BGRA8 reference bytes

public struct FixtureRun: Equatable, Sendable {
    public enum Kind: UInt32, Sendable { case rect = 0, glyph = 1 }
    public var kind: Kind
    public var start: UInt32
    public var count: UInt32
    public init(kind: Kind, start: UInt32, count: UInt32) {
        self.kind = kind; self.start = start; self.count = count
    }
}

public struct ReplayFixture: Equatable, Sendable {
    public static let version: UInt32 = 1
    /// The scalar-packed MetalUI primitive ABI the portable shaders expect
    /// (`MemoryLayout<MUIRect>.stride`, `MemoryLayout<MUIGlyph>.stride`).
    public static let rectStride: UInt32 = 120
    public static let glyphStride: UInt32 = 88
    public static let maxDimension: UInt32 = 4096

    public var width: UInt32
    public var height: UInt32
    public var rects: [UInt8]
    public var glyphs: [UInt8]
    public var runs: [FixtureRun]
    public var atlasWidth: UInt32
    public var atlasHeight: UInt32
    public var atlas: [UInt8]
    public var projection: [Float]
    public var reference: [UInt8]

    public var rectCount: Int { rects.count / Int(Self.rectStride) }
    public var glyphCount: Int { glyphs.count / Int(Self.glyphStride) }

    public init(width: UInt32, height: UInt32, rects: [UInt8], glyphs: [UInt8], runs: [FixtureRun],
                atlasWidth: UInt32, atlasHeight: UInt32, atlas: [UInt8],
                projection: [Float], reference: [UInt8]) throws(FixtureError) {
        self.width = width; self.height = height
        self.rects = rects; self.glyphs = glyphs; self.runs = runs
        self.atlasWidth = atlasWidth; self.atlasHeight = atlasHeight; self.atlas = atlas
        self.projection = projection; self.reference = reference
        try validate()
    }

    /// Everything the C bridge trusts, checked once here: it indexes the
    /// primitive buffers with these runs and copies these exact byte counts.
    public func validate() throws(FixtureError) {
        func dimension(_ value: UInt32, _ name: String) throws(FixtureError) {
            guard value > 0, value <= Self.maxDimension else { throw .invalid("\(name) \(value) outside 1...\(Self.maxDimension)") }
        }
        try dimension(width, "width"); try dimension(height, "height")
        try dimension(atlasWidth, "atlas width"); try dimension(atlasHeight, "atlas height")
        guard rects.count % Int(Self.rectStride) == 0 else { throw .invalid("rect bytes \(rects.count) not a multiple of \(Self.rectStride)") }
        guard glyphs.count % Int(Self.glyphStride) == 0 else { throw .invalid("glyph bytes \(glyphs.count) not a multiple of \(Self.glyphStride)") }
        guard atlas.count == Int(atlasWidth) * Int(atlasHeight) else { throw .invalid("atlas bytes \(atlas.count) ≠ \(atlasWidth)×\(atlasHeight)") }
        guard projection.count == 16, projection.allSatisfy(\.isFinite) else { throw .invalid("projection must be 16 finite floats") }
        guard reference.count == Int(width) * Int(height) * 4 else { throw .invalid("reference bytes \(reference.count) ≠ \(width)×\(height)×4") }
        for (index, run) in runs.enumerated() {
            let records = run.kind == .rect ? rectCount : glyphCount
            guard run.count > 0, UInt64(run.start) + UInt64(run.count) <= UInt64(records) else {
                throw .invalid("run \(index) \(run.kind) \(run.start)+\(run.count) exceeds \(records) records")
            }
        }
    }

    /// The same frame with painter order broken: every rect run before every
    /// glyph run. A comparison that cannot see this is a broken instrument.
    public var orderMutatedRuns: [FixtureRun] {
        runs.filter { $0.kind == .rect } + runs.filter { $0.kind == .glyph }
    }
}

public enum FixtureError: Error, Equatable, CustomStringConvertible {
    case truncated(at: Int, needed: Int)
    case badMagic
    case unsupportedVersion(UInt32)
    case strideMismatch(rect: UInt32, glyph: UInt32)
    case badRunKind(UInt32)
    case trailingBytes(Int)
    case invalid(String)

    public var description: String {
        switch self {
        case let .truncated(at, needed): "fixture truncated: need \(needed) bytes at offset \(at)"
        case .badMagic: "not a MetalUI replay fixture"
        case let .unsupportedVersion(v): "fixture version \(v), reader supports \(ReplayFixture.version)"
        case let .strideMismatch(r, g): "primitive ABI changed: rect \(r)/glyph \(g), shaders expect \(ReplayFixture.rectStride)/\(ReplayFixture.glyphStride)"
        case let .badRunKind(k): "unknown run kind \(k)"
        case let .trailingBytes(n): "\(n) trailing bytes after fixture"
        case let .invalid(message): "invalid fixture: \(message)"
        }
    }
}

private let magic: [UInt8] = Array("MUIRPLY".utf8) + [0]

extension ReplayFixture {
    public func encoded() -> [UInt8] {
        var out = magic
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out += $0 } }
        func bytes(_ b: [UInt8]) { u32(UInt32(b.count)); out += b }
        u32(Self.version)
        u32(width); u32(height); u32(Self.rectStride); u32(Self.glyphStride)
        bytes(rects); bytes(glyphs)
        u32(UInt32(runs.count))
        for run in runs { u32(run.kind.rawValue); u32(run.start); u32(run.count) }
        u32(atlasWidth); u32(atlasHeight); out += atlas
        for value in projection { u32(value.bitPattern) }
        out += reference
        return out
    }

    public init(decoding data: [UInt8]) throws(FixtureError) {
        var offset = 0
        func take(_ n: Int) throws(FixtureError) -> ArraySlice<UInt8> {
            guard n >= 0, n <= data.count - offset else { throw .truncated(at: offset, needed: n) }
            defer { offset += n }
            return data[offset..<offset + n]
        }
        func u32() throws(FixtureError) -> UInt32 {
            try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }
        func bytes(_ n: Int) throws(FixtureError) -> [UInt8] { Array(try take(n)) }

        guard Array(try take(magic.count)) == magic else { throw .badMagic }
        let version = try u32()
        guard version == Self.version else { throw .unsupportedVersion(version) }
        let width = try u32(), height = try u32()
        let rectStride = try u32(), glyphStride = try u32()
        guard rectStride == Self.rectStride, glyphStride == Self.glyphStride else {
            throw .strideMismatch(rect: rectStride, glyph: glyphStride)
        }
        let rects = try bytes(Int(try u32()))
        let glyphs = try bytes(Int(try u32()))
        let runCount = Int(try u32())
        var runs: [FixtureRun] = []
        for _ in 0..<runCount {
            let raw = try u32()
            guard let kind = FixtureRun.Kind(rawValue: raw) else { throw .badRunKind(raw) }
            runs.append(FixtureRun(kind: kind, start: try u32(), count: try u32()))
        }
        let atlasWidth = try u32(), atlasHeight = try u32()
        // Check dimensions before multiplying them into a read length.
        guard atlasWidth <= Self.maxDimension, atlasHeight <= Self.maxDimension,
              width <= Self.maxDimension, height <= Self.maxDimension else {
            throw .invalid("dimension exceeds \(Self.maxDimension)")
        }
        let atlas = try bytes(Int(atlasWidth) * Int(atlasHeight))
        var projection: [Float] = []
        for _ in 0..<16 { projection.append(Float(bitPattern: try u32())) }
        let reference = try bytes(Int(width) * Int(height) * 4)
        guard offset == data.count else { throw .trailingBytes(data.count - offset) }
        try self.init(width: width, height: height, rects: rects, glyphs: glyphs, runs: runs,
                      atlasWidth: atlasWidth, atlasHeight: atlasHeight, atlas: atlas,
                      projection: projection, reference: reference)
    }
}

/// Per-pixel BGRA comparison: pixels with a channel differing by more than
/// `threshold` (default: any difference), and the largest channel difference.
public func pixelDifference(_ a: [UInt8], _ b: [UInt8], above threshold: Int = 0) -> (pixels: Int, maxDelta: Int) {
    precondition(a.count == b.count && a.count % 4 == 0, "images differ in size")
    var pixels = 0, maxDelta = 0
    for i in stride(from: 0, to: a.count, by: 4) {
        var changed = false
        for c in 0..<4 {
            let delta = abs(Int(a[i + c]) - Int(b[i + c]))
            changed = changed || delta > threshold
            maxDelta = max(maxDelta, delta)
        }
        if changed { pixels += 1 }
    }
    return (pixels, maxDelta)
}

// MARK: - Parity

/// Parity is judged in two regions. Outside glyph quads a backend may differ
/// by one UNORM step (rounding). Inside them the atlas is sampled wherever
/// the projection puts a pixel centre; off texel centres, the sampled value
/// depends on the implementation's texture-coordinate and filter-weight
/// precision. Vulkan requires only 4 sub-texel bits, so a weight may be off
/// by 1/32 and a full-contrast texel pair then moves the result by ~8 steps.
/// Measured on Mesa llvmpipe vs Apple M1 Max: 3 (README, "Linux").
public enum ParityTolerance {
    public static let outsideGlyphs = 1
    public static let insideGlyphs = 8
}

public struct Parity: Equatable, Sendable {
    public var outside: (pixels: Int, maxDelta: Int)
    public var inside: (pixels: Int, maxDelta: Int)
    public var passes: Bool {
        outside.maxDelta <= ParityTolerance.outsideGlyphs && inside.maxDelta <= ParityTolerance.insideGlyphs
    }
    public static func == (a: Parity, b: Parity) -> Bool {
        a.outside == b.outside && a.inside == b.inside
    }
}

extension ReplayFixture {
    /// Glyph bounds (the first four floats of each 88-byte record), as
    /// recorded, before the projection.
    public var glyphBounds: [(x: Float, y: Float, width: Float, height: Float)] {
        (0..<glyphCount).map { index in
            let base = index * Int(Self.glyphStride)
            func float(_ k: Int) -> Float {
                let o = base + k * 4
                return Float(bitPattern: UInt32(glyphs[o]) | UInt32(glyphs[o + 1]) << 8
                                        | UInt32(glyphs[o + 2]) << 16 | UInt32(glyphs[o + 3]) << 24)
            }
            return (float(0), float(1), float(2), float(3))
        }
    }

    /// Where a pre-projection pixel position lands on the target, by the
    /// shaders' own mapping: pixels → NDC → `projection` → pixels.
    public func project(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
        let m = projection, w = Float(width), h = Float(height)
        let nx = x / w * 2 - 1, ny = 1 - y / h * 2
        let cx = m[0] * nx + m[4] * ny + m[12]
        let cy = m[1] * nx + m[5] * ny + m[13]
        let cw = m[3] * nx + m[7] * ny + m[15]
        return ((cx / cw + 1) / 2 * w, (1 - cy / cw) / 2 * h)
    }

    /// Pixels a glyph quad may touch after projection, grown by one pixel
    /// for anti-aliased coverage at its edge.
    public func glyphMask() -> [Bool] {
        let w = Int(width), h = Int(height)
        var mask = [Bool](repeating: false, count: w * h)
        // Snap to 1/256 px, a rasterizer's sub-pixel grid, so float round-off
        // in the NDC round trip (2 -> 1.9999998) cannot grow the mask a row.
        func snapped(_ p: (x: Float, y: Float)) -> (x: Float, y: Float) {
            ((p.x * 256).rounded() / 256, (p.y * 256).rounded() / 256)
        }
        for b in glyphBounds {
            let corners = [project(b.x, b.y), project(b.x + b.width, b.y),
                           project(b.x, b.y + b.height), project(b.x + b.width, b.y + b.height)].map(snapped)
            let x0 = max(0, Int((corners.map(\.x).min()! - 1).rounded(.down)))
            let x1 = min(w - 1, Int((corners.map(\.x).max()! + 1).rounded(.up)))
            let y0 = max(0, Int((corners.map(\.y).min()! - 1).rounded(.down)))
            let y1 = min(h - 1, Int((corners.map(\.y).max()! + 1).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { mask[y * w + x] = true } }
        }
        return mask
    }

    public func parity(of pixels: [UInt8]) -> Parity {
        precondition(pixels.count == reference.count, "output size differs from reference")
        let mask = glyphMask()
        var inside = (pixels: 0, maxDelta: 0), outside = (pixels: 0, maxDelta: 0)
        for p in 0..<mask.count {
            var delta = 0
            for c in 0..<4 { delta = max(delta, abs(Int(reference[p * 4 + c]) - Int(pixels[p * 4 + c]))) }
            guard delta > 0 else { continue }
            if mask[p] { inside.pixels += 1; inside.maxDelta = max(inside.maxDelta, delta) }
            else { outside.pixels += 1; outside.maxDelta = max(outside.maxDelta, delta) }
        }
        return Parity(outside: outside, inside: inside)
    }
}

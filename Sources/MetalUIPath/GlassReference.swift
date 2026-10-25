/// Liquid Glass's per-pixel arithmetic in `Float`, on the CPU (rulings `LG-D`,
/// `LG-G`, `TE-AD`): what `backdrop_fragment`'s glass branch in `shaders.metal`
/// and `replay.hlsl` compute, so a readback has a ground truth on every
/// platform. **Imports nothing** (`GX-B`): `+ − × ÷ sqrt`, `min`, `max` only.
///
/// A glass is a `.backdrop` record whose `glassFlags` bit 0 is set (`LG-B`).
/// Per pixel, in order (every distance in the record's LOCAL device pixels):
///
/// 1. the blob's signed distance `d` (`sdf`): one member reads the record's
///    own bounds, corner radii and shape exactly as the rect shader does (so a
///    glass edge equals a material's); two to four members read the fold
///    `smin(smin(m0, m1, K), m2, K) …` in tree order, `K = blendK`;
/// 2. coverage `c = saturate(½ − d·s) · clip`, `s` the transform's pixel scale;
/// 3. the blurred read `B`; inside the lens band (`t = saturate(−d / band) < 1`,
///    `lensRim` set) the sharp frame read `S` at `p − n·depth·(1−t)²` mixed over
///    it with weight `(1−t)²`, `n` the outward unit gradient of `d`;
/// 4. `base = T + (1 − T.a)·B'`, then the press lift (white at
///    `press · pressLift`), then the rim (white at
///    `rimStrength · (1−t)⁴ · (0.65 + 0.35·dot(n, L))`, `L` toward the upper
///    left), each source-over, the last two only with `lensRim` set;
/// 5. `c · opacity · base`, premultiplied.
package enum GlassReference {
    /// One member's outline, normalised to the record's own `bounds`
    /// (origin and size as fractions of it, radii as a fraction of its shorter
    /// side, `LG-B`).
    package struct Member: Equatable {
        package var x: Float, y: Float, width: Float, height: Float
        package var topLeft: Float, topRight: Float, bottomRight: Float, bottomLeft: Float
        package init(x: Float, y: Float, width: Float, height: Float,
                     topLeft: Float = 0, topRight: Float = 0, bottomRight: Float = 0, bottomLeft: Float = 0) {
            self.x = x; self.y = y; self.width = width; self.height = height
            self.topLeft = topLeft; self.topRight = topRight
            self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
        }
    }

    /// The record's fields the arithmetic reads (a mirror of `MUIBackdrop`;
    /// `MetalUIPath` cannot import the C module).
    package struct Record {
        package var originX: Float, originY: Float, width: Float, height: Float
        package var topLeft: Float = 0, topRight: Float = 0, bottomRight: Float = 0, bottomLeft: Float = 0
        /// `shape & 0xFF == 1`: the one-member shape is the inscribed ellipse.
        package var isEllipse = false
        /// Straight-alpha RGBA of the tint `T`.
        package var tint: SIMD4<Float> = .zero
        package var opacity: Float = 1
        package var flags: UInt32 = glassBit
        package var lensDepth: Float = 0
        package var band: Float = 0
        package var rimStrength: Float = 0
        package var blendK: Float = 0
        package var press: Float = 0
        package var pressLift: Float = 0
        /// Read only when the member count is two or more.
        package var members: [Member] = []

        package init(originX: Float, originY: Float, width: Float, height: Float) {
            self.originX = originX; self.originY = originY; self.width = width; self.height = height
        }

        /// The member count the flags carry, clamped to `1…4`.
        package var memberCount: Int { GlassReference.memberCount(flags) }
    }

    package static let glassBit: UInt32 = 1
    package static let lensRimBit: UInt32 = 2
    package static let darkBit: UInt32 = 4
    package static let maxMembers = 4
    /// The rim's light direction (outward normals toward it are brightest):
    /// the unit vector toward the upper left, y down.
    package static let lightX: Float = -0.70710678
    package static let lightY: Float = -0.70710678

    /// The flags word: glass, optional lens and rim, the scheme the record was
    /// resolved for, a member count of `1…4` (bits 3…5) and which members are
    /// ellipses (bits 6…9).
    package static func flags(lensRim: Bool, dark: Bool, memberCount: Int, ellipses: [Bool] = []) -> UInt32 {
        var word = glassBit
        if lensRim { word |= lensRimBit }
        if dark { word |= darkBit }
        word |= UInt32(min(max(memberCount, 1), 7)) << 3
        for (k, isEllipse) in ellipses.prefix(maxMembers).enumerated() where isEllipse { word |= 1 << UInt32(6 + k) }
        return word
    }

    /// Bits 3…5 of `flags`, read as `1…4` (zero means one).
    package static func memberCount(_ flags: UInt32) -> Int {
        min(max(Int((flags >> 3) & 7), 1), maxMembers)
    }

    /// The greedy chunks of at most four a container's members form, in tree
    /// order and never merging across (`LG-G`): `5 → [0..<4, 4..<5]`.
    package static func chunks(ofMemberCount count: Int, chunkSize: Int = maxMembers) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = 0
        while start < count {
            out.append(start..<min(start + chunkSize, count))
            start += chunkSize
        }
        return out
    }

    // MARK: Signed distances

    package static func rectSDF(_ px: Float, _ py: Float, halfWidth: Float, halfHeight: Float, radius: Float) -> Float {
        let dx = abs(px) - halfWidth + radius, dy = abs(py) - halfHeight + radius
        let ox = max(dx, 0), oy = max(dy, 0)
        return (ox * ox + oy * oy).squareRoot() + min(max(dx, dy), 0) - radius
    }

    /// `ellipse_sdf` of `shaders.metal`, statement for statement.
    package static func ellipseSDF(_ px: Float, _ py: Float, halfWidth hx: Float, halfHeight hy: Float) -> Float {
        if min(hx, hy) <= 0 { return 1.0e9 }
        if abs(hx - hy) <= 1.0e-4 { return (px * px + py * py).squareRoot() - hx }
        let qx = abs(px), qy = abs(py)
        var tx: Float = 0.70710678, ty: Float = 0.70710678
        let c = hx * hx - hy * hy
        for _ in 0..<3 {
            let ex = c * tx * tx * tx / hx, ey = -c * ty * ty * ty / hy
            let rx = hx * tx - ex, ry = hy * ty - ey
            let vx = qx - ex, vy = qy - ey
            let rl = (rx * rx + ry * ry).squareRoot()
            let vl = max((vx * vx + vy * vy).squareRoot(), 1.0e-6)
            tx = min(max((vx * (rl / vl) + ex) / hx, 0), 1)
            ty = min(max((vy * (rl / vl) + ey) / hy, 0), 1)
            let tl = max((tx * tx + ty * ty).squareRoot(), 1.0e-6)
            tx /= tl; ty /= tl
        }
        let dx = qx - hx * tx, dy = qy - hy * ty
        let d = (dx * dx + dy * dy).squareRoot()
        let nx = qx / hx, ny = qy / hy
        return nx * nx + ny * ny < 1 ? -d : d
    }

    /// The polynomial smooth minimum `min(a, b) − h²·k/4`,
    /// `h = max(k − |a − b|, 0) / k` (`LG-G`); plain `min` for `k ≤ 0`.
    package static func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        guard k > 0 else { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }

    private static func cornerRadius(_ rx: Float, _ ry: Float, tl: Float, tr: Float, br: Float, bl: Float) -> Float {
        if rx < 0 { return ry < 0 ? tl : bl }
        return ry < 0 ? tr : br
    }

    private static func memberSDF(_ record: Record, _ k: Int, _ x: Float, _ y: Float) -> Float {
        let m = record.members[k]
        let shorter = min(record.width, record.height)
        let w = m.width * record.width, h = m.height * record.height
        let cx = record.originX + m.x * record.width + w * 0.5
        let cy = record.originY + m.y * record.height + h * 0.5
        let rx = x - cx, ry = y - cy
        if (record.flags >> UInt32(6 + k)) & 1 != 0 {
            return ellipseSDF(rx, ry, halfWidth: w * 0.5, halfHeight: h * 0.5)
        }
        let r = cornerRadius(rx, ry, tl: m.topLeft * shorter, tr: m.topRight * shorter,
                             br: m.bottomRight * shorter, bl: m.bottomLeft * shorter)
        return rectSDF(rx, ry, halfWidth: w * 0.5, halfHeight: h * 0.5, radius: r)
    }

    /// The blob's signed distance at local position `(x, y)`: negative inside.
    package static func sdf(_ record: Record, _ x: Float, _ y: Float) -> Float {
        let count = record.memberCount
        if count <= 1 || record.members.count < count {
            let hw = record.width * 0.5, hh = record.height * 0.5
            let rx = x - (record.originX + hw), ry = y - (record.originY + hh)
            if record.isEllipse { return ellipseSDF(rx, ry, halfWidth: hw, halfHeight: hh) }
            let r = cornerRadius(rx, ry, tl: record.topLeft, tr: record.topRight,
                                 br: record.bottomRight, bl: record.bottomLeft)
            return rectSDF(rx, ry, halfWidth: hw, halfHeight: hh, radius: r)
        }
        var d = memberSDF(record, 0, x, y)
        for k in 1..<count { d = smin(d, memberSDF(record, k, x, y), record.blendK) }
        return d
    }

    /// The outward unit normal: the central difference of `sdf` over one
    /// local pixel, zero where the gradient vanishes.
    package static func normal(_ record: Record, _ x: Float, _ y: Float) -> (x: Float, y: Float) {
        let gx = sdf(record, x + 1, y) - sdf(record, x - 1, y)
        let gy = sdf(record, x, y + 1) - sdf(record, x, y - 1)
        let l = max((gx * gx + gy * gy).squareRoot(), 1.0e-6)
        return (gx / l, gy / l)
    }

    /// `t`: the distance inside the edge as a fraction of the band, `1` at
    /// and beyond its depth (and for a zero band).
    package static func edgeFraction(_ record: Record, _ x: Float, _ y: Float) -> Float {
        guard record.band > 0 else { return 1 }
        return min(max(-sdf(record, x, y) / record.band, 0), 1)
    }

    /// The rim's alpha at `(x, y)`, before `lensRim` gating.
    package static func rimAlpha(_ record: Record, _ x: Float, _ y: Float) -> Float {
        let t = edgeFraction(record, x, y)
        guard t < 1 else { return 0 }
        let n = normal(record, x, y)
        let u = 1 - t
        let u2 = u * u
        return record.rimStrength * (u2 * u2) * (0.65 + 0.35 * (n.x * lightX + n.y * lightY))
    }

    /// The premultiplied tint `T`.
    package static func premultipliedTint(_ record: Record) -> SIMD4<Float> {
        SIMD4(record.tint.x * record.tint.w, record.tint.y * record.tint.w, record.tint.z * record.tint.w, record.tint.w)
    }

    /// One pixel: premultiplied RGBA. `x, y` is the local position, `blurred`
    /// the blurred backdrop `B` there, `sharp` the frame read at a SCREEN
    /// position (`screenX, screenY` is this pixel's; the lens offset is mapped
    /// by `linear = (a, b, c, d)`), `clip` the content mask's coverage and
    /// `scale` the transform's pixel scale (all identity for an untransformed
    /// record).
    package static func shade(_ record: Record, x: Float, y: Float,
                              blurred: SIMD4<Float>,
                              sharp: (_ x: Float, _ y: Float) -> SIMD4<Float>,
                              screenX: Float? = nil, screenY: Float? = nil,
                              linear: (a: Float, b: Float, c: Float, d: Float) = (1, 0, 0, 1),
                              scale: Float = 1, clip: Float = 1) -> SIMD4<Float> {
        let d = sdf(record, x, y)
        let c = min(max(0.5 - d * scale, 0), 1) * clip
        var backdrop = blurred
        let lens = record.flags & lensRimBit != 0
        let t = record.band > 0 ? min(max(-d / record.band, 0), 1) : 1
        var n: (x: Float, y: Float) = (0, 0)
        if lens && t < 1 {
            n = normal(record, x, y)
            let u = 1 - t
            let weight = u * u
            let depth = record.lensDepth * weight
            let dx = n.x * depth, dy = n.y * depth
            let sx = (screenX ?? x) - (linear.a * dx + linear.c * dy)
            let sy = (screenY ?? y) - (linear.b * dx + linear.d * dy)
            backdrop = blurred + (sharp(sx, sy) - blurred) * weight
        }
        let tint = premultipliedTint(record)
        var base = tint + backdrop * (1 - tint.w)
        let lift = record.press * record.pressLift
        base = SIMD4(repeating: lift) + base * (1 - lift)
        if lens && t < 1 {
            let u = 1 - t
            let u2 = u * u
            let rim = record.rimStrength * (u2 * u2) * (0.65 + 0.35 * (n.x * lightX + n.y * lightY))
            base = SIMD4(repeating: rim) + base * (1 - rim)
        }
        return base * (c * record.opacity)
    }
}

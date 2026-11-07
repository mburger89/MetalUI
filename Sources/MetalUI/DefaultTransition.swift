import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIShaderTypes

// R4-3 PR B2 (`XF-H`…, record 206): the default fade. SwiftUI fades every member of an unannotated `if`, `if`/`else`
// branch and `ForEach` element in and out, at the transaction's animation (`XF0`, `XF3`, `XF4`, `XF6`). MetalUI notes the
// scene sequence range each such **unit** painted (`Frame.paintConditionalUnit`), slices the previous frame's scene by it when
// the unit is removed (`Scene.primitives(inSequences:)`), and fades the slice as a ghost; an insertion paints under a
// non-capturing `.fade` scope. Nothing captures at rest: a steady frame pays two integer reads and one array append a unit.

/// A conditional's layout (`XF-H` item 2): the content's layout, if the conditional produced any, and the unit it fades by
/// default, if it is one. What ``OptionalGroup`` hands from its build to its paint, so paint can note the scene range the
/// unit drew.
///
/// MetalUI-only (class `M`): an `ElementGroup`'s layout is an associated type no app reads; the type is public only
/// because `OptionalGroup.GroupLayout` is spelled in a public signature.
public struct ConditionalLayout<Inner> {
    /// The content's layout, `nil` when the conditional produced none (an absent `if`).
    var inner: Inner?
    /// The unit the conditional's content fades as by default (`XF-H`), `nil` when it does not (an `OptionalGroup`
    /// built with `init(_:)` rather than by the builder).
    var unit: GlobalElementID?
}

extension Scene {
    /// `kind`'s primitive `index` as a captured primitive (`XF-H`): what a default ghost replays. The record's own
    /// transform is carried by value; a clip depth is unknown (`innerMask: false`, `outerDepth: 0`), which only the
    /// scope-mapping paths read, and a ghost maps on the CPU with no outer mask.
    @MainActor
    func capturedPrimitive(_ kind: PrimitiveKind, at index: Int) -> CapturedPrimitive? {
        func transform(index t: Int) -> PrimitiveTransform? { capturedTransform(index: t) }
        var primitive: CapturedPrimitive
        switch kind {
        case .rect:
            let r = rects[index]
            primitive = .rect(r, layer: layer(of: .rect, at: index), innerMask: false)
            primitive.transform = transform(index: Int(r.shape >> 8))
        case .glyph:
            let g = glyphs[index]
            primitive = .glyph(g, layer: layer(of: .glyph, at: index), innerMask: false)
            primitive.transform = transform(index: Int(g.transform))
        case .image:
            let i = images[index]
            guard Int(i.texture) < textures.count else { return nil }
            primitive = .image(i, texture: textures[Int(i.texture)], layer: layer(of: .image, at: index), innerMask: false)
            primitive.transform = transform(index: Int(i.filter >> 8))
        case .surface:
            let q = surfaces[index]
            guard Int(q.texture) < surfaceTargets.count else { return nil }
            primitive = .surface(q, target: surfaceTargets[Int(q.texture)], layer: layer(of: .surface, at: index), innerMask: false)
            primitive.transform = transform(index: Int(q.filter >> 8))
        case .backdrop:
            let b = backdrops[index]
            primitive = .backdrop(b, layer: layer(of: .backdrop, at: index), innerMask: false)
            primitive.transform = transform(index: Int(b.shape >> 8))
        case .group:
            return nil   // expanded by `capturedGroup(at:)`, which returns several (`GO-G`)
        }
        return primitive
    }

    /// Transform record `t` (1-based, 0 is none) as a value (`GX-G`).
    @MainActor
    func capturedTransform(index t: Int) -> PrimitiveTransform? {
        guard t > 0, t <= transforms.count else { return nil }
        let record = transforms[t - 1]
        let projective = record.det3 != 0
        let homography = Homography2D(a: Double(record.a), b: Double(record.b), c: Double(record.c), d: Double(record.d),
                                      tx: Double(record.tx), ty: Double(record.ty),
                                      g: projective ? Double(record.g) : 0, h: projective ? Double(record.h) : 0,
                                      i: projective ? Double(record.i) : 1)
        return PrimitiveTransform(homography: homography, outerMask: record.outerMask,
                                  outerMaskRadii: record.outerMaskRadii, outerDepth: 0)
    }

    /// Offscreen group `index`'s content as captured primitives in paint order (`GO-G`), each marked with one fresh
    /// token at the quad's opacity, so a ghost of a removed unit fades the group as one group. A group inside the group
    /// expands in place, its marks inside this one's.
    @MainActor
    func capturedGroup(at index: Int) -> [CapturedPrimitive] {
        let child = groupScenes[index]
        let filter = groupFilters[index]
        if filter.kind != .none {
            // A filtered group (`GF-D`) is one shadow or blur item over its content, so the ghost goes through the
            // same route again (CPU where it can, the GPU where it cannot).
            let quad = groups[index]
            var content: [CapturedPrimitive] = []
            for run in child.drawList {
                for k in run.start..<(run.start + run.count) {
                    if run.kind == .group { content.append(contentsOf: child.capturedGroup(at: k)) }
                    else if let primitive = child.capturedPrimitive(run.kind, at: k) { content.append(primitive) }
                }
            }
            let layer = layer(of: .group, at: index)
            let item: CapturedPrimitive.Kind
            if filter.kind == .shadow {
                let a = filter.tint.w
                let rgba = Rgba(r: a > 0 ? filter.tint.x / a : 0, g: a > 0 ? filter.tint.y / a : 0,
                                b: a > 0 ? filter.tint.z / a : 0, a: a)
                item = .shadow(ShadowPaint(leaf: content, color: rgba.toHsla(), radius: Double(filter.sigma), dx: 0, dy: 0,
                                           local: .identity, contentMask: quad.contentMask,
                                           maskCornerRadii: quad.maskCornerRadii, entryDepth: 0))
            } else {
                item = .blur(BlurPaint(leaf: content, radius: Double(filter.sigma), local: .identity,
                                       contentMask: quad.contentMask, maskCornerRadii: quad.maskCornerRadii,
                                       entryDepth: 0, alpha: quad.opacity))
            }
            var captured = CapturedPrimitive(kind: item, layer: layer, innerMask: false)
            captured.transform = capturedTransform(index: Int(quad.filter >> 8))
            return [captured]
        }
        var mark = GroupMark(token: GroupToken(), alpha: groups[index].opacity)
        if let maskScene = groupMasks[index], let run = maskScene.drawList.first,
           let shape = maskScene.capturedPrimitive(run.kind, at: run.start) {
            // A masked group (`CM-A`): the ghost is masked again, by the primitive the mask scene drew (a path mask reads
            // back as its raster image, which is what it had already become).
            mark = GroupMark(token: GroupToken(), alpha: 1, mask: [shape])
        }
        var out: [CapturedPrimitive] = []
        for run in child.drawList {
            for k in run.start..<(run.start + run.count) {
                if run.kind == .group {
                    for var nested in child.capturedGroup(at: k) { nested.groups.insert(mark, at: 0); out.append(nested) }
                } else if var primitive = child.capturedPrimitive(run.kind, at: k) {
                    primitive.groups = [mark]
                    out.append(primitive)
                }
            }
        }
        return out
    }

    /// The primitives emitted with a sequence in `range`, minus any in `carved`, as captured primitives in emission
    /// order (`XF-H`).
    @MainActor
    func capturedPrimitives(inSequences range: Range<Int>, excluding carved: [Range<Int>])
        -> (primitives: [CapturedPrimitive], sequences: [Int]) {
        var out: [CapturedPrimitive] = [], sequences: [Int] = []
        for (kind, index) in primitives(inSequences: range) {
            let sequence = emissionSequence(of: kind, at: index)
            if carved.contains(where: { $0.contains(sequence) }) { continue }
            if kind == .group {
                for primitive in capturedGroup(at: index) { out.append(primitive); sequences.append(sequence) }
            } else if let primitive = capturedPrimitive(kind, at: index) {
                out.append(primitive)
                sequences.append(sequence)
            }
        }
        return (out, sequences)
    }
}

/// One unit's drawn scene range, in the emission sequence of the frame it was painted in (`XF-H` item 3).
struct UnitRange: Equatable {
    var unit: GlobalElementID
    var start: Int
    var end: Int
}

/// What `Frame.beginConditionalUnit` leaves for `endConditionalUnit`: the sequence the content started at and whether a
/// fade scope was opened around it.
struct ConditionalUnitMark {
    var start = 0
    var fading = false
}

extension Frame {
    /// Opens a conditional's content as the unit `unit` (`XF-H` items 3 and 7): an in-flight default insertion opens its
    /// non-capturing `.fade` scope around the content, and the scene sequence the content starts at is read for the range
    /// `endConditionalUnit` notes. `unit == nil` is the ordinary paint. At rest this is one integer read.
    @inline(__always)
    func beginConditionalUnit(_ unit: GlobalElementID?) -> ConditionalUnitMark {
        guard let unit else { return ConditionalUnitMark() }
        var mark = ConditionalUnitMark()
        let transitions = animationStore.transitions
        if transitions.hasLiveInsertions, let opened = transitions.beginFade(unit, frame: self) {
            paintScopes.append(opened)
            mark.fading = true
        }
        mark.start = scene.nextEmissionSequence
        return mark
    }

    /// Closes the unit `beginConditionalUnit` opened: notes the range the content drew, for a later removal's ghost. At
    /// rest one integer read and one array append.
    @inline(__always)
    func endConditionalUnit(_ unit: GlobalElementID?, _ mark: ConditionalUnitMark) {
        guard let unit else { return }
        let end = scene.nextEmissionSequence
        if mark.fading { paintScopes.removeLast() }
        // A composite scope collects its leaves and re-emits them later: the range would not be contiguous.
        let composite = !paintScopes.isEmpty && compositeScopeOpen
        animationStore.transitions.noteRange(unit, start: mark.start, end: composite ? mark.start : end)
    }

    private var compositeScopeOpen: Bool {
        for scope in paintScopes where scope.kind == .composite { return true }
        return false
    }
}

// Offscreen opacity groups in a recorded frame (ruling GO-F, record 218). A group is a nested body — the records of
// the scene a group quad draws — rendered before the frame's own passes into a target of its box. Imports only
// MetalUIScene, as the fixture does.

import MetalUIScene
import MetalUIShaderTypes

/// The records one scene draws, in the fixture's own byte form (`GO-F`): a group's body, and the shape the flattener
/// reads for the frame's root too. Image records name textures of the fixture's shared list; a group quad (a record in
/// a `.group` run of ``runs``) names its group by index instead.
public struct FixtureBody: Equatable, Sendable {
    public var rects: [UInt8]
    public var glyphs: [UInt8]
    public var images: [UInt8]
    public var transforms: [UInt8]
    public var runs: [FixtureRun]
    public init(rects: [UInt8], glyphs: [UInt8], images: [UInt8], transforms: [UInt8], runs: [FixtureRun]) {
        self.rects = rects; self.glyphs = glyphs; self.images = images; self.transforms = transforms; self.runs = runs
    }
}

/// One offscreen group (`GO-F`): rendered into a target of `width` x `height` whose pixel (0, 0) is the device point
/// (`x`, `y`), then drawn by a group quad of the scene that holds it.
public struct FixtureGroup: Equatable, Sendable {
    public var x: UInt32
    public var y: UInt32
    public var width: UInt32
    public var height: UInt32
    public var body: FixtureBody
    /// The filter the group's target goes through before its quad samples it (version 8, `GF-F`): 0 none, 1 blur, 2 shadow
    /// (`Scene.GroupFilter.Kind`).
    public var filterKind: UInt32
    /// The Gaussian's standard deviation in device pixels of the target; 0 skips the blur passes.
    public var sigma: Float
    /// A shadow's colour, premultiplied (r, g, b, a).
    public var tint: [Float]
    /// The mask the group's target is multiplied by (version 9, `CM-A`, `Scene.groupMasks`): rects, glyphs and images (no
    /// group run; a gradient text's mask is a glyph run, `TG-C`), drawn into a scratch of the group's size under the group's projection. `nil` is no mask.
    public var mask: FixtureBody?
    public init(x: UInt32, y: UInt32, width: UInt32, height: UInt32, body: FixtureBody,
                filterKind: UInt32 = 0, sigma: Float = 0, tint: [Float] = [0, 0, 0, 0], mask: FixtureBody? = nil) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.body = body
        self.filterKind = filterKind; self.sigma = sigma; self.tint = tint; self.mask = mask
    }

    /// What the bridge trusts, checked once (`GO-F`): the body's strides and runs, every image run's texture and every
    /// group quad naming a group **earlier** than this one (post-order), and transforms the body's table holds.
    func validate(index: Int, textureCount: Int, groupCount: Int) throws(FixtureError) {
        let name = "group \(index)"
        try Self.validate(body, name: name, textureCount: textureCount, groupCount: groupCount, filterKind: filterKind,
                          sigma: sigma, tint: tint, width: width, height: height)
        if let mask {
            // A mask draws rects, glyphs and images of the shared texture list and nothing that is itself a group (`CM-A`).
            try Self.validate(mask, name: "\(name) mask", textureCount: textureCount, groupCount: 0, filterKind: 0,
                              sigma: 0, tint: [0, 0, 0, 0], width: width, height: height)
        }
    }

    private static func validate(_ body: FixtureBody, name: String, textureCount: Int, groupCount: Int, filterKind: UInt32,
                                 sigma: Float, tint: [Float], width: UInt32, height: UInt32) throws(FixtureError) {
        guard filterKind <= 2, sigma.isFinite, sigma >= 0, tint.count == 4, tint.allSatisfy({ $0.isFinite }) else {
            throw .invalid("\(name) filter \(filterKind) sigma \(sigma) tint \(tint) is not a filter")
        }
        guard width > 0, height > 0, width <= ReplayFixture.maxDimension, height <= ReplayFixture.maxDimension else {
            throw .invalid("\(name) size \(width)×\(height) outside 1...\(ReplayFixture.maxDimension)")
        }
        guard body.rects.count % Int(ReplayFixture.rectStride) == 0, body.glyphs.count % Int(ReplayFixture.glyphStride) == 0,
              body.images.count % Int(ReplayFixture.imageStride) == 0,
              body.transforms.count % Int(ReplayFixture.transformStride) == 0 else {
            throw .invalid("\(name) record bytes are not whole records")
        }
        let rectCount = body.rects.count / Int(ReplayFixture.rectStride)
        let glyphCount = body.glyphs.count / Int(ReplayFixture.glyphStride)
        let images: [MUIImage] = body.images.withUnsafeBytes { raw in
            (0..<raw.count / Int(ReplayFixture.imageStride)).map {
                raw.loadUnaligned(fromByteOffset: $0 * Int(ReplayFixture.imageStride), as: MUIImage.self)
            }
        }
        let transformCount = body.transforms.count / Int(ReplayFixture.transformStride)
        for (k, run) in body.runs.enumerated() {
            let records: Int
            switch run.kind {
            case .rect: records = rectCount
            case .glyph: records = glyphCount
            case .image, .group: records = images.count
            case .backdrop: throw .invalid("\(name) holds a backdrop run (a group draws its materials flat)")
            }
            guard run.count > 0, UInt64(run.start) + UInt64(run.count) <= UInt64(records) else {
                throw .invalid("\(name) run \(k) \(run.kind) \(run.start)+\(run.count) exceeds \(records) records")
            }
            if run.kind == .image {
                let textures = images[Int(run.start)..<Int(run.start + run.count)].map(\.texture)
                guard Set(textures).count == 1, Int(textures[0]) < textureCount else {
                    throw .invalid("\(name) image run \(k) names textures \(Set(textures)) of \(textureCount)")
                }
            }
            if run.kind == .group {
                guard run.count == 1, Int(images[Int(run.start)].texture) < groupCount else {
                    throw .invalid("\(name) group run \(k) names a group that is not earlier than it")
                }
            }
        }
        // Every transform index a record names exists in the body's own table.
        let rects = body.rects.withUnsafeBytes { raw in
            (0..<rectCount).map { raw.loadUnaligned(fromByteOffset: $0 * Int(ReplayFixture.rectStride), as: MUIRect.self).shape >> 8 }
        }
        let glyphs = body.glyphs.withUnsafeBytes { raw in
            (0..<glyphCount).map { raw.loadUnaligned(fromByteOffset: $0 * Int(ReplayFixture.glyphStride), as: MUIGlyph.self).transform }
        }
        let used = rects + glyphs + images.map { $0.filter >> 8 }
        guard used.allSatisfy({ Int($0) <= transformCount }) else { throw .invalid("\(name) names a missing transform") }
    }
}

/// The groups of a scene tree as fixture groups, post-order (`GO-F`): `groups` (a group's quads name only earlier
/// ones), and `rootQuads`, the root scene's group quads with `texture` rewritten to the group's index in `groups`.
public struct FixtureGroupTree {
    public var groups: [FixtureGroup] = []
    public var rootQuads: [MUIImage] = []

    /// `textureIndex` maps an `ImageTexture` to its index in the fixture's shared texture list (the caller owns the list,
    /// root textures first).
    public init(_ scene: Scene, textureIndex: (ImageTexture) -> UInt32) {
        rootQuads = visit(scene, textureIndex)
    }

    /// Visits `scene`'s groups, appending each (after its own groups) to ``groups``; returns the scene's group quads with
    /// their flat group index.
    private mutating func visit(_ scene: Scene, _ textureIndex: (ImageTexture) -> UInt32) -> [MUIImage] {
        var quads: [MUIImage] = []
        for (index, quad) in scene.groups.enumerated() {
            let child = scene.groupScenes[index]
            let childQuads = visit(child, textureIndex)
            var images = child.images
            for k in images.indices { images[k].texture = textureIndex(child.textures[Int(images[k].texture)]) }
            let imageCount = images.count
            images += childQuads
            var runs: [FixtureRun] = []
            for run in child.drawList {
                switch run.kind {
                case .rect, .glyph, .image: runs.append(FixtureRun(scene: run))
                case .group: runs.append(FixtureRun(kind: .group, start: UInt32(imageCount + run.start), count: UInt32(run.count)))
                case .surface, .backdrop: continue   // a group holds neither (`GO-C`)
                }
            }
            let filter = scene.groupFilters[index]
            // The mask scene (`CM-A`): the same body form, its images naming the shared texture list.
            let mask = scene.groupMasks[index].map { mask -> FixtureBody in
                var maskImages = mask.images
                for k in maskImages.indices { maskImages[k].texture = textureIndex(mask.textures[Int(maskImages[k].texture)]) }
                return FixtureBody(rects: mask.rects.withUnsafeBytes { Array($0) },
                                   glyphs: mask.glyphs.withUnsafeBytes { Array($0) },
                                   images: maskImages.withUnsafeBytes { Array($0) },
                                   transforms: mask.transforms.withUnsafeBytes { Array($0) },
                                   runs: mask.drawList.compactMap { run in
                                       switch run.kind {
                                       case .rect, .glyph, .image: FixtureRun(scene: run)
                                       case .group, .surface, .backdrop: nil
                                       }
                                   })
            }
            groups.append(FixtureGroup(
                x: UInt32(max(quad.bounds.origin.x, 0)), y: UInt32(max(quad.bounds.origin.y, 0)),
                width: UInt32(quad.bounds.size.width), height: UInt32(quad.bounds.size.height),
                body: FixtureBody(rects: child.rects.withUnsafeBytes { Array($0) },
                                  glyphs: child.glyphs.withUnsafeBytes { Array($0) },
                                  images: images.withUnsafeBytes { Array($0) },
                                  transforms: child.transforms.withUnsafeBytes { Array($0) }, runs: runs),
                filterKind: filter.kind.rawValue, sigma: filter.sigma,
                tint: [filter.tint.x, filter.tint.y, filter.tint.z, filter.tint.w], mask: mask))
            var flat = quad
            flat.texture = MUIUInt(groups.count - 1)
            quads.append(flat)
        }
        return quads
    }
}

/// A group in a ``FlatFrame``: its box and the slice of the flat run array that draws it.
public struct FlatGroup: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: UInt32
    public var height: UInt32
    public var runStart: UInt32
    public var runCount: UInt32
    /// The group's filter (version 8, `GF-F`), as ``FixtureGroup`` holds it.
    public var filterKind: UInt32 = 0
    public var sigma: Float = 0
    public var tint: [Float] = [0, 0, 0, 0]
    /// The slice of the flat run array that draws the group's mask (version 9, `CM-A`), after the group's own runs;
    /// `maskRunCount` 0 is no mask.
    public var maskRunStart: UInt32 = 0
    public var maskRunCount: UInt32 = 0
}

/// A frame's records and its groups' in one set of arrays (`GO-F`), for the C bridge, which uploads one buffer a kind:
/// the root's records first, then each group's in post-order, every transform index shifted by the transforms before it
/// and every run start by the records before it. Group quads are image records whose `texture` is `groupTextureBase`
/// plus the group's index (the bridge's image-handle array has the group targets after the frame's own handles), and
/// their runs are image runs. With no group the arrays are the inputs.
public struct FlatFrame: Sendable {
    public var rects: [UInt8]
    public var glyphs: [UInt8]
    public var images: [UInt8]
    public var transforms: [UInt8]
    /// The root's runs, then every group's.
    public var runs: [FixtureRun]
    public var mainRunCount: Int
    public var groups: [FlatGroup]

    public init(root: FixtureBody, groups fixtureGroups: [FixtureGroup], groupTextureBase: UInt32) {
        rects = root.rects; glyphs = root.glyphs; images = root.images; transforms = root.transforms
        mainRunCount = root.runs.count
        runs = []
        groups = []
        append(root, transformShift: 0, rectShift: 0, glyphShift: 0, imageShift: 0, base: groupTextureBase, appendRecords: false)
        for group in fixtureGroups {
            let start = UInt32(runs.count)
            let transformShift = UInt32(transforms.count / Int(ReplayFixture.transformStride))
            let rectShift = UInt32(rects.count / Int(ReplayFixture.rectStride))
            let glyphShift = UInt32(glyphs.count / Int(ReplayFixture.glyphStride))
            let imageShift = UInt32(images.count / Int(ReplayFixture.imageStride))
            append(group.body, transformShift: transformShift, rectShift: rectShift, glyphShift: glyphShift,
                   imageShift: imageShift, base: groupTextureBase, appendRecords: true)
            let groupRunCount = UInt32(runs.count) - start
            // The group's mask body follows its own records, every index shifted like any record's (`CM-A`).
            let maskStart = UInt32(runs.count)
            if let mask = group.mask {
                append(mask, transformShift: UInt32(transforms.count / Int(ReplayFixture.transformStride)),
                       rectShift: UInt32(rects.count / Int(ReplayFixture.rectStride)),
                       glyphShift: UInt32(glyphs.count / Int(ReplayFixture.glyphStride)),
                       imageShift: UInt32(images.count / Int(ReplayFixture.imageStride)), base: groupTextureBase, appendRecords: true)
            }
            groups.append(FlatGroup(x: Float(group.x), y: Float(group.y), width: group.width, height: group.height,
                                    runStart: start, runCount: groupRunCount,
                                    filterKind: group.filterKind, sigma: group.sigma, tint: group.tint,
                                    maskRunStart: maskStart, maskRunCount: UInt32(runs.count) - maskStart))
        }
    }

    /// Appends a body's runs (and, for a group, its records with shifted transform indices); the root's records are
    /// already in place and only its group quads and runs are rewritten.
    private mutating func append(_ body: FixtureBody, transformShift: UInt32, rectShift: UInt32, glyphShift: UInt32,
                                 imageShift: UInt32, base: UInt32, appendRecords: Bool) {
        let rectStride = Int(ReplayFixture.rectStride), glyphStride = Int(ReplayFixture.glyphStride)
        let imageStride = Int(ReplayFixture.imageStride)
        var quadRecords = Set<Int>()
        for run in body.runs where run.kind == .group {
            for k in Int(run.start)..<Int(run.start + run.count) { quadRecords.insert(k) }
        }
        if appendRecords {
            var shifted = body.rects
            if transformShift > 0 {
                for i in 0..<shifted.count / rectStride {
                    shifted.withUnsafeMutableBytes { raw in
                        var rect = raw.loadUnaligned(fromByteOffset: i * rectStride, as: MUIRect.self)
                        if rect.shape >> 8 > 0 { rect.shape += transformShift << 8 }
                        raw.storeBytes(of: rect, toByteOffset: i * rectStride, as: MUIRect.self)
                    }
                }
            }
            rects += shifted
            var glyphBytes = body.glyphs
            if transformShift > 0 {
                for i in 0..<glyphBytes.count / glyphStride {
                    glyphBytes.withUnsafeMutableBytes { raw in
                        var glyph = raw.loadUnaligned(fromByteOffset: i * glyphStride, as: MUIGlyph.self)
                        if glyph.transform > 0 { glyph.transform += transformShift }
                        raw.storeBytes(of: glyph, toByteOffset: i * glyphStride, as: MUIGlyph.self)
                    }
                }
            }
            glyphs += glyphBytes
            transforms += body.transforms
        }
        var imageBytes = appendRecords ? body.images : images
        for i in 0..<imageBytes.count / imageStride {
            imageBytes.withUnsafeMutableBytes { raw in
                var image = raw.loadUnaligned(fromByteOffset: i * imageStride, as: MUIImage.self)
                if quadRecords.contains(i) { image.texture += base }
                // A record's transform index (a filtered group's quad drawn under a projective record included, `GF-C`)
                // names its own scene's table; the root's is unshifted.
                if appendRecords, image.filter >> 8 > 0 { image.filter += transformShift << 8 }
                raw.storeBytes(of: image, toByteOffset: i * imageStride, as: MUIImage.self)
            }
        }
        if appendRecords { images += imageBytes } else { images = imageBytes }
        for run in body.runs {
            switch run.kind {
            case .rect: runs.append(FixtureRun(kind: .rect, start: run.start + rectShift, count: run.count))
            case .glyph: runs.append(FixtureRun(kind: .glyph, start: run.start + glyphShift, count: run.count))
            case .image, .group: runs.append(FixtureRun(kind: .image, start: run.start + imageShift, count: run.count))
            case .backdrop: runs.append(run)
            }
        }
    }
}

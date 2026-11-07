#if canImport(MetalUIAppKit)
import AppKit
import CoreGraphics
import MetalUICore
import MetalUIScene

// The macOS route of `Image(systemName:)` (record 230, `SYM-C`): AppKit rasterises the SF Symbol, MetalUI tints and
// draws it as an ordinary `MUIImage`. No shader or primitive changes (`TE-AD`). Probe `swiftui-symbol-images.swift`
// `S9`, `S9b` and the bounded placement attempt in its header record the residue against SwiftUI's own raster
// (divergence 227).

/// The process-wide raster cache for symbols (`SYM-C`): coverage by (name, point size, weight, scale, pixel size) so a
/// colour change re-tints without re-rasterising, tinted textures by coverage key and colour so a frame that repeats
/// a symbol hands the renderer the **same `ImageTexture` identity** (`TE-AF`). Process-wide on purpose: a window's
/// `RasterCache` drops what a frame did not touch, which would re-rasterise after every retained replay. LRU, 512
/// entries per table.
@MainActor
final class SymbolRasterCache {
    static let shared = SymbolRasterCache()
    static let capacity = 512

    /// AppKit rasters drawn (a coverage, or a hierarchical or multicolor raster).
    private(set) var rastersMade = 0
    /// Tinted textures built from a cached coverage.
    private(set) var tintsMade = 0
    /// Texture requests.
    private(set) var lookups = 0

    struct Key: Hashable {
        var name: String
        var pointSize: Double
        var weight: Double
        var scale: Image.Scale
        var pixelWidth: Int
        var pixelHeight: Int
        var stretched: Bool
        var deviceScaleBits: UInt32
    }
    struct TintKey: Hashable {
        var key: Key
        var mode: SymbolRenderingMode
        var rgba: UInt32
    }
    private struct Entry<Value> { var value: Value; var stamp: Int }

    private var coverage: [Key: Entry<[UInt8]>] = [:]
    private var tinted: [TintKey: Entry<ImageTexture>] = [:]
    private var clock = 0
    private var metricsCache: [SymbolSpec: SymbolMetrics?] = [:]
    private var existsCache: [String: Bool] = [:]
    private var descriptionCache: [String: String?] = [:]

    var coverageCount: Int { coverage.count }
    var tintedCount: Int { tinted.count }

    /// Drops everything and zeroes the counters (a test seam).
    func reset() {
        coverage = [:]; tinted = [:]; metricsCache = [:]; existsCache = [:]; descriptionCache = [:]
        rastersMade = 0; tintsMade = 0; lookups = 0; clock = 0
    }

    func exists(_ name: String) -> Bool {
        if let known = existsCache[name] { return known }
        let found = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        existsCache[name] = found
        return found
    }

    func accessibilityDescription(_ name: String) -> String? {
        if let known = descriptionCache[name] { return known }
        let found = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.accessibilityDescription
        descriptionCache[name] = found
        return found
    }

    private static func nsScale(_ scale: Image.Scale) -> NSImage.SymbolScale {
        switch scale {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }

    private func configured(_ spec: SymbolSpec, extra: NSImage.SymbolConfiguration? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: spec.name, accessibilityDescription: nil) else { return nil }
        var configuration = NSImage.SymbolConfiguration(pointSize: spec.pointSize, weight: NSFont.Weight(rawValue: spec.weight),
                                                        scale: Self.nsScale(spec.scale))
        if let extra { configuration = configuration.applying(extra) }
        return base.withSymbolConfiguration(configuration)
    }

    func metrics(_ spec: SymbolSpec) -> SymbolMetrics? {
        if let known = metricsCache[spec] { return known }
        var result: SymbolMetrics?
        if let image = configured(spec) {
            let alignment = image.alignmentRect
            result = SymbolMetrics(width: Double(alignment.width), height: Double(image.size.height),
                                   baseline: Double(image.size.height - alignment.minY), originX: Double(alignment.minX))
        }
        metricsCache[spec] = result
        return result
    }

    private func touch(_ stamp: inout Int) { clock += 1; stamp = clock }

    private func evictCoverage() {
        while coverage.count > Self.capacity, let oldest = coverage.min(by: { $0.value.stamp < $1.value.stamp })?.key {
            coverage[oldest] = nil
        }
    }
    private func evictTinted() {
        while tinted.count > Self.capacity, let oldest = tinted.min(by: { $0.value.stamp < $1.value.stamp })?.key {
            tinted[oldest] = nil
        }
    }

    /// The texture for `spec` at `pixelWidth` x `pixelHeight`, tinted `color` (monochrome and hierarchical; multicolor
    /// ignores it), or `nil` when AppKit does not know the symbol.
    func texture(_ spec: SymbolSpec, metrics: SymbolMetrics, mode: SymbolRenderingMode, color: Rgba,
                 pixelWidth: Int, pixelHeight: Int, stretched: Bool, deviceScale: Float) -> ImageTexture? {
        lookups += 1
        let key = Key(name: spec.name, pointSize: spec.pointSize, weight: spec.weight, scale: spec.scale,
                      pixelWidth: pixelWidth, pixelHeight: pixelHeight, stretched: stretched,
                      deviceScaleBits: deviceScale.bitPattern)
        let bytes = Self.quantised(color)
        switch mode {
        case .monochrome:
            let tintKey = TintKey(key: key, mode: .monochrome, rgba: bytes)
            if var hit = tinted[tintKey] { touch(&hit.stamp); tinted[tintKey] = hit; return hit.value }
            let alpha: [UInt8]
            if var hit = coverage[key] {
                touch(&hit.stamp); coverage[key] = hit
                alpha = hit.value
            } else {
                guard let rgba = draw(spec, metrics: metrics, mode: .monochrome, color: nil,
                                      pixelWidth: pixelWidth, pixelHeight: pixelHeight, stretched: stretched) else { return nil }
                rastersMade += 1
                var cover = [UInt8](repeating: 0, count: pixelWidth * pixelHeight)
                for i in 0..<cover.count { cover[i] = rgba[i * 4 + 3] }
                alpha = cover
                var entry = Entry(value: cover, stamp: 0); touch(&entry.stamp)
                coverage[key] = entry
                evictCoverage()
            }
            tintsMade += 1
            let texture = Self.tint(alpha, width: pixelWidth, height: pixelHeight, bytes: bytes)
            var entry = Entry(value: texture, stamp: 0); touch(&entry.stamp)
            tinted[tintKey] = entry
            evictTinted()
            return texture
        case .hierarchical, .multicolor:
            // Coloured by AppKit: the raster depends on the colour (hierarchical) and is the texture itself.
            let tintKey = TintKey(key: key, mode: mode, rgba: mode == .hierarchical ? bytes : 0)
            if var hit = tinted[tintKey] { touch(&hit.stamp); tinted[tintKey] = hit; return hit.value }
            guard let rgba = draw(spec, metrics: metrics, mode: mode, color: mode == .hierarchical ? bytes : nil,
                                  pixelWidth: pixelWidth, pixelHeight: pixelHeight, stretched: stretched) else { return nil }
            rastersMade += 1
            let texture = ImageTexture(width: pixelWidth, height: pixelHeight, premultipliedRGBA: rgba)
            var entry = Entry(value: texture, stamp: 0); touch(&entry.stamp)
            tinted[tintKey] = entry
            evictTinted()
            return texture
        }
    }

    /// The colour as four bytes (r, g, b, a packed high to low): the key and the tint are one function of it.
    private static func quantised(_ c: Rgba) -> UInt32 {
        func byte(_ v: Float) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(c.r) << 24 | byte(c.g) << 16 | byte(c.b) << 8 | byte(c.a)
    }

    /// Coverage times colour, premultiplied.
    private static func tint(_ alpha: [UInt8], width: Int, height: Int, bytes: UInt32) -> ImageTexture {
        let r = Float((bytes >> 24) & 255), g = Float((bytes >> 16) & 255), b = Float((bytes >> 8) & 255), a = Float(bytes & 255) / 255
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let k = Float(alpha[i]) / 255 * a
            pixels[i * 4] = UInt8((r * k).rounded())
            pixels[i * 4 + 1] = UInt8((g * k).rounded())
            pixels[i * 4 + 2] = UInt8((b * k).rounded())
            pixels[i * 4 + 3] = UInt8((255 * k).rounded())
        }
        return ImageTexture(width: width, height: height, premultipliedRGBA: pixels)
    }

    /// One AppKit raster: premultiplied RGBA8 sRGB, row 0 at the top. The image is drawn so its alignment rect fills the
    /// layout box (`originX`), or stretched over the whole texture for a resizable symbol.
    private func draw(_ spec: SymbolSpec, metrics: SymbolMetrics, mode: SymbolRenderingMode, color: UInt32?,
                      pixelWidth: Int, pixelHeight: Int, stretched: Bool) -> [UInt8]? {
        var extra: NSImage.SymbolConfiguration?
        switch mode {
        case .monochrome: extra = nil
        case .hierarchical:
            let c = color ?? 0x000000FF
            extra = NSImage.SymbolConfiguration(hierarchicalColor: NSColor(
                srgbRed: CGFloat((c >> 24) & 255) / 255, green: CGFloat((c >> 16) & 255) / 255,
                blue: CGFloat((c >> 8) & 255) / 255, alpha: CGFloat(c & 255) / 255))
        case .multicolor: extra = NSImage.SymbolConfiguration.preferringMulticolor()
        }
        guard let image = configured(spec, extra: extra) else { return nil }
        var data = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                          bytesPerRow: pixelWidth * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            if stretched {
                image.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight), from: .zero,
                           operation: .sourceOver, fraction: 1)
            } else {
                context.scaleBy(x: CGFloat(pixelWidth) / CGFloat(metrics.width), y: CGFloat(pixelHeight) / CGFloat(metrics.height))
                image.draw(in: NSRect(x: -metrics.originX, y: 0, width: image.size.width, height: image.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return data
    }
}

/// The platform side of `Image(systemName:)` on macOS: AppKit's catalogue, metrics and raster, through the
/// process-wide cache.
@MainActor
enum SymbolBackend {
    static func exists(_ name: String) -> Bool { SymbolRasterCache.shared.exists(name) }
    static func metrics(_ spec: SymbolSpec) -> SymbolMetrics? { SymbolRasterCache.shared.metrics(spec) }
    static func accessibilityDescription(_ name: String) -> String? { SymbolRasterCache.shared.accessibilityDescription(name) }
    static func texture(_ spec: SymbolSpec, metrics: SymbolMetrics, mode: SymbolRenderingMode, color: Rgba,
                        pixelWidth: Int, pixelHeight: Int, stretched: Bool, deviceScale: Float) -> ImageTexture? {
        SymbolRasterCache.shared.texture(spec, metrics: metrics, mode: mode, color: color, pixelWidth: pixelWidth,
                                         pixelHeight: pixelHeight, stretched: stretched, deviceScale: deviceScale)
    }
}
#endif

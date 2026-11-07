import MetalUICore
import MetalUILayout
import MetalUIScene

// `Image(systemName:)` (record 230, prefix `SYM-`): the request, the name resolution, the shared plan layout and paint
// read, the diagnostics and the accessibility labels. The raster route is `SymbolRasterAppKit.swift`, behind
// `canImport(MetalUIAppKit)`; **on any other platform every name is missing** (an empty 0 x 0 leaf) until the bundled
// icons land (PR 2, `SYM-I`).

/// Resolves the symbol name that `variants` select (probes `S5`, `S5b`): the name with `.slash`, then the shape
/// (`.circle`, `.square`, `.rectangle`), then `.fill` appended, **dropping words with the priority slash, shape,
/// fill when that full name does not exist** (`star` + `.circle.slash` is `star.slash`; `doc` + `.rectangle.slash.fill`
/// is `doc.fill`), and the name itself when no variant exists. `nil` when not even the name exists (a missing
/// symbol). Pure: `exists` is the platform's catalogue, so both platforms and the tests share it (`SYM-F`).
func resolveSymbolName(_ name: String, variants: SymbolVariants, exists: (String) -> Bool) -> String? {
    var words: [(word: String, weight: Int)] = []
    if variants.hasSlash { words.append(("slash", 4)) }
    switch variants.shape {
    case .none: break
    case .circle: words.append(("circle", 2))
    case .square: words.append(("square", 2))
    case .rectangle: words.append(("rectangle", 2))
    }
    if variants.hasFill { words.append(("fill", 1)) }
    let subsets = (1..<(1 << words.count)).map { mask in
        words.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
    }.sorted { $0.reduce(0) { $0 + $1.weight } > $1.reduce(0) { $0 + $1.weight } }
    for subset in subsets {
        let candidate = name + "." + subset.map(\.word).joined(separator: ".")
        if exists(candidate) { return candidate }
    }
    return exists(name) ? name : nil
}

/// The names `Image(systemName:)` could not draw, counted once each (`SYM-G`). SwiftUI is silent about a missing name
/// (probe `S6`: a 0 x 0 leaf, no stderr), so MetalUI is too; this counter exists for tests and tools.
@MainActor
enum SymbolDiagnostics {
    /// Each missing name once: the number of distinct frames that missed it is deliberately not counted.
    static var misses: [String: Int] = [:]
    static func noteMiss(_ name: String) { if misses[name] == nil { misses[name] = 1 } }
    static func reset() { misses = [:] }
}

/// What a platform needs to draw one symbol: the resolved catalogue name, the font's point size and weight trait
/// (CoreText's, which is `NSFont.Weight`'s raw value) and the image scale.
struct SymbolSpec: Hashable, Sendable {
    var name: String
    var pointSize: Double
    var weight: Double
    var scale: Image.Scale
}

/// A symbol's layout, in points (`SYM-D`, probes `S1`, `S2`): the width is the **alignment rect's** width, the height the
/// image's, the baseline `height - alignmentRect.minY` (first and last), and `originX` the alignment rect's left edge,
/// which the paint shifts the image by.
struct SymbolMetrics: Equatable, Sendable {
    var width: Double
    var height: Double
    var baseline: Double
    var originX: Double
}

/// Everything layout and paint both read for one symbol, resolved once from the environment (`SYM-D`).
struct SymbolPlan {
    var spec: SymbolSpec
    var metrics: SymbolMetrics
    var mode: SymbolRenderingMode
}

extension Image {
    /// A symbol from the platform's catalogue — SwiftUI's `Image(systemName:)` (`SYM-B`). Its size is the font's:
    /// the point size and weight of the font in the environment, scaled by `imageScale`, laid out as SwiftUI lays
    /// the same symbol out (probe `S1`: the alignment rect's width, the image's height), with a first and last baseline
    /// (`S2`). **macOS draws the platform's own SF Symbols; on Linux and Windows every name is missing until the
    /// bundled icons land (`SYM-I`).** A name that does not exist is a 0 x 0 leaf that draws nothing and logs nothing
    /// (probe `S6`). The image is labelled for accessibility with SwiftUI's own label for the name (`SYM-H`).
    public init(systemName: String) {
        content = .symbol(name: systemName)
    }

    /// SwiftUI's `Image.symbolRenderingMode(_:)`: how this image colours itself, over the environment's mode; `nil`
    /// defers to it. Only a symbol has one.
    public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Image {
        var copy = self
        copy.symbolMode = mode
        return copy
    }

    /// The plan for `name` under `environment`, or `nil` for a missing name (counted once in the diagnostics).
    @MainActor
    func symbolPlan(for name: String, in environment: EnvironmentValues) -> SymbolPlan? {
        let style = resolveTextStyle(TextStyleRequest(), in: environment)
        guard let resolved = resolveSymbolName(name, variants: environment.symbolVariants, exists: { SymbolBackend.exists($0) }) else {
            SymbolDiagnostics.noteMiss(name)
            return nil
        }
        let spec = SymbolSpec(name: resolved, pointSize: style.descriptor.size, weight: style.descriptor.weight ?? 0,
                              scale: environment.imageScale)
        guard let metrics = SymbolBackend.metrics(spec) else {
            SymbolDiagnostics.noteMiss(name)
            return nil
        }
        return SymbolPlan(spec: spec, metrics: metrics, mode: symbolMode ?? environment.symbolRenderingMode ?? .monochrome)
    }

    /// The accessibility label of a symbol: SwiftUI's own label for the names probe `S8b` read, the platform's
    /// description for others (divergence 227: AppKit's wording and capitalisation differ).
    @MainActor
    func symbolLabel(for plan: SymbolPlan) -> String? {
        SymbolAccessibilityLabels.table[plan.spec.name] ?? SymbolBackend.accessibilityDescription(plan.spec.name)
    }

    /// The one raster a cursor or toolbar button shows for `name` (`SYM-L`): the body font (13 pt, regular), medium scale,
    /// monochrome black, rasterised at scale 2 so it is 16 pt-class crisp on a 2x display; `nil` for a missing name.
    @MainActor
    static func platformRaster(forSymbol name: String) -> (texture: ImageTexture, scale: Float)? {
        var environment = EnvironmentValues()
        environment.font = .system(size: 13)
        guard let plan = Image(systemName: name).symbolPlan(for: name, in: environment) else { return nil }
        let scale: Float = 2
        let width = max(1, Int((plan.metrics.width * Double(scale)).rounded()))
        let height = max(1, Int((plan.metrics.height * Double(scale)).rounded()))
        guard let texture = SymbolBackend.texture(plan.spec, metrics: plan.metrics, mode: .monochrome,
                                                  color: Rgba(r: 0, g: 0, b: 0, a: 1),
                                                  pixelWidth: width, pixelHeight: height, stretched: false,
                                                  deviceScale: scale) else { return nil }
        return (texture, scale)
    }
}

/// SwiftUI's accessibility label for each symbol the probe read (`S8b`, macOS 27.2): title-cased and not always
/// AppKit's `accessibilityDescription` (`doc.on.doc` is "Copy", `pencil` "Edit"). Names outside the table fall back to the
/// platform's description (`SYM-H`).
enum SymbolAccessibilityLabels {
    static let table: [String: String] = [
        "star": "Favorite", "star.fill": "Favorite", "magnifyingglass": "Search", "doc": "Document", "doc.text": "Plain Text Document",
        "pencil": "Edit", "square.and.pencil": "Compose", "doc.badge.plus": "Document With A Plus Badge",
        "terminal": "Terminal Command Prompt", "apple.terminal": "Terminal Command-Line Prompt", "brain": "Human Brain",
        "brain.head.profile": "Head Profile Showing The Brain", "sparkles": "Sparkle", "globe": "Globe",
        "person": "Person Silhouette", "person.crop.circle": "Account", "exclamationmark.triangle": "Warning",
        "xmark": "Close", "xmark.circle": "Close", "xmark.circle.fill": "Close", "play": "Play", "play.fill": "Play",
        "stop": "Stop Button Square", "stop.fill": "Stop", "stop.circle": "Stop Button In A Circle", "checkmark": "Selected",
        "chevron.right": "Forward", "chevron.down": "Go Down", "doc.on.doc": "Copy", "arrow.uturn.backward": "Undo",
        "arrow.up.right.square": "Up-Right Arrow In A Square", "rectangle.split.2x1": "Rectangle Split Two By One",
        "cpu": "Cpu Chip", "desktopcomputer": "Computer", "brain.filled.head.profile": "Head Profile With A Filled Brain",
        "gearshape.2": "Advanced", "ant": "Report Issue",
    ]
}

#if !canImport(MetalUIAppKit)
/// The platform side of `Image(systemName:)` on a platform without the AppKit raster route: every name is missing
/// (`SYM-C`; the bundled icons are PR 2).
@MainActor
enum SymbolBackend {
    static func exists(_ name: String) -> Bool { false }
    static func metrics(_ spec: SymbolSpec) -> SymbolMetrics? { nil }
    static func accessibilityDescription(_ name: String) -> String? { nil }
    static func texture(_ spec: SymbolSpec, metrics: SymbolMetrics, mode: SymbolRenderingMode, color: Rgba,
                        pixelWidth: Int, pixelHeight: Int, stretched: Bool, deviceScale: Float) -> ImageTexture? { nil }
}
#endif

import MetalUICore
import MetalUIIconData
import MetalUILayout
import MetalUIScene

// The portable route of `Image(systemName:)` and of `Image(icon:)` (record 232, rulings `SYM-I`, `SYM-J`): a table from SF
// Symbol names to the bundled Lucide icons (`MetalUIIconData`), a box fitted to SF Symbols' own measurements, and a paint
// through `pass.drawPath` (so the existing raster cache, crisp results under transforms, retained replay and both renderers
// apply, with no new raster code). **Linux and Windows always take this route; macOS takes it only under the
// `SymbolRoute.forcesBundled` test seam** (SF Symbols are drawn only through AppKit and never bundled or cached to disk:
// Apple's licence).

/// Which route `Image(systemName:)` takes (`SYM-C`, `SYM-I`).
enum SymbolRoute {
    /// A test seam (`package`): on macOS, draws the bundled icons instead of asking AppKit, so the portable layout and
    /// paint are tested where the suite runs. Ignored elsewhere (the bundled route is the only one).
    @MainActor package static var forcesBundled = false

    @MainActor static var usesBundled: Bool {
        #if canImport(MetalUIAppKit)
        forcesBundled
        #else
        true
        #endif
    }
}

/// The SF name table and the bundled `Icon`s (`SYM-I`).
@MainActor
enum BundledSymbols {
    /// One SF name's Lucide icon; `filled` adds a fill of the outline under its stroke (the `.fill` variants of a closed
    /// outline: play, stop, circle, square, triangle, star).
    struct Entry {
        var lucide: String
        var filled = false
        /// A vendored shape (not a Lucide file) filled under the stroke instead of the whole outline: the filled half of
        /// `rectangle.lefthalf.inset.filled` (`SYM-Q`). Wins over `filled`.
        var fillShape: String?
    }

    /// SF name to Lucide icon. Only names that exist on macOS 27.2 (probe `S1`): `robot` does not, `cpu` does. A `.fill`
    /// name exists only where the outline can be filled; elsewhere `symbolVariant(.fill)` falls back to the base name,
    /// as it does for an SF Symbol that has no filled variant (`S5`).
    static let table: [String: Entry] = [
        "magnifyingglass": Entry(lucide: "search"),
        "doc": Entry(lucide: "file"),
        "doc.text": Entry(lucide: "file-text"),
        "pencil": Entry(lucide: "pencil"),
        "square.and.pencil": Entry(lucide: "square-pen"),
        "doc.badge.plus": Entry(lucide: "file-plus"),
        "terminal": Entry(lucide: "square-terminal"),
        "apple.terminal": Entry(lucide: "square-terminal"),
        "brain": Entry(lucide: "brain"),
        "brain.head.profile": Entry(lucide: "brain"),
        "sparkles": Entry(lucide: "sparkles"),
        "globe": Entry(lucide: "globe"),
        "person": Entry(lucide: "user"),
        "person.crop.circle": Entry(lucide: "circle-user"),
        "exclamationmark.triangle": Entry(lucide: "triangle-alert"),
        "xmark": Entry(lucide: "x"),
        "xmark.circle": Entry(lucide: "circle-x"),
        "play": Entry(lucide: "play"),
        "play.fill": Entry(lucide: "play", filled: true),
        "stop": Entry(lucide: "square"),
        "stop.fill": Entry(lucide: "square", filled: true),
        "stop.circle": Entry(lucide: "circle-stop"),
        "checkmark": Entry(lucide: "check"),
        "chevron.right": Entry(lucide: "chevron-right"),
        "chevron.down": Entry(lucide: "chevron-down"),
        "doc.on.doc": Entry(lucide: "copy"),
        "arrow.uturn.backward": Entry(lucide: "undo-2"),
        "arrow.up.right.square": Entry(lucide: "square-arrow-out-up-right"),
        "rectangle.split.2x1": Entry(lucide: "columns-2"),
        "cpu": Entry(lucide: "cpu"),
        "star": Entry(lucide: "star"),
        "star.fill": Entry(lucide: "star", filled: true),
        "circle": Entry(lucide: "circle"),
        "circle.fill": Entry(lucide: "circle", filled: true),
        "square": Entry(lucide: "square"),
        "square.fill": Entry(lucide: "square", filled: true),
        "triangle": Entry(lucide: "triangle"),
        "triangle.fill": Entry(lucide: "triangle", filled: true),
        "checklist": Entry(lucide: "list-checks"),
        "questionmark.bubble": Entry(lucide: "message-circle-question"),
        "list.bullet.clipboard": Entry(lucide: "clipboard-list"),
        "puzzlepiece.extension": Entry(lucide: "puzzle"),
        "info.circle": Entry(lucide: "info"),
        "paperclip": Entry(lucide: "paperclip"),
        "photo": Entry(lucide: "image"),
        "gearshape": Entry(lucide: "settings"),
        "eye": Entry(lucide: "eye"),
        "eye.slash": Entry(lucide: "eye-off"),
        "eye.circle": Entry(lucide: "eye-circle"),
        "eye.slash.circle": Entry(lucide: "eye-off-circle"),
        // Record 279 (`SYM-Q`): MetalCreator's toolbar.
        "arrow.uturn.forward": Entry(lucide: "redo-2"),
        "square.and.arrow.up": Entry(lucide: "share"),
        "plus.magnifyingglass": Entry(lucide: "zoom-in"),
        "minus.magnifyingglass": Entry(lucide: "zoom-out"),
        "sidebar.left": Entry(lucide: "panel-left"),
        "rectangle.lefthalf.inset.filled": Entry(lucide: "panel-left", fillShape: "panel-left-fill"),
        "rectangle.bottomhalf.inset.filled": Entry(lucide: "panel-bottom", fillShape: "panel-bottom-fill"),
        "house": Entry(lucide: "house"),
        "camera": Entry(lucide: "camera"),
        // Record 288 (`SYM-R`): MetalCreator gap ICON-a.
        "plus": Entry(lucide: "plus"),
        "minus": Entry(lucide: "minus"),
    ]

    static func exists(_ name: String) -> Bool { table[name] != nil }

    private static var cache: [String: Icon] = [:]

    /// The icon for the exact SF name (no variants), built once.
    static func icon(forExactName name: String) -> Icon? {
        if let known = cache[name] { return known }
        guard let entry = table[name], let data = LucideIcons.data(named: entry.lucide) else { return nil }
        let path = Self.path(data)
        var layers: [Icon.Layer] = []
        if let shape = entry.fillShape {
            guard let shapeData = LucideIcons.data(named: shape) else { return nil }
            layers.append(Icon.Layer(Self.path(shapeData), paint: .fill(FillStyle())))
        } else if entry.filled { layers.append(Icon.Layer(path, paint: .fill(FillStyle()))) }
        layers.append(Icon.Layer(path, paint: .stroke(width: Pixels(LucideIcons.strokeWidth), cap: .round, join: .round)))
        let side = Pixels(LucideIcons.viewBoxSide)
        let icon = Icon(viewBox: Size(width: side, height: side), layers: layers)
        cache[name] = icon
        return icon
    }

    /// `data`'s move / line / cubic / close opcodes as a `Path` (the data holds nothing else).
    private static func path(_ data: IconPathData) -> Path {
        var path = Path()
        var c = 0
        func point() -> Point<Pixels> {
            defer { c += 2 }
            return Point(x: Pixels(data.coords[c]), y: Pixels(data.coords[c + 1]))
        }
        for op in data.ops {
            switch op {
            case 0: path.move(to: point())
            case 1: path.addLine(to: point())
            case 2:
                let c1 = point(), c2 = point(), end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
            default: path.closeSubpath()
            }
        }
        return path
    }
}

/// The portable box and stroke (`SYM-J`), fitted to the SF Symbols numbers recorded by probe `S1` and `S2`
/// (`docs/probes/swiftui-symbol-images.swift`, macOS 27.2).
enum PortableSymbolMetrics {
    /// The box's side as a multiple of the point size, per scale: the median over 38 SF names x 6 sizes (9, 11, 13, 17, 26, 48
    /// pt) of the alignment rect's width and the image's height (the two things `S1` found SwiftUI lays out by,
    /// H1'). Medians: 0.941, 1.154 and 1.462.
    static func sideFactor(_ scale: Image.Scale) -> Double {
        switch scale {
        case .small: 0.94
        case .medium: 1.15
        case .large: 1.46
        }
    }

    /// How far the SF image extends below its baseline as a multiple of the point size, per scale: the median of
    /// `alignmentRect.minY / pointSize` over the same sample (0.091, 0.192, 0.346). `S2` found the baseline is
    /// `height - alignmentRect.minY` (H2); the box has no alignment rect, so the portable baseline is
    /// `side - descent * pointSize`, and the cap-centre model (H3) was off by up to 2.8 pt there.
    static func descentFactor(_ scale: Image.Scale) -> Double {
        switch scale {
        case .small: 0.09
        case .medium: 0.19
        case .large: 0.35
        }
    }

    /// Lucide's stroke width on its 24-unit grid for each of the nine font weights, ultra-light to black: 1, 1.25, 1.5, 2
    /// (regular, Lucide's own), 2.25, 2.5, 2.75, 3, 3.25.
    private static let weightWidths: [(weight: Double, width: Double)] = [
        (-0.8, 1), (-0.6, 1.25), (-0.4, 1.5), (0, 2), (0.23, 2.25), (0.3, 2.5), (0.4, 2.75), (0.56, 3), (0.62, 3.25),
    ]

    /// The stroke of `weight` (CoreText's trait) relative to regular: a width of 2 at regular scales by 1.
    static func strokeFactor(weight: Double) -> Double {
        let nearest = weightWidths.min { abs($0.weight - weight) < abs($1.weight - weight) }!
        return nearest.width / 2
    }
}

/// Everything layout and paint both read for one bundled icon, resolved once from the environment.
struct IconPlan {
    var icon: Icon
    /// The box's side, in points.
    var side: Double
    /// The first and last baseline, from the box's top.
    var baseline: Double
    /// The font weight's stroke relative to regular.
    var strokeFactor: Double
    var mode: SymbolRenderingMode
    /// The SF name the plan was resolved from (a symbol only), for its accessibility label.
    var resolvedName: String?
}

extension Image {
    /// The plan of `icon` under `environment`: a square of the font's point size times the scale's factor
    /// (`PortableSymbolMetrics`).
    @MainActor
    func iconPlan(_ icon: Icon, resolvedName: String? = nil, in environment: EnvironmentValues) -> IconPlan {
        let style = resolveTextStyle(TextStyleRequest(), in: environment)
        let points = style.descriptor.size
        let scale = environment.imageScale
        let side = points * PortableSymbolMetrics.sideFactor(scale)
        return IconPlan(icon: icon, side: side, baseline: side - points * PortableSymbolMetrics.descentFactor(scale),
                        strokeFactor: PortableSymbolMetrics.strokeFactor(weight: style.descriptor.weight ?? 0),
                        mode: symbolMode ?? environment.symbolRenderingMode ?? .monochrome, resolvedName: resolvedName)
    }

    /// The bundled plan of the symbol `name`, or `nil` for a missing one (counted once, `SYM-G`).
    @MainActor
    func bundledSymbolPlan(for name: String, in environment: EnvironmentValues) -> IconPlan? {
        guard let resolved = resolveSymbolName(name, variants: environment.symbolVariants, exists: { BundledSymbols.exists($0) }),
              let icon = BundledSymbols.icon(forExactName: resolved) else {
            SymbolDiagnostics.noteMiss(name)
            return nil
        }
        return iconPlan(icon, resolvedName: resolved, in: environment)
    }

    /// The layout of a bundled icon: its square box and one baseline, or a bitmap's rule when resizable.
    nonisolated static func iconMeasurement(_ plan: IconPlan?, isResizable: Bool, proposal: ProposedSize) -> LayoutMeasurement {
        guard let plan else { return LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
        guard isResizable else {
            return LayoutMeasurement(size: SizeD(width: plan.side, height: plan.side),
                                     firstBaseline: plan.baseline, lastBaseline: plan.baseline)
        }
        return LayoutMeasurement(size: SizeD(width: proposal.width ?? plan.side, height: proposal.height ?? plan.side))
    }

    /// Draws `plan.icon` in `bounds`: scaled uniformly so the view box's larger side fills the smaller side of `bounds`,
    /// centred; each layer stroked (width x scale x weight) or filled in the foreground, a secondary layer at half under
    /// `.hierarchical` (`SYM-E`, `SYM-J`).
    @MainActor
    func paintIcon(_ plan: IconPlan, bounds: Bounds<Pixels>, pass: inout PaintPass) {
        let icon = plan.icon
        let boxWidth = Double(bounds.size.width.value), boxHeight = Double(bounds.size.height.value)
        let viewWidth = Double(icon.viewBox.width.value), viewHeight = Double(icon.viewBox.height.value)
        guard boxWidth > 0, boxHeight > 0, viewWidth > 0, viewHeight > 0 else { return }
        let scale = min(boxWidth, boxHeight) / max(viewWidth, viewHeight)
        let transform = Transform2D(a: scale, b: 0, c: 0, d: scale,
                                    tx: Double(bounds.origin.x.value) + (boxWidth - viewWidth * scale) / 2,
                                    ty: Double(bounds.origin.y.value) + (boxHeight - viewHeight * scale) / 2)
        let (foreground, _) = resolveForeground(nil, in: pass.environment)
        let base = pass.resolve(foreground)
        for layer in icon.layers {
            var color = base
            if plan.mode == .hierarchical, layer.level == .secondary { color.a *= 0.5 }
            let path = layer.path.applying(transform)
            switch layer.paint {
            case .stroke(let width, let cap, let join):
                let device = Double(width.value) * scale * plan.strokeFactor
                pass.drawPath(path, stroke: StrokeStyle(lineWidth: Pixels(Float(device)), lineCap: cap, lineJoin: join), color: color)
            case .fill(let style):
                pass.drawPath(path, fill: style, color: color)
            }
        }
    }
}

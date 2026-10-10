import MetalUICore
import MetalUILayout

// C10 lane 1: `ColorPicker`'s drawn panel (rulings `LK-C` item 5, `LK-D`,
// `LK-P` item 3; spec `2026-10-08-controls-looks-design.md` §3.1). SwiftUI
// has no drawn panel to measure: every rule here is MetalUI's, except the
// binding's (every write a gamma-sRGB literal, `C4`–`C6`; opacity 1 without
// `supportsOpacity`, `C8`).

/// The panel's colour: HSB plus an opacity, each 0…1 (hue a fraction of a turn).
struct PanelColor: Equatable {
    var hsb: ColorMath.HSB
    var opacity: Double

    init(_ rgba: ColorMath.RGBA) {
        hsb = ColorMath.hsb(from: rgba.rgb)
        opacity = ColorMath.clamp(rgba.opacity)
    }

    init(hsb: ColorMath.HSB, opacity: Double) {
        self.hsb = hsb
        self.opacity = opacity
    }

    /// The sRGB components with the opacity.
    var rgba: ColorMath.RGBA {
        let rgb = ColorMath.rgb(from: hsb)
        return ColorMath.RGBA(red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }
}

/// The panel's own edit (`LK-D` item 4): the colour it last wrote, with the
/// HSB it wrote it from — so the hue survives saturation or brightness 0.
struct PanelEdit: Equatable {
    var color: PanelColor
    var written: Color
}

/// The drawn colour panel (`LK-D` item 1), a popover's content: **one**
/// column (a popover's content is one presentation root, `LK-P` item 3) of a
/// 200×150 saturation–brightness square, a 200×14 hue bar, a 200×14 opacity
/// bar only with `supportsOpacity`, and a row of a 24×24 swatch and the hex
/// field. The popover's chrome pads it by 12.
///
/// **Its colour** is its own `@State` edit while the binding still holds the
/// colour that edit wrote; otherwise — at open, or after a write from outside
/// — it is the selection resolved at this frame's layout (`seed`), so an
/// outside write re-seeds it and the panel's own drag keeps its hue (`LK-D`
/// item 4). Its `@State` starts fresh at each presentation (`ID-C`).
struct ColorPickerPanel: Component {
    let selection: Binding<Color>
    let supportsOpacity: Bool
    /// The selection resolved in the picker's environment at this layout.
    let seed: ColorMath.RGBA
    @State var edit: PanelEdit? = nil
    /// The hex field's text while it is being edited; `nil` shows the colour.
    @State var hexDraft: String? = nil

    var elementID: ElementID? { nil }

    nonisolated static let width: Float = 200
    nonisolated static let squareHeight: Float = 150
    nonisolated static let barHeight: Float = 14
    nonisolated static let gap: Float = 8
    nonisolated static let swatch: Float = 24

    /// The colour shown: the panel's edit if the binding still holds what it
    /// wrote, else the seed. Read fresh by every handler (under `StateDispatch`).
    var current: PanelColor {
        if let edit, edit.written == selection.wrappedValue { return edit.color }
        return PanelColor(seed)
    }

    /// The hex field's text for `color` (`LK-D` item 6).
    func hex(_ color: PanelColor) -> String {
        ColorMath.hexString(color.rgba, includesAlpha: supportsOpacity && ColorMath.byte(color.opacity) < 255)
    }

    /// Writes `color` to the binding as a gamma-sRGB literal — opacity 1
    /// without `supportsOpacity` (`C8`) — and remembers it. From input only.
    func apply(_ color: PanelColor) {
        var color = color
        color.hsb.saturation = ColorMath.clamp(color.hsb.saturation)
        color.hsb.brightness = ColorMath.clamp(color.hsb.brightness)
        color.opacity = ColorMath.clamp(color.opacity)
        let rgba = color.rgba
        let written = Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue,
                            opacity: supportsOpacity ? rgba.opacity : 1)
        edit = PanelEdit(color: color, written: written)
        hexDraft = nil
        selection.wrappedValue = written
    }

    /// Changes the current colour with `change` and writes it.
    func adjust(_ change: (inout PanelColor) -> Void) {
        var color = current
        change(&color)
        apply(color)
    }

    /// The field's submit: a valid string writes, an invalid one reverts.
    func submitHex() {
        defer { hexDraft = nil }
        guard let draft = hexDraft, let parsed = ColorMath.parseHex(draft, allowsAlpha: supportsOpacity) else { return }
        var color = PanelColor(parsed)
        if !supportsOpacity { color.opacity = current.opacity }
        // A grey keeps the current hue (`LK-D` item 4's footing).
        if color.hsb.saturation == 0 || color.hsb.brightness == 0 { color.hsb.hue = current.hsb.hue }
        apply(color)
    }

    var content: some ElementGroup {
        let color = current
        let rgba = color.rgba
        let literal = Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue,
                            opacity: supportsOpacity ? rgba.opacity : 1)
        let hexText = Binding(get: { hexDraft ?? hex(current) }, set: { hexDraft = $0 })
        return Column(gap: Pixels(Self.gap)) {
            ColorPanelParts.square(self, color)
            ColorPanelParts.hueBar(self, color)
            if supportsOpacity {
                ColorPanelParts.opacityBar(self, color)
            }
            Row(gap: Pixels(Self.gap)) {
                Box().frame(width: Pixels(Self.swatch), height: Pixels(Self.swatch))
                    .background(literal).cornerRadius(Pixels(4))
                TextField("Hex", text: hexText).onSubmit { submitHex() }
                    .frame(width: Pixels(Self.width - Self.swatch - Self.gap))
            }
        }
        .alignItems(.flexStart)
    }
}

/// The panel's three planes, built from its current colour.
@MainActor
enum ColorPanelParts {
    /// One step: 0.01 (of saturation, brightness or opacity) or 1° of hue,
    /// ten times that with ⇧ (`LK-D` item 5).
    static func multiplier(_ modifiers: Modifiers) -> Double { modifiers.contains(.shift) ? 10 : 1 }

    static func percent(_ value: Double) -> String { "\(Int((ColorMath.clamp(value) * 100).rounded()))%" }

    static func degrees(_ hue: Double) -> String { "\(Int((hue * 360).rounded()) % 360)°" }

    /// The saturation–brightness square: x = saturation, y = brightness 1…0.
    static func square(_ panel: ColorPickerPanel, _ color: PanelColor) -> ColorPlane {
        var plane = ColorPlane(
            width: ColorPickerPanel.width, height: ColorPickerPanel.squareHeight,
            image: ColorPanelImages.square(hue: color.hsb.hue).texture, checker: false,
            marker: .ring(x: color.hsb.saturation, y: 1 - color.hsb.brightness),
            onKey: { event in
                let step = 0.01 * multiplier(event.modifiers)
                switch event.charactersIgnoringModifiers {
                case TextEditing.rightArrow: panel.adjust { $0.hsb.saturation += step }
                case TextEditing.leftArrow: panel.adjust { $0.hsb.saturation -= step }
                case TextEditing.upArrow: panel.adjust { $0.hsb.brightness += step }
                case TextEditing.downArrow: panel.adjust { $0.hsb.brightness -= step }
                default: return false
                }
                return true
            })
        plane.handlers.axNode.role = .container
        plane.handlers.axNode.label = "Saturation and brightness"
        plane.children = [
            ColorPlane.Child(label: "Saturation", value: percent(color.hsb.saturation), half: .top) { up in
                panel.adjust { $0.hsb.saturation += up ? 0.01 : -0.01 }
            },
            ColorPlane.Child(label: "Brightness", value: percent(color.hsb.brightness), half: .bottom) { up in
                panel.adjust { $0.hsb.brightness += up ? 0.01 : -0.01 }
            },
        ]
        return plane.gesture(DragGesture(minimumDistance: Pixels(0)).onChanged { value in
            let x = ColorMath.clamp(Double(value.location.x.value) / Double(ColorPickerPanel.width))
            let y = ColorMath.clamp(Double(value.location.y.value) / Double(ColorPickerPanel.squareHeight))
            panel.adjust {
                $0.hsb.saturation = x
                $0.hsb.brightness = 1 - y
            }
        })
    }

    /// The hue bar: hue 0…360° along x.
    static func hueBar(_ panel: ColorPickerPanel, _ color: PanelColor) -> ColorPlane {
        func turn(_ hue: Double) -> Double { hue - hue.rounded(.down) }
        var plane = ColorPlane(
            width: ColorPickerPanel.width, height: ColorPickerPanel.barHeight,
            image: ColorPanelImages.hueStrip.texture, checker: false, marker: .thumb(x: color.hsb.hue),
            onKey: { event in
                let step = multiplier(event.modifiers) / 360
                switch event.charactersIgnoringModifiers {
                case TextEditing.rightArrow: panel.adjust { $0.hsb.hue = turn($0.hsb.hue + step) }
                case TextEditing.leftArrow: panel.adjust { $0.hsb.hue = turn($0.hsb.hue - step) }
                default: return false
                }
                return true
            })
        plane.handlers.axNode.role = .slider
        plane.handlers.axNode.label = "Hue"
        plane.handlers.axNode.value = degrees(color.hsb.hue)
        plane.adjustment = { up in panel.adjust { $0.hsb.hue = turn($0.hsb.hue + (up ? 1 : -1) / 360) } }
        return plane.gesture(DragGesture(minimumDistance: Pixels(0)).onChanged { value in
            let x = ColorMath.clamp(Double(value.location.x.value) / Double(ColorPickerPanel.width))
            // The bar's right end is 360°, the same colour as 0°.
            panel.adjust { $0.hsb.hue = x >= 1 ? 0 : x }
        })
    }

    /// The opacity bar: the current colour from clear to opaque over a
    /// checkerboard.
    static func opacityBar(_ panel: ColorPickerPanel, _ color: PanelColor) -> ColorPlane {
        let rgb = color.rgba.rgb
        var plane = ColorPlane(
            width: ColorPickerPanel.width, height: ColorPickerPanel.barHeight,
            image: ColorPanelImages.opacityStrip(rgb).texture, checker: true, marker: .thumb(x: color.opacity),
            onKey: { event in
                let step = 0.01 * multiplier(event.modifiers)
                switch event.charactersIgnoringModifiers {
                case TextEditing.rightArrow: panel.adjust { $0.opacity += step }
                case TextEditing.leftArrow: panel.adjust { $0.opacity -= step }
                default: return false
                }
                return true
            })
        plane.handlers.axNode.role = .slider
        plane.handlers.axNode.label = "Opacity"
        plane.handlers.axNode.value = percent(color.opacity)
        plane.adjustment = { up in panel.adjust { $0.opacity += up ? 0.01 : -0.01 } }
        return plane.gesture(DragGesture(minimumDistance: Pixels(0)).onChanged { value in
            let x = ColorMath.clamp(Double(value.location.x.value) / Double(ColorPickerPanel.width))
            panel.adjust { $0.opacity = x }
        })
    }
}

/// One of the panel's planes — the square or a bar (`LK-D` items 1–3, 5, 7):
/// a fixed-size leaf drawing its CPU-made image (and a checkerboard under the
/// opacity bar) with its marker over it, focusable with its keys, its pointer
/// a `DragGesture(minimumDistance: 0)` attached by the panel. `Slider`'s shape:
/// `registerAndScope` in `prepaint`, `paintDecoration` in `paint`.
///
/// **The square's two accessibility children** (`LK-D` item 7) are
/// registrations of their own under positional child ids of the square — its
/// top and bottom halves, each an adjustable `.slider` with no hitbox and no
/// focus stop — so a client reads "Saturation" and "Brightness" under the
/// square's group and adjusts each, while Tab stops once at the square.
struct ColorPlane: Element, StyledElement {
    enum Marker {
        /// A 10-point ring at fractions of the plane.
        case ring(x: Double, y: Double)
        /// A full-height thumb at a fraction of the width.
        case thumb(x: Double)
    }

    /// An accessibility child of the square.
    struct Child {
        enum Half { case top, bottom }
        var label: String
        var value: String
        var half: Half
        var adjust: @MainActor (_ up: Bool) -> Void
    }

    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()
    let width: Float
    let height: Float
    let image: ImageTexture
    let checker: Bool
    let marker: Marker
    let onKey: @MainActor (KeyEvent) -> Bool
    /// The plane's own accessibility adjustment (a bar), up or down one step.
    var adjustment: (@MainActor (_ up: Bool) -> Void)?
    var children: [Child] = []

    init(width: Float, height: Float, image: ImageTexture, checker: Bool, marker: Marker,
         onKey: @escaping @MainActor (KeyEvent) -> Bool) {
        self.width = width
        self.height = height
        self.image = image
        self.checker = checker
        self.marker = marker
        self.onKey = onKey
    }

    struct Layout { var node: LayoutNodeID }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let size = SizeD(width: Double(width), height: Double(height))
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .colorPicker) {
            pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: size) }
        }
        return (node, Layout(node: node))
    }

    /// `adjust` as an `AccessibilityAdjustment` handler.
    private static func adjustmentHandler(_ adjust: @escaping @MainActor (Bool) -> Void) -> ActionHandler {
        { action in
            // The key is `AccessibilityAdjustment`'s, so the cast holds by
            // construction (`Box.onAction`'s reasoning).
            adjust((action as! AccessibilityAdjustment).direction == .increment)
        }
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) {
        var composed = handlers
        composed.isFocusable = true
        let callerKey = handlers.onKey, onKey = onKey
        composed.onKey = { event in
            if let callerKey, callerKey(event) { return true }
            return onKey(event)
        }
        let adjustmentKey = ObjectIdentifier(AccessibilityAdjustment.self)
        if let adjustment { composed.actions[adjustmentKey] = Self.adjustmentHandler(adjustment) }
        let children = children
        pass.registerAndScope(composed, decoration, at: bounds, for: id) {
            for (index, child) in children.enumerated() {
                var handlers = Handlers()
                handlers.axNode.role = .slider
                handlers.axNode.label = child.label
                handlers.axNode.value = child.value
                handlers.actions[adjustmentKey] = Self.adjustmentHandler(child.adjust)
                let half = Pixels(bounds.size.height.value / 2)
                let origin = Point(x: bounds.origin.x,
                                   y: child.half == .top ? bounds.origin.y : bounds.origin.y + half)
                pass.registerAndScope(handlers, Decoration(), at: Bounds(origin: origin, size: Size(width: bounds.size.width, height: half)),
                                      for: GlobalElementID.child(of: id, at: index, name: nil)) { }
            }
        }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                        prepaint: inout Void, pass: inout PaintPass) {
        var decorated = decoration
        if decorated.focusBorder == nil { decorated.focusBorder = controlRing(pass.frame.environmentTop) }
        let image = image, checker = checker, marker = marker
        pass.paintDecoration(decorated, in: bounds, for: id) {
            if checker {
                pass.drawImage(ColorPanelImages.checker(columns: 50, rows: 4).texture, in: bounds, filter: .nearest)
            }
            pass.drawImage(image, in: bounds, filter: .linear)
            pass.fill(bounds, color: .transparent, cornerRadii: Corners(all: Pixels(2)),
                      borderColor: pass.theme[.separator], borderWidths: Edges(all: Pixels(1)))
            ColorPanelDrawing.marker(marker, in: bounds, pass: pass)
        }
    }
}

/// The panel's and the well's small drawing helpers.
@MainActor
enum ColorPanelDrawing {
    /// `bounds` inset by `inset` on every edge.
    static func inset(_ bounds: Bounds<Pixels>, by inset: Float) -> Bounds<Pixels> {
        Bounds(origin: Point(x: Pixels(bounds.origin.x.value + inset), y: Pixels(bounds.origin.y.value + inset)),
               size: Size(width: Pixels(max(bounds.size.width.value - 2 * inset, 0)),
                          height: Pixels(max(bounds.size.height.value - 2 * inset, 0))))
    }

    /// A plane's marker: a white ring with a dark outline, or a white thumb.
    static func marker(_ marker: ColorPlane.Marker, in bounds: Bounds<Pixels>, pass: PaintPass) {
        let white = Hsla(h: 0, s: 0, l: 1, a: 1), shade = Hsla(h: 0, s: 0, l: 0, a: 0.5)
        switch marker {
        case let .ring(x, y):
            let cx = bounds.origin.x.value + Float(x) * bounds.size.width.value
            let cy = bounds.origin.y.value + Float(y) * bounds.size.height.value
            let ring = Bounds(origin: Point(x: Pixels(cx - 5), y: Pixels(cy - 5)),
                              size: Size(width: Pixels(10), height: Pixels(10)))
            pass.fill(ring, color: .transparent, cornerRadii: Corners(all: Pixels(5)),
                      borderColor: shade, borderWidths: Edges(all: Pixels(3)))
            pass.fill(inset(ring, by: 0.5), color: .transparent, cornerRadii: Corners(all: Pixels(4.5)),
                      borderColor: white, borderWidths: Edges(all: Pixels(1.5)))
        case let .thumb(x):
            let cx = bounds.origin.x.value + Float(ColorMath.clamp(x)) * bounds.size.width.value
            let thumb = Bounds(origin: Point(x: Pixels(cx - 3), y: Pixels(bounds.origin.y.value - 2)),
                               size: Size(width: Pixels(6), height: Pixels(bounds.size.height.value + 4)))
            pass.fill(thumb, color: white, cornerRadii: Corners(all: Pixels(2)),
                      borderColor: shade, borderWidths: Edges(all: Pixels(1)))
        }
    }
}

/// The panel's CPU-made images (`LK-D` item 2): no gradient primitive, no
/// shader change — `ImageBitmap`s drawn through the image pipeline. The square
/// is cached by hue and the opacity strip by colour (one entry each, the last
/// one asked for), the hue strip and the checkerboards once.
@MainActor
enum ColorPanelImages {
    /// The square's samples: 100 × 75, scaled to 200 × 150 with the linear filter.
    static let squareColumns = 100, squareRows = 75
    private static var lastSquare: (hue: Double, bitmap: ImageBitmap)?
    private static var lastOpacity: (rgb: ColorMath.RGB, bitmap: ImageBitmap)?
    private static var checkers: [Int: ImageBitmap] = [:]

    /// Saturation along x, brightness 1 → 0 down, at `hue`, sampled at pixel
    /// centres.
    static func square(hue: Double) -> ImageBitmap {
        if let lastSquare, lastSquare.hue == hue { return lastSquare.bitmap }
        var rgba = [UInt8]()
        rgba.reserveCapacity(squareColumns * squareRows * 4)
        for row in 0..<squareRows {
            let brightness = 1 - (Double(row) + 0.5) / Double(squareRows)
            for column in 0..<squareColumns {
                let saturation = (Double(column) + 0.5) / Double(squareColumns)
                let rgb = ColorMath.rgb(from: ColorMath.HSB(hue: hue, saturation: saturation, brightness: brightness))
                rgba += [UInt8(ColorMath.byte(rgb.red)), UInt8(ColorMath.byte(rgb.green)),
                         UInt8(ColorMath.byte(rgb.blue)), 255]
            }
        }
        let bitmap = ImageBitmap(width: squareColumns, height: squareRows, rgba: rgba)
        lastSquare = (hue, bitmap)
        return bitmap
    }

    /// Every hue at full saturation and brightness, 360 × 1.
    static let hueStrip: ImageBitmap = {
        var rgba = [UInt8]()
        for column in 0..<360 {
            let rgb = ColorMath.rgb(from: ColorMath.HSB(hue: (Double(column) + 0.5) / 360, saturation: 1, brightness: 1))
            rgba += [UInt8(ColorMath.byte(rgb.red)), UInt8(ColorMath.byte(rgb.green)),
                     UInt8(ColorMath.byte(rgb.blue)), 255]
        }
        return ImageBitmap(width: 360, height: 1, rgba: rgba)
    }()

    /// `rgb` from clear to opaque, 64 × 1, straight alpha.
    static func opacityStrip(_ rgb: ColorMath.RGB) -> ImageBitmap {
        if let lastOpacity, lastOpacity.rgb == rgb { return lastOpacity.bitmap }
        let bytes = [UInt8(ColorMath.byte(rgb.red)), UInt8(ColorMath.byte(rgb.green)), UInt8(ColorMath.byte(rgb.blue))]
        var rgba = [UInt8]()
        for column in 0..<64 {
            rgba += bytes + [UInt8(ColorMath.byte((Double(column) + 0.5) / 64))]
        }
        let bitmap = ImageBitmap(width: 64, height: 1, rgba: rgba)
        lastOpacity = (rgb, bitmap)
        return bitmap
    }

    /// A light/dark checkerboard of `columns × rows` cells, one texel each
    /// (drawn with the nearest filter).
    static func checker(columns: Int, rows: Int) -> ImageBitmap {
        let key = columns << 16 | rows
        if let cached = checkers[key] { return cached }
        var rgba = [UInt8]()
        for row in 0..<rows {
            for column in 0..<columns {
                let light: UInt8 = (row + column).isMultiple(of: 2) ? 255 : 204
                rgba += [light, light, light, 255]
            }
        }
        let bitmap = ImageBitmap(width: columns, height: rows, rgba: rgba)
        checkers[key] = bitmap
        return bitmap
    }
}

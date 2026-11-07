import MetalUICore
import MetalUILayout
import MetalUIScene

/// SwiftUI's `Image`, decorative, over pixels MetalUI holds (plan task 11,
/// part 2, rulings `TE-AL`, `TE-AQ` item 9).
///
/// `Image(decorative:scale:)` answers its **point size**, `pixels ÷ scale`, at
/// every proposal (probes I1, I9) until ``resizable()``, which answers the
/// proposal, a nil axis its point size (I2). Fit and fill are
/// `.scaledToFit()`/`.scaledToFill()`/`.aspectRatio(contentMode:)` over a
/// resizable image, which read its ideal ratio (`TE-AM`; I3–I5); a filling
/// image overflows its frame unless `.clipped()` (I10). It paints one textured
/// quad over its bounds through `PaintPass.drawImage` — both renderers draw it
/// (`TE-AF`) — bilinear by default and nearest for `.interpolation(.none)`
/// (I8, I11; `.high` is drawn bilinear, **divergence 93**).
///
/// A proposal leaf like `Rectangle`: it registers no hitbox, focus entry or
/// **accessibility record** (decorative, as its name says — a labelled image,
/// `init(_:scale:label:)`, records one, plan task 12 part 2), and snaps under
/// animation. ``init(systemName:)`` draws a platform symbol (record 230, `SymbolImage.swift`).
/// **Not offered** (spec §9): asset names, `Image(nsImage:)`, cap insets and tiling,
/// rendering modes of a bitmap (guard `anImageHasASystemNameButNoAssetInitialiser`).
public struct Image: ProposalElement {
    /// SwiftUI's four interpolation qualities. `.none` samples the nearest
    /// texel; `.low`, `.medium` and `.high` are bilinear, SwiftUI's own answer
    /// for the first two (I8, I11) and **divergence 93** for `.high` (880 px
    /// apart in SwiftUI).
    public enum Interpolation: Sendable, Hashable {
        case none, low, medium, high
    }

    /// What the image draws: pixels MetalUI holds, or a symbol of the platform's catalogue (`SYM-B`).
    enum Content {
        case bitmap(ImageBitmap, scale: Float)
        case symbol(name: String)
    }

    let content: Content
    /// `Image.symbolRenderingMode(_:)`, over the environment's mode (a symbol only).
    var symbolMode: SymbolRenderingMode?
    var isResizable = false
    var interpolationQuality: Interpolation = .low

    /// `scale` is `Frame.scaleFactor`'s type, `Float` (`TE-AQ` item 9); the
    /// oriented spelling is ``init(decorative:scale:orientation:)``. **A scale that is not finite and
    /// positive traps** (SA-J: the point size would be infinite or negative at
    /// every proposal).
    public init(decorative bitmap: ImageBitmap, scale: Float) {
        precondition(scale.isFinite && scale > 0,
                     "Image scale must be finite and positive (SA-J), got \(scale)")
        self.content = .bitmap(bitmap, scale: scale)
    }

    /// SwiftUI's `Image(_:scale:label:)`, with `ImageBitmap` for `CGImage` and
    /// `Float` for `CGFloat` (plan task 12 part 2, `IX-AB` item 3): an image an
    /// accessibility client reads as an `.image` labelled by `label`'s string
    /// (SwiftUI I1, I3). Otherwise exactly `init(decorative:scale:)`.
    public init(_ bitmap: ImageBitmap, scale: Float, label: Text) {
        self.init(decorative: bitmap, scale: scale)
        accessibilityLabelText = label.string
    }

    /// SwiftUI's `Image(decorative:scale:orientation:)`: the bitmap drawn turned by `orientation`
    /// (``ImageBitmap/oriented(_:)``; a rotated one lays out at the swapped size). **`orientation`
    /// has no default** (`IB-K`): a defaulted parameter would make `Image(decorative:scale:)`
    /// ambiguous with the unoriented init, which stays and draws stored pixels (divergence 435).
    public init(decorative bitmap: ImageBitmap, scale: Float, orientation: Orientation) {
        self.init(decorative: bitmap.oriented(orientation), scale: scale)
    }

    /// SwiftUI's `Image(_:scale:orientation:label:)`: a labelled image (as
    /// ``init(_:scale:label:)``) drawn turned by `orientation`; no default for `orientation` (`IB-K`).
    public init(_ bitmap: ImageBitmap, scale: Float, orientation: Orientation, label: Text) {
        self.init(bitmap.oriented(orientation), scale: scale, label: label)
    }

    /// `label`'s string for a labelled image; `nil` for a decorative one, which
    /// publishes nothing, even labelled or tapped (I2, I4, I5).
    var accessibilityLabelText: String?

    /// Whether this image was built `decorative:` — an accessibility modifier
    /// written over it publishes nothing (I4, `AccessibilityModifier`).
    var isDecorative: Bool {
        if case .symbol = content { return false }
        return accessibilityLabelText == nil
    }

    /// Answers the proposal instead of the point size; a nil axis still
    /// answers the point size (probe I2).
    public func resizable() -> Image {
        var copy = self
        copy.isResizable = true
        return copy
    }

    /// How a resized image samples: `.none` nearest, `.low`, `.medium` and the
    /// default bilinear; `.high` also draws bilinear (divergence 93, `TE-AL`).
    public func interpolation(_ interpolation: Interpolation) -> Image {
        var copy = self
        copy.interpolationQuality = interpolation
        return copy
    }

    /// The sampler `interpolationQuality` draws with.
    var filter: ImageFilter { interpolationQuality == .none ? .nearest : .linear }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let isResizable = isResizable
        switch content {
        case .bitmap(let bitmap, let scale):
            let width = Double(bitmap.width) / Double(scale)
            let height = Double(bitmap.height) / Double(scale)
            let node = pass.requestNativeLeaf { proposal in
                guard isResizable else { return LayoutMeasurement(size: SizeD(width: width, height: height)) }
                return LayoutMeasurement(size: SizeD(width: proposal.width ?? width,
                                                     height: proposal.height ?? height))
            }
            return (node, ())
        case .symbol(let name):
            // `SYM-D`: the symbol's own size (alignment-rect width, image height) and one baseline, or a 0 x 0 leaf
            // when the name is missing (probe S6). A resizable symbol answers its proposal as a bitmap does (S7).
            let plan = symbolPlan(for: name, in: pass.environment)
            let node = pass.requestNativeLeaf { proposal in
                guard let plan else { return LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
                let m = plan.metrics
                guard isResizable else {
                    return LayoutMeasurement(size: SizeD(width: m.width, height: m.height),
                                             firstBaseline: m.baseline, lastBaseline: m.baseline)
                }
                return LayoutMeasurement(size: SizeD(width: proposal.width ?? m.width, height: proposal.height ?? m.height))
            }
            return (node, ())
        }
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Void, pass: inout PrepaintPass) {
        if case .symbol(let name) = content {
            guard let plan = symbolPlan(for: name, in: pass.environment),
                  let label = symbolLabel(for: plan) else { return }
            pass.frame.recordAccessibility(text: nil, declared: AXNode(role: .image, label: label), at: bounds, id: id)
            return
        }
        guard let label = accessibilityLabelText else { return }
        pass.frame.recordAccessibility(text: nil, declared: AXNode(role: .image, label: label), at: bounds, id: id)
    }

    /// One quad over `bounds`, stretched — the texture's pixel size never
    /// enters here (`PaintPass.drawImage`). A symbol is rasterised for `bounds` at the frame's scale
    /// (`SymbolRasterCache`, `SYM-C`) in the foreground colour (`SYM-E`).
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        switch content {
        case .bitmap(let bitmap, _):
            pass.drawImage(bitmap.texture, in: bounds, filter: filter)
        case .symbol(let name):
            let environment = pass.environment
            guard let plan = symbolPlan(for: name, in: environment) else { return }
            let scale = Double(pass.scaleFactor)
            let width = Int((Double(bounds.size.width.value) * scale).rounded())
            let height = Int((Double(bounds.size.height.value) * scale).rounded())
            guard width > 0, height > 0 else { return }
            let (foreground, _) = resolveForeground(nil, in: environment)
            let rgba = pass.resolve(foreground).toRgba()
            guard let texture = SymbolBackend.texture(plan.spec, metrics: plan.metrics, mode: plan.mode, color: rgba,
                                                      pixelWidth: width, pixelHeight: height, stretched: isResizable,
                                                      deviceScale: pass.scaleFactor) else { return }
            pass.drawImage(texture, in: bounds, filter: .linear)
        }
    }
}

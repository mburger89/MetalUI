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
/// animation. **Not offered** (spec §9):
/// SF Symbols (`Image(systemName:)`, out of the task's scope), asset names,
/// `Image(nsImage:)`, `orientation:`, cap insets and tiling, rendering modes
/// (guard `anImageHasNoSystemNameOrAssetInitialiser`).
public struct Image: ProposalElement {
    /// SwiftUI's four interpolation qualities. `.none` samples the nearest
    /// texel; `.low`, `.medium` and `.high` are bilinear, SwiftUI's own answer
    /// for the first two (I8, I11) and **divergence 93** for `.high` (880 px
    /// apart in SwiftUI).
    public enum Interpolation: Sendable, Hashable {
        case none, low, medium, high
    }

    let bitmap: ImageBitmap
    let scale: Float
    var isResizable = false
    var interpolationQuality: Interpolation = .low

    /// `scale` is `Frame.scaleFactor`'s type, `Float` (`TE-AQ` item 9); SwiftUI's
    /// `orientation:` is not offered. **A scale that is not finite and
    /// positive traps** (SA-J: the point size would be infinite or negative at
    /// every proposal).
    public init(decorative bitmap: ImageBitmap, scale: Float) {
        precondition(scale.isFinite && scale > 0,
                     "Image scale must be finite and positive (SA-J), got \(scale)")
        self.bitmap = bitmap
        self.scale = scale
    }

    /// SwiftUI's `Image(_:scale:label:)`, with `ImageBitmap` for `CGImage` and
    /// `Float` for `CGFloat` (plan task 12 part 2, `IX-AB` item 3): an image an
    /// accessibility client reads as an `.image` labelled by `label`'s string
    /// (SwiftUI I1, I3). Otherwise exactly `init(decorative:scale:)`.
    public init(_ bitmap: ImageBitmap, scale: Float, label: Text) {
        self.init(decorative: bitmap, scale: scale)
        accessibilityLabelText = label.string
    }

    /// `label`'s string for a labelled image; `nil` for a decorative one, which
    /// publishes nothing, even labelled or tapped (I2, I4, I5).
    var accessibilityLabelText: String?

    /// Whether this image was built `decorative:` — an accessibility modifier
    /// written over it publishes nothing (I4, `AccessibilityModifier`).
    var isDecorative: Bool { accessibilityLabelText == nil }

    /// Answers the proposal instead of the point size; a nil axis still
    /// answers the point size (probe I2).
    public func resizable() -> Image {
        var copy = self
        copy.isResizable = true
        return copy
    }

    public func interpolation(_ interpolation: Interpolation) -> Image {
        var copy = self
        copy.interpolationQuality = interpolation
        return copy
    }

    /// The sampler `interpolationQuality` draws with.
    var filter: ImageFilter { interpolationQuality == .none ? .nearest : .linear }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let width = Double(bitmap.width) / Double(scale)
        let height = Double(bitmap.height) / Double(scale)
        let isResizable = isResizable
        let node = pass.requestNativeLeaf { proposal in
            guard isResizable else { return LayoutMeasurement(size: SizeD(width: width, height: height)) }
            return LayoutMeasurement(size: SizeD(width: proposal.width ?? width,
                                                 height: proposal.height ?? height))
        }
        return (node, ())
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Void, pass: inout PrepaintPass) {
        guard let label = accessibilityLabelText else { return }
        pass.frame.recordAccessibility(text: nil, declared: AXNode(role: .image, label: label), at: bounds, id: id)
    }

    /// One quad over `bounds`, stretched — the texture's pixel size never
    /// enters here (`PaintPass.drawImage`).
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        pass.drawImage(bitmap.texture, in: bounds, filter: filter)
    }
}

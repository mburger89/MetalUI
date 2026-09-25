import MetalUICore
import MetalUILayout

/// The native proposal-layout and paint modifiers currently supported by MetalUI.
///
/// This is intentionally a closed value set rather than a public protocol
/// whose requirements expose `LayoutNodeID`. A caller composes typed values;
/// only MetalUI translates their layout effects into native nodes during layout.
///
/// **`frame` and `flexibleFrame` are two cases, not one**, so that
/// `ModifiedContent(content:modifier:)` can no more combine a fixed and a
/// flexible frame dimension than the `frame` modifiers can: SwiftUI has no
/// spelling for the combination (ruling SA-K item 6).
public enum LayoutModifier: Sendable {
    /// SwiftUI's `frame(width:height:alignment:)`.
    case frame(width: Pixels? = nil, height: Pixels? = nil,
               alignment: ProposalAlignment = .center)
    /// SwiftUI's `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`.
    case flexibleFrame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil,
                       minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                       alignment: ProposalAlignment = .center)
    case padding(Edges<Pixels>)
    case fixedSize(horizontal: Bool = true, vertical: Bool = true)
    case aspectRatio(Double, contentMode: AspectRatioContentMode = .fit)
    case layoutPriority(Double)
    case background(ColorToken)
    case clip(cornerRadius: Pixels = Pixels(0))
    case border(ColorToken, width: Pixels, cornerRadius: Pixels = Pixels(0))
    case opacity(Float)
    case allowsHitTesting(Bool)
}

/// **The wrapper these modifiers build is `ModifiedContent<Content,
/// LayoutModifier>`** (`ModifiedContent.swift`), ONE flat chain since stage 11
/// (ruling `LR-FV`): every modifier below goes through
/// `ProposalElementGroup._wrapLayout(_:)`, which appends a layer to a chain
/// rather than nesting it — `Rectangle().padding(e).frame(width: w)` is
/// `ModifiedContent<Rectangle, LayoutModifier>`, where until stage 11 it was
/// `ModifiedContent<ModifiedContent<Rectangle>>`. Each modifier is still one
/// layer = one identity level, so every id path is unchanged.
extension ProposalElementGroup {
    /// Applies a native SwiftUI-style fixed outer frame. The same as
    /// `frame(width:height:alignment:)`; split from the flexible spelling for
    /// the same reason (ruling SA-K item 6).
    public func nativeFrame(width: Pixels? = nil, height: Pixels? = nil,
                            alignment: ProposalAlignment = .center) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.frame(width: width, height: height, alignment: alignment))
    }

    /// Applies a native SwiftUI-style flexible outer frame. The same as
    /// `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`.
    public func nativeFrame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil,
                            maxWidth: Pixels? = nil, minHeight: Pixels? = nil,
                            idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                            alignment: ProposalAlignment = .center) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(
            .flexibleFrame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
                           minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
                           alignment: alignment)
        )
    }

    /// Applies proposal-layout outer padding.
    public func padding(_ insets: Edges<Pixels>) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.padding(insets))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "padding")
    public func nativePadding(_ insets: Edges<Pixels>) -> ModifiedContent<ProposalBase, LayoutModifier> {
        padding(insets)
    }

    /// Requests proposal-layout fixed-size behaviour on either axis.
    public func fixedSize(horizontal: Bool = true, vertical: Bool = true)
        -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.fixedSize(horizontal: horizontal, vertical: vertical))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "fixedSize")
    public func nativeFixedSize(horizontal: Bool = true, vertical: Bool = true)
        -> ModifiedContent<ProposalBase, LayoutModifier> {
        fixedSize(horizontal: horizontal, vertical: vertical)
    }

    /// Paints a semantic token behind this native subtree without changing its
    /// proposal, measurement, or placement.
    public func background(_ token: ColorToken) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.background(token))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "background")
    public func nativeBackground(_ token: ColorToken) -> ModifiedContent<ProposalBase, LayoutModifier> {
        background(token)
    }

    /// Clips this native subtree to its resolved bounds.
    public func clip(cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.clip(cornerRadius: cornerRadius))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "clip")
    public func nativeClip(cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<ProposalBase, LayoutModifier> {
        clip(cornerRadius: cornerRadius)
    }

    /// Draws a border over this native subtree without changing its layout.
    public func border(_ token: ColorToken, width: Pixels,
                       cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.border(token, width: width, cornerRadius: cornerRadius))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "border")
    public func nativeBorder(_ token: ColorToken, width: Pixels,
                             cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<ProposalBase, LayoutModifier> {
        border(token, width: width, cornerRadius: cornerRadius)
    }

    /// Applies paint-only opacity to this proposal-layout subtree.
    public func opacity(_ value: Float) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.opacity(value))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "opacity")
    public func nativeOpacity(_ value: Float) -> ModifiedContent<ProposalBase, LayoutModifier> {
        opacity(value)
    }

    /// Controls whether pointer hit testing enters this proposal-layout subtree.
    /// Keyboard focus and key handlers remain available when it is disabled.
    public func allowsHitTesting(_ enabled: Bool) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.allowsHitTesting(enabled))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "allowsHitTesting")
    public func nativeAllowsHitTesting(_ enabled: Bool) -> ModifiedContent<ProposalBase, LayoutModifier> {
        allowsHitTesting(enabled)
    }

    /// Applies a SwiftUI-style fixed proposal-layout frame.
    ///
    /// The legacy CSS wrapper now takes the same parameters, in the same order,
    /// with the same defaults (plan task 4, ruling `FR-C`), so a call site ports
    /// between the paths by changing nothing but the element type. What is only
    /// available here is the **proposal**: this overload owns its child's
    /// measurement proposal as well as its resolved size and alignment, which is
    /// why the legacy lowering diverges in named places — a finite maximum
    /// clamps but never grows (`FR-E`), a single infinite maximum is inert
    /// (`FR-O`), and an oversized child is squeezed on one axis when the frame
    /// wraps several nodes (`FR-N`, closed for one node by `CN-N`) — and why
    /// `idealWidth`/`idealHeight` trapped there when the legacy engine laid the
    /// frame out (`FR-D`; since plan task 7's `LR-H` at registration, until stage
    /// 9 deleted that engine). A legacy frame lowered onto the kernel answers all
    /// of these as this overload does. Which overload a call
    /// resolves to is pinned by
    /// `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload`.
    ///
    /// **SwiftUI's two `frame` overloads, not one.** A fixed and a flexible
    /// dimension cannot be passed together, on one axis or across both,
    /// because SwiftUI has no overload that spells it (`extra argument
    /// 'minWidth' in call`; ruling SA-K item 6). Chain two frames instead.
    /// Pinned by the typecheck guard `aFixedAndAFlexibleFrameDimensionCannotBeCombined`.
    /// The kernel validates each dimension when the frame registers (ruling
    /// SA-J): a negative, NaN or infinite fixed dimension traps.
    public func frame(width: Pixels? = nil, height: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.frame(width: width, height: height, alignment: alignment))
    }

    /// Applies SwiftUI-style flexible proposal-layout frame constraints.
    ///
    /// The kernel validates the constraints when the frame registers (ruling
    /// SA-J): a NaN or +∞ minimum, a negative or NaN maximum, a negative, NaN
    /// or +∞ ideal, and min > ideal > max orderings trap; a negative minimum
    /// and an infinite maximum are accepted.
    public func frame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil,
                      maxWidth: Pixels? = nil, minHeight: Pixels? = nil,
                      idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(
            .flexibleFrame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
                           minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
                           alignment: alignment)
        )
    }

    /// SwiftUI's own rejection of an argument-less frame, verbatim (ruling
    /// FR-J).
    ///
    /// **This declaration is load-bearing even though `ProposalElementGroup`
    /// refines `ElementGroup`, which declares the same overload.** With only the
    /// `ElementGroup` one, `leaf.frame()` on a proposal element resolves to the
    /// all-defaulted `frame(width:height:alignment:)` above — more specialized,
    /// so it wins — and infers `ModifiedContent<Leaf>` with no deprecation
    /// diagnostic at all, which is `SA-N` item 9 surviving on the path that
    /// matters. Measured against a skeleton of the real protocol shape under
    /// `-swift-version 6`, and pinned by the typecheck fixture
    /// `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths`, which asserts the
    /// inferred type on **both** paths so deleting either declaration reddens it.
    @available(*, deprecated, message: "Please pass one or more parameters.")
    public func frame() -> Self { self }

    /// Constrains this proposal-layout subtree to a width-to-height ratio.
    ///
    /// Proposes a ratio-shaped size to the content — a two-axis proposal
    /// inscribed by `.fit` or circumscribed by `.fill`, one proposed axis
    /// determining the other, ∞ a concrete axis, nil×nil passed through — and
    /// answers the content's answer to it, as SwiftUI does (ruling CN-G): a
    /// fixed-size child keeps its own size, a child that takes the offer takes
    /// the ratio's shape. The modifier never read the legacy CSS
    /// `Style.aspectRatio` field, which stage 10 deleted (`LR-FM` item 1).
    ///
    /// **The kernel's rule, checked at construction** so the two layers cannot
    /// disagree (ruling SA-K item 4): the ratio must be finite and non-zero; a
    /// negative ratio is accepted, as SwiftUI accepts it (P8).
    public func aspectRatio(_ ratio: Double,
                            contentMode: AspectRatioContentMode = .fit) -> ModifiedContent<ProposalBase, LayoutModifier> {
        precondition(ratio.isFinite && ratio != 0,
                     "aspect ratio must be finite and non-zero (SA-J), got \(ratio)")
        return _wrapLayout(.aspectRatio(ratio, contentMode: contentMode))
    }

    /// Prioritizes this subtree when a native `HStack` or `VStack` must divide
    /// less main-axis space than its children request.
    ///
    /// **The kernel's rule, checked at construction** (ruling SA-K item 4): NaN
    /// traps, as SwiftUI hangs on it (P7); ±∞ is accepted and orders like any
    /// finite priority.
    public func layoutPriority(_ value: Double) -> ModifiedContent<ProposalBase, LayoutModifier> {
        precondition(!value.isNaN, "layout priority must not be NaN (SA-J)")
        return _wrapLayout(.layoutPriority(value))
    }
}

/// Temporary source-compatible name for ``LayoutModifier``.
@available(*, deprecated, renamed: "LayoutModifier")
public typealias NativeLayoutModifier = LayoutModifier

/// Temporary source-compatible name for ``ModifiedContent`` over the proposal
/// vocabulary, retargeted by stage 11 (ruling `LR-FV` item 8): the
/// one-argument spelling `ModifiedContent<C>` became
/// `ModifiedContent<C, LayoutModifier>`, and this alias spells that.
@available(*, deprecated, renamed: "ModifiedContent")
public typealias NativeModifiedContent<Content: ProposalElementGroup> = ModifiedContent<Content, LayoutModifier>

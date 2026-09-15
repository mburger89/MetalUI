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

/// A typed proposal-layout modifier wrapper, analogous to SwiftUI's `ModifiedContent`.
///
/// Each value owns one content subtree and one layout modifier. Chaining keeps
/// that structure concrete—`ModifiedContent<ModifiedContent<T>>`
/// rather than silently introducing `AnyElement`—so identity and phase order
/// remain observable and predictable.
public struct ModifiedContent<Content: ProposalElementGroup>: Element {
    public var content: Content
    public var modifier: LayoutModifier

    public init(content: Content, modifier: LayoutModifier) {
        self.content = content
        self.modifier = modifier
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor,
                                                                   pass: &pass)
        let node = nativeWrapperNode(for: children, pass: &pass)
        return (node, Layout(node: node, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        if case let .allowsHitTesting(enabled) = modifier {
            var result: Content.GroupPrepaint?
            pass.allowsHitTesting(enabled) {
                result = content.prepaintGroup(layout: &layout.content, pass: &pass)
            }
            return result!
        }
        if case let .clip(cornerRadius) = modifier {
            var result: Content.GroupPrepaint?
            pass.clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0)),
                         cornerRadii: Corners(all: cornerRadius)) {
                result = content.prepaintGroup(layout: &layout.content, pass: &pass)
            }
            return result!
        }
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        if case let .opacity(value) = modifier {
            pass.opacity(value) {
                content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
            }
            return
        }
        if case let .background(token) = modifier {
            pass.fill(bounds, color: pass.theme[token], cornerRadii: Corners(all: Pixels(0)))
        }
        if case let .clip(cornerRadius) = modifier {
            pass.clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0)),
                         cornerRadii: Corners(all: cornerRadius)) {
                content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
            }
        } else {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
        if case let .border(token, width, cornerRadius) = modifier {
            pass.fill(bounds, color: .transparent, cornerRadii: Corners(all: cornerRadius),
                      borderColor: pass.theme[token], borderWidths: Edges(all: width))
        }
    }

    private func nativeWrapperNode(for children: [LayoutNodeID], pass: inout LayoutPass) -> LayoutNodeID {
        precondition(children.count == 1,
                     "a native outer modifier must wrap exactly one native layout node")
        let child = children[0]
        switch modifier {
        case let .frame(width, height, alignment):
            return pass.requestNativeFrame(
                child: child,
                width: width.map { Double($0.value) }, height: height.map { Double($0.value) },
                alignment: alignment
            )
        case let .flexibleFrame(minWidth, idealWidth, maxWidth, minHeight, idealHeight, maxHeight, alignment):
            return pass.requestNativeFrame(
                child: child,
                minWidth: minWidth.map { Double($0.value) }, idealWidth: idealWidth.map { Double($0.value) },
                maxWidth: maxWidth.map { Double($0.value) },
                minHeight: minHeight.map { Double($0.value) }, idealHeight: idealHeight.map { Double($0.value) },
                maxHeight: maxHeight.map { Double($0.value) }, alignment: alignment
            )
        case let .padding(insets):
            return pass.requestNativePadding(
                child: child,
                insets: Edges(top: Double(insets.top.value), right: Double(insets.right.value),
                              bottom: Double(insets.bottom.value), left: Double(insets.left.value))
            )
        case let .fixedSize(horizontal, vertical):
            return pass.requestNativeFixedSize(child: child, horizontal: horizontal, vertical: vertical)
        case let .aspectRatio(ratio, contentMode):
            return pass.requestNativeAspectRatio(child: child, ratio: ratio, contentMode: contentMode)
        case let .layoutPriority(priority):
            return pass.requestNativeLayoutPriority(child: child, priority: priority)
        case .background:
            // A background has no independent layout footprint. Returning the
            // content node lets the wrapper observe its resolved bounds during
            // paint while preserving modifier nesting in the element tree.
            return child
        case .clip:
            return child
        case .border:
            return child
        case .opacity:
            return child
        case .allowsHitTesting:
            return child
        }
    }
}

extension ProposalElementGroup {
    /// Applies a native SwiftUI-style fixed outer frame. The same as
    /// `frame(width:height:alignment:)`; split from the flexible spelling for
    /// the same reason (ruling SA-K item 6).
    public func nativeFrame(width: Pixels? = nil, height: Pixels? = nil,
                            alignment: ProposalAlignment = .center) -> ModifiedContent<Self> {
        ModifiedContent(content: self, modifier: .frame(width: width, height: height, alignment: alignment))
    }

    /// Applies a native SwiftUI-style flexible outer frame. The same as
    /// `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`.
    public func nativeFrame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil,
                            maxWidth: Pixels? = nil, minHeight: Pixels? = nil,
                            idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                            alignment: ProposalAlignment = .center) -> ModifiedContent<Self> {
        ModifiedContent(
            content: self,
            modifier: .flexibleFrame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
                                     minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
                                     alignment: alignment)
        )
    }

    /// Applies proposal-layout outer padding.
    public func padding(_ insets: Edges<Pixels>) -> ModifiedContent<Self> {
        ModifiedContent(content: self, modifier: .padding(insets))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "padding")
    public func nativePadding(_ insets: Edges<Pixels>) -> ModifiedContent<Self> {
        padding(insets)
    }

    /// Requests proposal-layout fixed-size behaviour on either axis.
    public func fixedSize(horizontal: Bool = true, vertical: Bool = true)
        -> ModifiedContent<Self> {
        ModifiedContent(content: self, modifier: .fixedSize(horizontal: horizontal, vertical: vertical))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "fixedSize")
    public func nativeFixedSize(horizontal: Bool = true, vertical: Bool = true)
        -> ModifiedContent<Self> {
        fixedSize(horizontal: horizontal, vertical: vertical)
    }

    /// Paints a semantic token behind this native subtree without changing its
    /// proposal, measurement, or placement.
    public func background(_ token: ColorToken) -> ModifiedContent<Self> {
        ModifiedContent(content: self, modifier: .background(token))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "background")
    public func nativeBackground(_ token: ColorToken) -> ModifiedContent<Self> {
        background(token)
    }

    /// Clips this native subtree to its resolved bounds.
    public func clip(cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<Self> {
        ModifiedContent(content: self, modifier: .clip(cornerRadius: cornerRadius))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "clip")
    public func nativeClip(cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<Self> {
        clip(cornerRadius: cornerRadius)
    }

    /// Draws a border over this native subtree without changing its layout.
    public func border(_ token: ColorToken, width: Pixels,
                       cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<Self> {
        ModifiedContent(content: self,
                              modifier: .border(token, width: width, cornerRadius: cornerRadius))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "border")
    public func nativeBorder(_ token: ColorToken, width: Pixels,
                             cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<Self> {
        border(token, width: width, cornerRadius: cornerRadius)
    }

    /// Applies paint-only opacity to this proposal-layout subtree.
    public func opacity(_ value: Float) -> ModifiedContent<Self> {
        ModifiedContent(content: self, modifier: .opacity(value))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "opacity")
    public func nativeOpacity(_ value: Float) -> ModifiedContent<Self> {
        opacity(value)
    }

    /// Controls whether pointer hit testing enters this proposal-layout subtree.
    /// Keyboard focus and key handlers remain available when it is disabled.
    public func allowsHitTesting(_ enabled: Bool) -> ModifiedContent<Self> {
        ModifiedContent(content: self, modifier: .allowsHitTesting(enabled))
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "allowsHitTesting")
    public func nativeAllowsHitTesting(_ enabled: Bool) -> ModifiedContent<Self> {
        allowsHitTesting(enabled)
    }

    /// Applies a SwiftUI-style fixed proposal-layout frame.
    ///
    /// Unlike the legacy CSS wrapper with the same spelling, this overload is
    /// available only on a fully proposal-layout subtree and therefore owns
    /// its child's measurement proposal, resolved size, and alignment.
    ///
    /// **SwiftUI's two `frame` overloads, not one.** A fixed and a flexible
    /// dimension cannot be passed together, on one axis or across both,
    /// because SwiftUI has no overload that spells it (`extra argument
    /// 'minWidth' in call`; ruling SA-K item 6). Chain two frames instead.
    /// Pinned by the typecheck guard `aFixedAndAFlexibleFrameDimensionCannotBeCombined`.
    /// The kernel validates each dimension when the frame registers (ruling
    /// SA-J): a negative, NaN or infinite fixed dimension traps.
    public func frame(width: Pixels? = nil, height: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedContent<Self> {
        ModifiedContent(content: self, modifier: .frame(width: width, height: height, alignment: alignment))
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
                      alignment: ProposalAlignment = .center) -> ModifiedContent<Self> {
        ModifiedContent(
            content: self,
            modifier: .flexibleFrame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
                                     minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
                                     alignment: alignment)
        )
    }

    /// Constrains this proposal-layout subtree to a width-to-height ratio.
    ///
    /// A concrete parent proposal is inscribed by `.fit` or circumscribed by
    /// `.fill`; a single proposed axis determines the other. The modifier
    /// never reads the legacy CSS `Style.aspectRatio` field.
    ///
    /// **The kernel's rule, checked at construction** so the two layers cannot
    /// disagree (ruling SA-K item 4): the ratio must be finite and non-zero; a
    /// negative ratio is accepted, as SwiftUI accepts it (P8).
    public func aspectRatio(_ ratio: Double,
                            contentMode: AspectRatioContentMode = .fit) -> ModifiedContent<Self> {
        precondition(ratio.isFinite && ratio != 0,
                     "aspect ratio must be finite and non-zero (SA-J), got \(ratio)")
        return ModifiedContent(content: self, modifier: .aspectRatio(ratio, contentMode: contentMode))
    }

    /// Prioritizes this subtree when a native `HStack` or `VStack` must divide
    /// less main-axis space than its children request.
    ///
    /// **The kernel's rule, checked at construction** (ruling SA-K item 4): NaN
    /// traps, as SwiftUI hangs on it (P7); ±∞ is accepted and orders like any
    /// finite priority.
    public func layoutPriority(_ value: Double) -> ModifiedContent<Self> {
        precondition(!value.isNaN, "layout priority must not be NaN (SA-J)")
        return ModifiedContent(content: self, modifier: .layoutPriority(value))
    }
}

/// Temporary source-compatible name for ``LayoutModifier``.
@available(*, deprecated, renamed: "LayoutModifier")
public typealias NativeLayoutModifier = LayoutModifier

/// Temporary source-compatible name for ``ModifiedContent``.
@available(*, deprecated, renamed: "ModifiedContent")
public typealias NativeModifiedContent<Content: ProposalElementGroup> = ModifiedContent<Content>

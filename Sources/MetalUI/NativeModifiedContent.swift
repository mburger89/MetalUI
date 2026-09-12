import MetalUICore
import MetalUILayout

/// The native proposal-layout and paint modifiers currently supported by MetalUI.
///
/// This is intentionally a closed value set rather than a public protocol
/// whose requirements expose `LayoutNodeID`. A caller composes typed values;
/// only MetalUI translates their layout effects into native nodes during layout.
public enum NativeLayoutModifier: Sendable {
    case frame(width: Pixels? = nil, height: Pixels? = nil,
               minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil,
               minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
               alignment: NativeAlignment = .center)
    case padding(Edges<Pixels>)
    case fixedSize(horizontal: Bool = true, vertical: Bool = true)
    case background(ColorToken)
}

/// A typed native modifier wrapper, analogous to SwiftUI's `ModifiedContent`.
///
/// Each value owns one content subtree and one layout modifier. Chaining keeps
/// that structure concrete—`NativeModifiedContent<NativeModifiedContent<T>>`
/// rather than silently introducing `AnyElement`—so identity and phase order
/// remain observable and predictable.
public struct NativeModifiedContent<Content: ElementGroup>: Element {
    public var content: Content
    public var modifier: NativeLayoutModifier

    public init(content: Content, modifier: NativeLayoutModifier) {
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
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        if case let .background(token) = modifier {
            pass.fill(bounds, color: pass.theme[token], cornerRadii: Corners(all: Pixels(0)))
        }
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }

    private func nativeWrapperNode(for children: [LayoutNodeID], pass: inout LayoutPass) -> LayoutNodeID {
        precondition(children.count == 1,
                     "a native outer modifier must wrap exactly one native layout node")
        let child = children[0]
        switch modifier {
        case let .frame(width, height, minWidth, idealWidth, maxWidth,
                        minHeight, idealHeight, maxHeight, alignment):
            return pass.requestNativeFrame(
                child: child,
                width: width.map { Double($0.value) }, height: height.map { Double($0.value) },
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
        case .background:
            // A background has no independent layout footprint. Returning the
            // content node lets the wrapper observe its resolved bounds during
            // paint while preserving modifier nesting in the element tree.
            return child
        }
    }
}

extension ElementGroup {
    /// Applies a native SwiftUI-style outer frame.
    public func nativeFrame(width: Pixels? = nil, height: Pixels? = nil,
                            minWidth: Pixels? = nil, idealWidth: Pixels? = nil,
                            maxWidth: Pixels? = nil, minHeight: Pixels? = nil,
                            idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                            alignment: NativeAlignment = .center) -> NativeModifiedContent<Self> {
        NativeModifiedContent(
            content: self,
            modifier: .frame(width: width, height: height,
                             minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
                             minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
                             alignment: alignment)
        )
    }

    /// Applies native outer padding.
    public func nativePadding(_ insets: Edges<Pixels>) -> NativeModifiedContent<Self> {
        NativeModifiedContent(content: self, modifier: .padding(insets))
    }

    /// Requests native fixed-size behaviour on either axis.
    public func nativeFixedSize(horizontal: Bool = true, vertical: Bool = true)
        -> NativeModifiedContent<Self> {
        NativeModifiedContent(content: self, modifier: .fixedSize(horizontal: horizontal, vertical: vertical))
    }

    /// Paints a semantic token behind this native subtree without changing its
    /// proposal, measurement, or placement.
    public func nativeBackground(_ token: ColorToken) -> NativeModifiedContent<Self> {
        NativeModifiedContent(content: self, modifier: .background(token))
    }
}

import MetalUICore
import MetalUILayout

/// A SwiftUI-style layout wrapper.
///
/// Unlike `width(_:)` and `height(_:)`, which amend an existing element's
/// border-box style, `frame(width:height:)` introduces an outer layout node.
/// That distinction is observable for a component: the frame constrains and
/// positions the component's body without overwriting the sizes its author
/// declared on the body's individual elements.
///
/// The wrapper uses the framework's normal `Box` machinery rather than a
/// second layout implementation. Its children are centred on both axes, which
/// is SwiftUI's default frame alignment. Passing `nil` leaves that axis
/// unconstrained.
extension ElementGroup {
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> Box<Self> {
        var wrapper = Box(content: self)
        wrapper.style.alignItems = .center
        wrapper.style.justifyContent = .center

        if let width {
            wrapper.style.size.width = .length(.pixels(width))
        }
        if let height {
            wrapper.style.size.height = .length(.pixels(height))
        }
        return wrapper
    }
}

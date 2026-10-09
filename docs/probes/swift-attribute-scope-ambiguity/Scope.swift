// The module half of run.sh: an attribute scope declared the way MetalUI's
// would be, in a module that imports AppKit internally (as `Sources/MetalUI`'s
// App.swift does). `PER_KEY` adds one non-generic dynamic-member subscript for
// the colour key beside the generic one.
@_exported import Foundation
import AppKit
public struct MColor: Hashable, Sendable { public var r: Double; public static let red = MColor(r: 1) }
extension AttributeScopes {
    public struct MetalUIAttributes: AttributeScope {
        public let foregroundColor: ForegroundColorAttribute
        public let foundation: AttributeScopes.FoundationAttributes
        public enum ForegroundColorAttribute: AttributedStringKey {
            public typealias Value = MColor
            public static let name = "MetalUI.foregroundColor"
        }
    }
}
extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, T>) -> T {
        self[T.self]
    }
#if PER_KEY
    public subscript(dynamicMember keyPath: KeyPath<AttributeScopes.MetalUIAttributes, AttributeScopes.MetalUIAttributes.ForegroundColorAttribute>) -> AttributeScopes.MetalUIAttributes.ForegroundColorAttribute {
        self[AttributeScopes.MetalUIAttributes.ForegroundColorAttribute.self]
    }
#endif
}

import MetalUICore

/// The role synthesized accessibility metadata assigns to an element — spec
/// §9's "role" field, given a concrete enumeration.
///
/// **Deliberately small.** This task builds the shape `AXNode` carries, not the
/// full role vocabulary a platform bridge would eventually need; `.generic` is
/// what an element that declares nothing gets, and it is what makes an
/// undeclared `AXNode` compare equal to `AXNode()` (see `AXNode.isEmpty`).
public enum AXRole: Equatable, Sendable {
    case generic
    case button
    case text
    case image
    case container
}

/// One descriptive trait an accessibility client can read off a node — spec
/// §9's "traits" field, one case per trait rather than a single flag, on
/// `Handlers`' own precedent (`isFocusable`/`onKey` are two separate asks
/// because one flag could not tell them apart).
public enum AXTrait: Equatable, Hashable, Sendable {
    case selected
    case disabled
    case updatesFrequently
}

/// One action an accessibility client may invoke on a node — spec §9's
/// "actions" field.
///
/// **Descriptive only, and that is deliberate.** This carries no closure: a
/// node says which actions it supports, not how to run them. Wiring an
/// invocation back to a live handler — most naturally the same `Handlers`
/// dictionary `onAction(_:_:)` already writes — is the platform bridge's job
/// (design spec §9, "Bridge"), which this task's brief puts out of scope. That
/// keeps `AXNode` free of escaping closures, so it stays `Equatable` and needs
/// no `HandlerShape`-style projection of its own.
public enum AXActionKind: Equatable, Hashable, Sendable {
    case activate
    case increment
    case decrement
}

/// A node in the accessibility tree MetalUI synthesizes for what it draws —
/// design spec §9's list, "taken as given" by this task's brief: role, label,
/// value, traits, actions, frame, and ordered children.
///
/// **One type, two lifetimes.** The same `AXNode` value is used both as
/// *declared* data — what `Handlers.axNode` carries between the moment a
/// caller sets it and the moment an element's `prepaint` runs — and as the
/// *emitted* record `Frame.axNodes` stores. `frame` and `children` are
/// meaningless on the declared half (an element does not know its own resolved
/// bounds or its children's ids until prepaint), so they default to zero and
/// empty; `PrepaintPass.emitAXNode(_:at:id:children:)` is what fills them in,
/// on the way into `Frame.axNodes`, on `PrepaintPass.insertHitbox`'s footing —
/// prepaint is the only phase where positions have resolved and nothing has
/// been emitted yet.
///
/// **Identity is not a stored field.** Spec §9 derives it from
/// `GlobalElementID`, and every call site already has one — `emitAXNode`
/// takes it as a parameter, the same way `insertHitbox` and `registerHandlers`
/// do, rather than storing it a second time inside the value it keys.
public struct AXNode: Equatable {
    public var role: AXRole
    public var label: String?
    public var value: String?
    public var traits: Set<AXTrait>
    public var actions: Set<AXActionKind>

    /// The resolved bounds, absolute to the root — meaningless until
    /// `emitAXNode` fills it in from `prepaint`'s own resolved geometry.
    public var frame: Bounds<Pixels>

    /// This node's children, in declaration order, by their own
    /// `GlobalElementID` — meaningless until `emitAXNode` fills it in. A
    /// consumer looks each one up in `Frame.axNodes` to walk the tree, which
    /// is what keeps this array from duplicating the child records themselves.
    public var children: [GlobalElementID]

    public init(role: AXRole = .generic, label: String? = nil, value: String? = nil,
                traits: Set<AXTrait> = [], actions: Set<AXActionKind> = [],
                frame: Bounds<Pixels> = Bounds(origin: Point(x: .zero, y: .zero),
                                               size: Size(width: .zero, height: .zero)),
                children: [GlobalElementID] = []) {
        self.role = role
        self.label = label
        self.value = value
        self.traits = traits
        self.actions = actions
        self.frame = frame
        self.children = children
    }

    /// Whether this is the value an element gets by declaring nothing —
    /// `Handlers`' own "empty means not a hit target" rule, one type over. A
    /// `Box` whose `handlers.axNode` is still this value emits no `AXNode` at
    /// all; see `Box.prepaint`.
    public var isEmpty: Bool { self == AXNode() }
}

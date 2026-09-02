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
/// **One type, two lifetimes, and the second is not reachable from the
/// public API.** The same `AXNode` value is used both as *declared* data —
/// what `Handlers.axNode` carries between the moment a caller sets it and the
/// moment an element's `prepaint` runs — and as the *emitted* record
/// `Frame.axNodes` stores. `frame` and `children` are meaningless on the
/// declared half (an element does not know its own resolved bounds or its
/// children's ids until prepaint), so they are `internal(set)`: a caller
/// outside this module can read them but cannot write them, at construction
/// or afterwards — the public initializer below does not even accept them as
/// parameters. `PrepaintPass.emitAXNode(_:at:id:children:)` is the one place
/// that fills them in, on the way into `Frame.axNodes`, on
/// `PrepaintPass.insertHitbox`'s footing — prepaint is the only phase where
/// positions have resolved and nothing has been emitted yet.
///
/// **This is a fix, not the original shape.** The first version of this type
/// left both fields `public var`, reachable through the public initializer —
/// a caller could write `AXNode(role: .button, frame: someRect)`, or set
/// `.frame` after construction, and get a positioned-but-otherwise-empty node
/// through `isEmpty`'s gate below with no diagnostic. Review caught it with a
/// two-line probe: `var n = AXNode(); n.frame = someNonZeroRect;
/// #expect(!n.isEmpty)` passed. `internal(set)` closes it at the type level
/// rather than by widening `isEmpty`'s comparison — Tasks 6 and 7 extend this
/// type, and a caller-reachable footgun is cheaper to remove now than after
/// two more tasks build on the shape.
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

    /// The resolved bounds, absolute to the root — meaningless, and fixed at
    /// zero, until `emitAXNode` fills it in from `prepaint`'s own resolved
    /// geometry. Settable only from inside this module; see this type's own
    /// doc.
    public internal(set) var frame: Bounds<Pixels> = Bounds(
        origin: Point(x: .zero, y: .zero), size: Size(width: .zero, height: .zero))

    /// This node's children, in declaration order, by their own
    /// `GlobalElementID` — meaningless, and fixed at `[]`, until `emitAXNode`
    /// fills it in. A consumer looks each one up in `Frame.axNodes` to walk
    /// the tree, which is what keeps this array from duplicating the child
    /// records themselves. Settable only from inside this module.
    public internal(set) var children: [GlobalElementID] = []

    /// No `frame:`/`children:` parameters, deliberately — see this type's own
    /// doc on why a caller cannot supply either.
    public init(role: AXRole = .generic, label: String? = nil, value: String? = nil,
                traits: Set<AXTrait> = [], actions: Set<AXActionKind> = []) {
        self.role = role
        self.label = label
        self.value = value
        self.traits = traits
        self.actions = actions
    }

    /// Whether this is the value an element gets by declaring nothing —
    /// `Handlers`' own "empty means not a hit target" rule, one type over. A
    /// `Box` whose `handlers.axNode` is still this value emits no `AXNode` at
    /// all; see `Box.prepaint`.
    ///
    /// **Safe to compare as a whole value BECAUSE `frame`/`children` cannot
    /// vary on a declared value** — `internal(set)` is what makes that true
    /// rather than this property scoping itself to the five declarable
    /// fields by hand. A resolved value read back out of `Frame.axNodes` is
    /// never checked with this — `Box.prepaint` calls it only on the declared
    /// `handlers.axNode`, before emission.
    public var isEmpty: Bool { self == AXNode() }
}

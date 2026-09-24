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
    /// An editable line of text — `TextField` (ruling TI-C).
    case textField
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

    /// The full count a virtualized container represents — spec §9's "3 of
    /// 500", the 500 half. `nil` for an ordinary node; a `List` sets it to
    /// `data.count` on its own emitted node regardless of how many rows are
    /// actually realized this frame (Task 7, `List.requestLayout`).
    ///
    /// **A normal declared field, on `role`/`label`'s footing — NOT
    /// `frame`/`children`/`isValid`'s.** Those three are `internal(set)`
    /// because `emitAXNode` overwrites them unconditionally from its own
    /// parameters, discarding whatever a declared value carried (see this
    /// type's own doc above). `logicalCount` is never touched by
    /// `emitAXNode` — it flows straight through from whatever the caller set,
    /// exactly as `role` and `label` do. Keeping it `public var` and on the
    /// public initializer is what lets an author of a *custom* virtualized
    /// element (not `List`) declare their own count the same way `List` does
    /// internally; making it `internal(set)` would block every caller outside
    /// this module from ever setting it, which is the wrong shape for data
    /// nobody but the declarer can supply.
    public var logicalCount: Int?

    /// A realized row's index in its virtualized container's logical sequence —
    /// spec §9's "3 of 500", the 3 half (ruling AB-L).
    ///
    /// **A hint, never a declaration, and internal.** `List` sets it on each row
    /// it realizes, and only while a client is active and its window is bounded
    /// (AB-X). `Frame.registerHandlers` strips it before `isEmpty`'s gate, so a
    /// row hint never emits into `Frame.axNodes` and never writes a `$ax` slot
    /// (AB-U); it reaches a client only through the frame's accessibility
    /// record, where `AccessibilityTreeBuilder` maps it to `.row`. Not on the
    /// public initializer and not `public`, so a third-party virtualized
    /// container cannot publish row indices (AB-Q item 10).
    var logicalIndex: Int?

    /// The resolved bounds, absolute to the root — meaningless, and fixed at
    /// zero, until `emitAXNode` fills it in from `prepaint`'s own resolved
    /// geometry. Settable only from inside this module; see this type's own
    /// doc.
    public internal(set) var frame: Bounds<Pixels> = Bounds(
        origin: Point(x: .zero, y: .zero), size: Size(width: .zero, height: .zero))

    /// This node's children, in declaration order, by their own
    /// `GlobalElementID` — meant to let a consumer look each one up in
    /// `Frame.axNodes` to walk the tree, without this array duplicating the
    /// child records themselves. Settable only from inside this module.
    ///
    /// **In production this is ALWAYS `[]`, and no caller fills it in — a
    /// correction of what this doc used to say (Task 7's review).** The
    /// earlier wording read as though `emitAXNode` populates this from real
    /// child ids; it does not, because nothing ever hands it any. The one
    /// production caller, `Frame.registerHandlers` (reached from `Box`, `Stack` and
    /// `Text`'s `prepaint`), always passes `children: []` (see
    /// its own doc), and the reason is not an oversight left for `emitAXNode`
    /// to close: `ElementGroup.requestGroupLayout` hands a container a flat
    /// `[LayoutNodeID]` rather than a `GlobalElementID` per child, so a
    /// container has no ids to pass in the first place. Reconstructing order
    /// from `Frame.axNodes`' own keys does not work either — Task 5's review
    /// found it provably ambiguous: `GlobalElementID.child(of:at:name:)` is
    /// `name.map(PathComponent.named) ?? .positional(index)`, so the index is
    /// discarded whenever a name is given, and two containers with the same
    /// named children in opposite declaration orders produce an identical set
    /// of ids — there is no order left to recover. Closing this needs an
    /// `ElementGroup` associated-type change (an API that hands back ids
    /// alongside layout nodes), which is out of this milestone's scope; see
    /// `List`'s own type doc for the consequence this leaves for `List`
    /// specifically, and Task 7's report for the measurement (a production
    /// 500-row `List` emits exactly one `AXNode`, its own container, with
    /// zero row nodes and `children.count == 0`, whether or not the rows
    /// carry `onClick`).
    public internal(set) var children: [GlobalElementID] = []

    /// Whether this node was produced by the last **completed** frame —
    /// design spec §9's requirement that a handle an AX client still holds
    /// reports itself **invalid** once its element stops being produced,
    /// rather than vanishing or dangling. Meaningless, and fixed at `true`,
    /// on every value this type has carried until now: an `AXNode` fresh out
    /// of `Frame.axNodes` for the frame that emitted it was, by construction,
    /// just produced, and a declared value (`Handlers.axNode`, before
    /// emission) has no notion of validity yet either. `Frame.axNode(for:)`
    /// is the one reader that can make this `false` — a durable lookup,
    /// separate from `Frame.axNodes`, that resolves against
    /// `StateTable.isLive` rather than a second liveness notion of its own.
    /// See that method's own doc for the mechanism, and `AXNodeTests.swift`
    /// for the two-sided pin (a node still being produced reports valid; one
    /// that stopped reports invalid, without vanishing).
    ///
    /// **Not the same question as "is this node current right now", and the
    /// gap is a full frame, one-directional.** `StateTable.isLive` answers as
    /// of the last `sweep()`, which runs at the END of a frame
    /// (`Frame.render`) — so an element that vanishes *during* a frame (its
    /// `prepaint` simply does not run this time) still reads `isValid == true`
    /// for the whole of that frame, because nothing has swept yet to notice.
    /// The next frame's sweep is what flips it. This is a **read lag, not a
    /// wrong answer that self-corrects wrong**: it can only ever report valid
    /// one frame too long, never invalid too early, and it converges within
    /// one frame. See `Frame.axNode(for:)`'s own doc for the measured
    /// timeline and why this is documented rather than fixed.
    public internal(set) var isValid: Bool = true

    /// No `frame:`/`children:`/`isValid:` parameters, deliberately — see this
    /// type's own doc on why a caller cannot supply any of the three.
    /// `logicalCount` IS a parameter here, on `role`/`label`'s footing rather
    /// than theirs — see its own doc above.
    public init(role: AXRole = .generic, label: String? = nil, value: String? = nil,
                traits: Set<AXTrait> = [], actions: Set<AXActionKind> = [],
                logicalCount: Int? = nil) {
        self.role = role
        self.label = label
        self.value = value
        self.traits = traits
        self.actions = actions
        self.logicalCount = logicalCount
    }

    /// Whether this is the value an element gets by declaring nothing —
    /// `Handlers`' own "empty means not a hit target" rule, one type over. A
    /// `Box` whose `handlers.axNode` is still this value emits no `AXNode` at
    /// all; see `Frame.registerHandlers`.
    ///
    /// **Safe to compare as a whole value BECAUSE `frame`/`children`/`isValid`
    /// cannot vary on a declared value** — `internal(set)` is what makes that
    /// true rather than this property scoping itself to the six declarable
    /// fields by hand. A resolved value read back out of `Frame.axNodes` or
    /// `Frame.axNode(for:)` is never checked with this — `Frame.registerHandlers` calls
    /// it only on the declared `handlers.axNode`, before emission.
    public var isEmpty: Bool { self == AXNode() }
}

import MetalUICore
import MetalUIPlatform

/// What an element's `onKey(_:)` runs, and what its answer means.
///
/// `true` claims the event: the walk stops there and nothing above it — no
/// ancestor, and not `Window.onInput` — sees the keystroke. `false` means "not
/// mine", and the event continues outward. That is the whole of the bubbling
/// contract, and it is a `Bool` rather than a `Void` precisely so an element can
/// look at a key and decline it without having to know what else is bound.
public typealias KeyHandler = @MainActor (KeyEvent) -> Bool

/// What each element asked for on the keyboard side, this frame — design spec
/// §4.2's "focus is a tree registered in prepaint".
///
/// **It is not a tree, and that is the point (and a ruling).** A
/// `GlobalElementID` is already a persistent linked list with a parent pointer,
/// so an element's ancestors are derivable from its id alone. Building a second
/// containment structure here would mean registering parenthood, keeping it in
/// sync with an identity that already encodes it, and paying for both. So this
/// records only **which ids asked for what**, and `focusChain(from:)` supplies
/// the shape by walking the id.
///
/// **Two members rather than one, because focusability and key handling are
/// separable** — see `Handlers.onKey`. An ancestor handles keys without being
/// focusable (a container binding a shortcut for its whole subtree); a text
/// field is focusable before anything is bound to it. A single "is interactive"
/// set could express neither.
///
/// Rebuilt from scratch every frame, exactly like `Frame.hitboxes` and the
/// `LayoutTree` — which is what makes "was the focused element produced this
/// frame" answerable at all (see `Frame.resolveFocus()`).
struct FocusRegistry {
    /// Every id that declared `.focusable()` this frame. Membership is what
    /// lets an id **hold** focus: `resolveFocus` clears a focused id that is
    /// not in here.
    private var focusable: Set<GlobalElementID> = []

    /// Every id that bound a key handler this frame, and what it bound.
    ///
    /// A dictionary rather than an array, because the only question asked of it
    /// is "does *this* id have one", once per level of the focus chain.
    private var keyHandlers: [GlobalElementID: KeyHandler] = [:]

    /// Every id that registered an action handler this frame, and for which
    /// action types — design spec §4.1's dispatch by type identity.
    ///
    /// Nested dictionaries rather than a flat `[Pair: Handler]`, because the
    /// question dispatch asks is "does *this* id handle *this* type", once per
    /// chain level, and the outer lookup is the one that usually misses.
    private var actionHandlers: [GlobalElementID: [ObjectIdentifier: ActionHandler]] = [:]

    /// The key context each id contributed this frame — framework spec §8.3's
    /// context stack, recorded flat and given its shape by the focus chain.
    ///
    /// **Keyed by id and not accumulated here**, for `focusChain(from:)`'s
    /// reason: the nesting is already encoded in `GlobalElementID`'s parent
    /// chain, so a stack assembled at registration time would be a second copy
    /// of a structure that already exists — and a wrong one, since prepaint
    /// order is not the focus chain.
    private var contexts: [GlobalElementID: KeyContext] = [:]
    private var textTargets: [GlobalElementID: TextInputTarget] = [:]

    /// Records whatever `handlers` asked for on the keyboard side, and nothing
    /// at all when it asked for neither.
    ///
    /// **The early return IS purely an optimisation, and it is worth saying so
    /// rather than dressing it up.** An earlier version of this comment claimed
    /// the opposite — that without it the registry would grow an entry per
    /// element per frame — and that is false: `isKeyTarget` is
    /// `onKey != nil || isFocusable`, so when it is false both `if`s below are
    /// false too and nothing is added either way. Measured: delete the guard and
    /// the registry is **byte-identical** and the suite stays green.
    ///
    /// What it buys is **cost**, and the cost is not small in aggregate: every
    /// element in the tree reaches this through its `prepaint`, and the
    /// overwhelming majority of them want nothing on the keyboard side, so this
    /// is one comparison instead of two on every node of every frame.
    ///
    /// **That also explains why no test guards it, which is the useful half.**
    /// A behaviourally inert line cannot be pinned by a behavioural assertion —
    /// mutating it away reddens nothing, correctly (a broken instrument rather
    /// than a coverage gap, in `docs/practices/verifying-tests-can-fail.md`'s
    /// terms). Do not "close" that with a test; there is nothing for one to
    /// see.
    mutating func register(_ handlers: Handlers, id: GlobalElementID) {
        guard handlers.isKeyTarget else { return }
        if handlers.isFocusable { focusable.insert(id) }
        if let onKey = handlers.onKey { keyHandlers[id] = onKey }
        if !handlers.actions.isEmpty { actionHandlers[id] = handlers.actions }
        if let context = handlers.keyContext { contexts[id] = context }
        if let target = handlers.textInput { textTargets[id] = target }
    }

    /// Whether `id` declared itself focusable this frame.
    func isFocusable(_ id: GlobalElementID) -> Bool { focusable.contains(id) }

    /// `id`'s key handler this frame, or `nil` — the lookup `dispatchKey` makes
    /// at each level of the chain.
    func handler(for id: GlobalElementID) -> KeyHandler? { keyHandlers[id] }

    /// `id`'s handler for one action type this frame, or `nil` — the lookup
    /// `dispatchAction` makes at each level of the chain.
    func actionHandler(for id: GlobalElementID,
                       type: ObjectIdentifier) -> ActionHandler? {
        actionHandlers[id]?[type]
    }

    /// The key context `id` contributed this frame, or `nil`.
    func context(for id: GlobalElementID) -> KeyContext? { contexts[id] }
    /// The text field registered under `id` this frame (ruling TI-B).
    func textTarget(for id: GlobalElementID) -> TextInputTarget? { textTargets[id] }

    /// How many ids declared themselves focusable — test observability, and the
    /// only way to assert that registration happened for an element that binds
    /// no key handler.
    var focusableCount: Int { focusable.count }
}

/// The focused element's id and every ancestor of it, **innermost first** —
/// `[focused, its parent, …, the root]`, and empty when nothing is focused.
///
/// **Derived from the id, not from a registry.** `GlobalElementID` is a
/// persistent linked list of `PathComponent` with a parent pointer, so this is a
/// walk of a structure that already exists rather than a lookup into one this
/// milestone built. Nothing has to be kept in sync, and an id that no longer
/// corresponds to a produced element still yields its ancestors (which is
/// harmless: `dispatchKey` finds no handler for any of them).
///
/// **Innermost first is the order §4.3 requires**, and it is why this is a
/// function of its own rather than a loop inside `dispatchKey`. Task 10 matches
/// context predicates against this chain and calls no handler at all, so the
/// chain has to be reachable without going through dispatch.
///
/// A `@State` slot id cannot appear here. Slots are children of their element
/// (`.child(of: elementID, at: n, name: "$state\(n)")`), so they hang *below* an
/// element and never sit on the path from one up to the root.
func focusChain(from id: GlobalElementID?) -> [GlobalElementID] {
    var chain: [GlobalElementID] = []
    var cursor = id
    while let node = cursor {
        chain.append(node)
        cursor = node.parent
    }
    return chain
}

/// Runs the first handler along `chain` that claims `event`, and reports
/// whether one did.
///
/// **Innermost first**, because `chain` is: the focused element gets the first
/// look and each ancestor the next, which is what "bubbling" means and is the
/// opposite of the capture phase design spec §3.5 deliberately cuts.
///
/// A free function over an explicit chain and registry, rather than a method on
/// `Window`, for `topmostOpaqueHitbox(in:at:)`'s reason: the ranking rule is the
/// interesting part and a test should be able to drive it without building a
/// window, a device and a frame.
@MainActor
func dispatchKey(_ event: KeyEvent, along chain: [GlobalElementID],
                 in registry: FocusRegistry) -> Bool {
    for id in chain {
        guard let handler = registry.handler(for: id) else { continue }
        if handler(event) { return true }
    }
    return false
}

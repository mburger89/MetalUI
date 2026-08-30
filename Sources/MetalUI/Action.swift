import MetalUICore

/// A command, identified by its **type** rather than by a string (framework
/// spec §8.3, design spec §4.1).
///
/// ```swift
/// struct Increment: Action {}
/// struct MoveCursor: Action { var direction: Direction }
/// ```
///
/// **Type identity is the whole point.** A keymap binds a keystroke to an
/// action *value*, an element registers a handler for an action *type*, and
/// dispatch matches the two by `ObjectIdentifier`. A typo in an action name is
/// therefore a compile error, where a string-keyed command system gives a
/// silent no-op — this repo's most-recorded bug shape.
///
/// **An action carries its payload**, which is why it is a protocol over
/// values rather than a marker on a type: `MoveCursor(direction: .left)` and
/// `MoveCursor(direction: .right)` are the same binding target and different
/// values, and the handler receives the value.
public protocol Action {}

/// What an element's `onAction(_:_:)` runs.
///
/// **Returns `Void`, unlike `KeyHandler`'s `Bool`, and the asymmetry is
/// deliberate.** A raw key handler sees *every* keystroke that reaches it, so
/// it must be able to look at one and decline; an action handler is registered
/// against a single action type and sees nothing else, so there is nothing for
/// it to decline. Registration is the claim: the action stops at the first
/// element along the focus chain that registered for its type.
public typealias ActionHandler = @MainActor (any Action) -> Void

/// Runs the first handler along `chain` registered for `action`'s **type**, and
/// reports whether one existed.
///
/// **Innermost first**, because `chain` is — the same walk `dispatchKey` makes
/// and deliberately a *separate* one: a keystroke that a keymap resolved to an
/// action dispatches by type, and a keystroke nothing was bound to dispatches
/// raw. Collapsing the two would make a raw handler see bound keystrokes, or an
/// action handler see unbound ones.
///
/// **Unhandled is `false`, and `Window` treats that as "not claimed"** — the
/// keystroke then falls through to the raw key bubble rather than vanishing.
/// See `Window.dispatchAction(_:)`.
///
/// A free function over an explicit chain and registry, for
/// `dispatchKey(_:along:in:)`'s reason: the ranking rule is the interesting
/// part and a test should be able to drive it without building a window.
@MainActor
func dispatchAction(_ action: any Action, along chain: [GlobalElementID],
                    in registry: FocusRegistry) -> Bool {
    let key = ObjectIdentifier(type(of: action))
    for id in chain {
        guard let handler = registry.actionHandler(for: id, type: key) else { continue }
        handler(action)
        return true
    }
    return false
}

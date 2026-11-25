extension Dictionary {
    /// The value for a key the caller itself put there, read or edited in place.
    ///
    /// A missing key is a bug in the caller's own bookkeeping (the key came from a
    /// list built alongside the dictionary), so it traps with a message instead of
    /// `dictionary[key]!`. One hash lookup, the same as the force unwrap it replaces.
    subscript(required key: Key) -> Value {
        get {
            guard let position = index(forKey: key) else {
                preconditionFailure("a key the caller recorded is missing from its dictionary")
            }
            return values[position]
        }
        _modify {
            guard let position = index(forKey: key) else {
                preconditionFailure("a key the caller recorded is missing from its dictionary")
            }
            yield &values[position]
        }
    }
}

extension Optional {
    /// The wrapped value of an optional the caller has already set, read or edited in place.
    ///
    /// Stands in for `optional!` where the invariant is "this phase's state was produced by the
    /// phase before it"; unset is a framework bug and traps with a message. The in-place edit
    /// moves the payload out and back, which neither copies nor allocates.
    var required: Wrapped {
        get {
            guard let value = self else { preconditionFailure("an optional the caller had already set is nil") }
            return value
        }
        _modify {
            guard var value = self else { preconditionFailure("an optional the caller had already set is nil") }
            self = nil
            defer { self = value }
            yield &value
        }
    }
}

/// The result a scope helper's body stored. The helpers (`clipped`, `deferred`, `inScroller`, …) run
/// their body exactly once, so `nil` is a bug in the helper, not a state to handle.
@inline(__always)
func scopeResult<R>(_ result: R?) -> R {
    guard let result else { preconditionFailure("a scope helper returned without running its body") }
    return result
}

/// `value as! T`, spelled so the trap names both types. For a type-erased value that the
/// code itself stored under the type's own key (an action handler, a gesture value, an
/// environment slot): a mismatch is a bug in that bookkeeping, never user input.
@inline(__always)
func trapCast<T>(_ value: Any) -> T {
    guard let typed = value as? T else {
        preconditionFailure("a value stored as \(type(of: value)) was read back as \(T.self)")
    }
    return typed
}

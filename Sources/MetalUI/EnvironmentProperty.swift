/// Reads one environment value at the element's position — SwiftUI's
/// `@Environment` (ruling EV-M).
///
/// ```swift
/// struct Label: Element {
///     @Environment(\.isEnabled) var isEnabled
///     …
/// }
/// ```
///
/// **Bound like `@State`: by reflection, per element, per phase.**
/// `StateBinder.bind(_:in:id:)` finds the wrapper through `Mirror` and hands
/// its box a snapshot of the frame's current environment — the values at this
/// element's position, inside every scope above it. An `Element` is re-bound
/// in `prepaintGroup` and `paintGroup`, so each phase reads its own
/// occurrence's scope; a `Component` is bound once, in `requestGroupLayout`,
/// where its `content` is built. The snapshot is taken only for a type whose
/// shape declares an `@Environment`, once per bind (ruling EV-O).
///
/// **A wrapper that was never bound reads the key's default, silently**, and
/// builds a fresh `EnvironmentValues()` on every access — so its locale is the
/// root locale `Locale(identifier: "")`, not the window's `Locale.current`
/// (ruling EV-Y). There is no diagnostic, because the legitimate unbound reads (a
/// handler closure after the frame reading an `AnyElement`-wrapped element, a
/// value built outside any frame) look identical to a forgotten bind. **Inside
/// `AnyElement` it is always unbound**, for `@State`'s reason: `Mirror` cannot
/// see through the box. Pinned by
/// `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`.
///
/// **One element value placed twice shares one box**, divergence 19's shape:
/// reads are right per phase because of the re-bind, but a handler reading
/// the property after the frame sees whichever occurrence bound last.
@propertyWrapper
@MainActor
public struct Environment<Value> {
    final class Box {
        var values: EnvironmentValues?
    }

    let keyPath: KeyPath<EnvironmentValues, Value>
    let box = Box()

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        (box.values ?? EnvironmentValues())[keyPath: keyPath]
    }
}

/// Bridges a `Mirror` child back to `Environment`'s bind without knowing
/// `Value` — `BindableState`'s shape, one wrapper over.
@MainActor
protocol BindableEnvironment {
    func bind(_ values: EnvironmentValues)
}

extension Environment: BindableEnvironment {
    func bind(_ values: EnvironmentValues) {
        box.values = values
    }
}

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
/// value built outside any frame) look identical to a forgotten bind. **Inside
/// `AnyElement` it is bound** since plan task 8 (ruling ID-E): `AnyElementBox`
/// binds its concrete element in layout, prepaint and paint. Pinned by
/// `anEnvironmentPropertyInsideAnyElementReadsItsScope` (until then
/// `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`, pinned
/// inert).
///
/// **One element value placed twice shares one box**, as for `@State`: reads
/// are right per phase because of the re-bind, and since plan task 8 (ruling
/// ID-F) a handler run by input dispatch reads its own occurrence's snapshot —
/// the box keeps one per element id bound in a generation, and resolves
/// `StateDispatch.owner` (or its nearest ancestor) against them. A read
/// outside dispatch sees whichever occurrence bound last (divergence 71).
@propertyWrapper
@MainActor
public struct Environment<Value> {
    final class Box {
        var values: EnvironmentValues?
        /// The element id and generation `values` was bound under, so a
        /// second element id in one generation — one value placed twice — is
        /// told from the per-phase re-bind (ruling ID-F).
        var boundID: GlobalElementID?
        var boundGeneration: UInt64?
        /// One snapshot per element id bound this generation, once a second id
        /// is bound; `nil` in the common case, cleared by a later generation.
        var occurrences: [(id: GlobalElementID, values: EnvironmentValues)]?

        /// The snapshot `wrappedValue` reads: the dispatching owner's (or its
        /// nearest ancestor's) occurrence during input dispatch, else the last
        /// bound.
        @MainActor var resolvedValues: EnvironmentValues? {
            guard let occurrences, StateDispatch.owner != nil,
                  let index = StateDispatch.resolve(among: occurrences.map(\.id)) else {
                return values
            }
            return occurrences[index].values
        }
    }

    let keyPath: KeyPath<EnvironmentValues, Value>
    let box = Box()

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        (box.resolvedValues ?? EnvironmentValues())[keyPath: keyPath]
    }
}

/// Bridges a `Mirror` child back to `Environment`'s bind without knowing
/// `Value` — `BindableState`'s shape, one wrapper over.
@MainActor
protocol BindableEnvironment {
    func bind(_ values: EnvironmentValues, id: GlobalElementID, generation: UInt64)
}

extension Environment: BindableEnvironment {
    /// Seeds the box with the snapshot at element `id`'s position. A second,
    /// different `id` in one `generation` records every occurrence's snapshot
    /// (ruling ID-F); a later generation starts over.
    func bind(_ values: EnvironmentValues, id: GlobalElementID, generation: UInt64) {
        if box.boundGeneration != generation {
            box.occurrences = nil
        } else if let previous = box.boundID, previous != id {
            if box.occurrences == nil, let last = box.values {
                box.occurrences = [(previous, last)]
            }
            if let index = box.occurrences?.firstIndex(where: { $0.id == id }) {
                box.occurrences![index].values = values
            } else {
                box.occurrences?.append((id, values))
            }
        } else if let index = box.occurrences?.firstIndex(where: { $0.id == id }) {
            box.occurrences![index].values = values
        }
        box.values = values
        box.boundID = id
        box.boundGeneration = generation
    }
}

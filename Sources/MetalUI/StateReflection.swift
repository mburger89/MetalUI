import MetalUICore

/// Bridges a `Mirror` child back to `State`'s generic `bind`, without knowing
/// `Value`.
///
/// **`State<Value>` is generic, so a `Mirror` child typed `Any` cannot be cast
/// to `State<Int>` without already knowing `Int`.** Casting to this
/// existential instead lets `StateBinder` call `bind` on any `State<Value>`
/// with no `Value` in sight.
///
/// **Marking is not this protocol's job.** An earlier version of this file
/// exposed a second requirement, `boundID`, so `StateBinder` could read the
/// id `bind` had just computed and mark it from the caller's side. That
/// bought nothing over marking directly inside `State.bind` — both read the
/// same `box.slotID` — while costing a second existential dispatch per slot
/// per frame, and an `if let` around `boundID` whose `nil` branch could not
/// actually happen but was not trapped, so a future `bind` that somehow
/// failed to set the id would silently skip the mark rather than fail loudly.
/// `State.bind` marks itself now; see its own doc comment.
@MainActor
protocol BindableState {
    func bind(to table: StateTable, id: GlobalElementID, slot: Int)
}

extension State: BindableState {}

/// Seeds every `@State` an element declares with this frame's `StateTable`
/// and the element's own identity — the thing that makes `@State` work at
/// all, since the wrapper itself (`State.swift`) only ever reads a box
/// someone else must have filled in.
///
/// **`@Environment` rides the same walk** (ruling EV-M): its box is seeded
/// with a snapshot of the frame's environment at the element's position. The
/// shape cache records both kinds of ordinal, and a type with no
/// `@Environment` never causes a snapshot (ruling EV-O).
///
/// **Reflects a TYPE once, not an instance every frame.** `Mirror` over every
/// element every frame would cost more than the whole layout pass; a type's
/// stored properties cannot change at runtime, so the ordinals of its `State`
/// children are computed once, keyed by `ObjectIdentifier`, and reused for
/// every instance of that type forever. The common case — an element with no
/// `@State` at all — is a dictionary hit against an empty array and nothing
/// else: no `Mirror` is built for it at all past the type's first sighting.
///
/// **What is NOT eliminated, and is not this file's job to eliminate:** a
/// `Mirror` walk over the CHILDREN, once per element per frame, for every
/// element that does have `@State`. `Mirror` hands back copies, so there is
/// no way to reach a specific stored property without asking it for its
/// children again; the per-type cache only removes the cost of working out
/// WHICH children matter, not the cost of touching the ones that do.
/// Measured: 200 sibling leaves with one `@State` each cost measurably more
/// per frame than 200 stateless ones (see the input-and-state task 2 review
/// for the numbers) — real and unavoidable given this design, distinct from
/// the per-type cost this cache exists to remove.
///
/// **What WAS avoidable, and is fixed here:** two wasted `Mirror` passes.
/// `Array(Mirror(reflecting:).children)` used to materialize every child into
/// a new array on every bind call, when only the recorded ordinals were ever
/// read out of it; `bindOrdinals` below walks the `Mirror`'s children once,
/// consuming the sorted `ordinals` array in step and stopping as soon as the
/// last one is bound, with no intermediate collection. And a cache MISS used
/// to call `Mirror(reflecting:)` twice — once to find the ordinals, once
/// again to bind them — where one pass can do both, since the ordinals are
/// only ever used against the exact same `Mirror` that found them.
///
/// `@MainActor` because `StateTable`, `State` and `Element` all are — the
/// cache is main-actor state read and written from main-actor call sites
/// only, so no `nonisolated(unsafe)` is needed anywhere here.
@MainActor
enum StateBinder {
    /// What a type declares, found once by reflection: the ordinals of its
    /// `State` and `Environment` wrappers among its `Mirror` children, in
    /// ASCENDING order — `bindOrdinals` relies on that order to consume them in
    /// one forward pass — and whether any of them is an `Environment`.
    private struct Shape {
        var ordinals: [Int] = []
        var hasEnvironment = false
    }

    private static var shapes: [ObjectIdentifier: Shape] = [:]

    /// Test observability for the per-type cache. Not part of any contract.
    /// One per type, whatever the type declares.
    private(set) static var reflectionCount = 0

    static func resetReflectionCount() { reflectionCount = 0 }

    /// Seeds every `@State` `element` declares with `frame`'s state table and
    /// `id`, and every `@Environment` with a snapshot of `frame`'s current
    /// environment (ruling EV-M). Marking is `State.bind`'s own job, done
    /// unconditionally as part of computing the slot id — see its doc comment.
    ///
    /// **Takes the `Frame`, not an `EnvironmentValues`, and that is the whole
    /// performance argument** (ruling EV-O). An `environment:` argument would
    /// be evaluated before this could return early, copying the environment
    /// for every element in every phase. Here `frame.environmentSnapshot()` is
    /// called only when the type's cached shape has `Environment` ordinals, and
    /// then once per bind.
    ///
    /// **No overload keeps the old `bind(_:table:id:)` spelling, and the frame
    /// must never gain a default** (ruling EV-W). A call site written elsewhere
    /// against the old spelling fails to compile at a merge, instead of
    /// silently binding the root environment.
    static func bind<E>(_ element: E, in frame: Frame, id: GlobalElementID) {
        let key = ObjectIdentifier(E.self)
        if let shape = shapes[key] {
            guard !shape.ordinals.isEmpty else { return }
            let snapshot = shape.hasEnvironment ? frame.environmentSnapshot() : nil
            bindOrdinals(shape.ordinals, in: element, table: frame.stateTable,
                         environment: snapshot, id: id)
            return
        }

        // Cache miss: one Mirror pass finds the ordinals AND binds them,
        // rather than a `reflect` pass followed by a separate `bindOrdinals`
        // pass over the same value.
        var shape = Shape()
        var snapshot: EnvironmentValues?
        for (index, child) in Mirror(reflecting: element).children.enumerated() {
            if let bindable = child.value as? BindableState {
                shape.ordinals.append(index)
                bindable.bind(to: frame.stateTable, id: id, slot: index)
            } else if let bindable = child.value as? BindableEnvironment {
                shape.ordinals.append(index)
                shape.hasEnvironment = true
                if snapshot == nil { snapshot = frame.environmentSnapshot() }
                bindable.bind(snapshot!, id: id, generation: frame.stateTable.generation)
            }
        }
        shapes[key] = shape
        reflectionCount += 1
    }

    /// Binds exactly the children at `ordinals`, in one forward walk of the
    /// `Mirror`'s children — no `Array` of every child, and no work past the
    /// last ordinal. `environment` is non-nil exactly when the shape has
    /// `Environment` ordinals.
    ///
    /// `ordinals` is never empty here: the one caller already guards that.
    ///
    /// **Never subscripts `children` by ordinal, and that is what keeps this
    /// safe against a shorter Mirror than the type produced when it was first
    /// reflected.** A struct's stored properties cannot change count between
    /// instances, but nothing enforces that for a `CustomReflectable`
    /// conformance — a walk that compared `index == ordinals[next]` while
    /// iterating simply runs out of children and stops without touching any
    /// of the remaining ordinals, rather than trapping on an out-of-range
    /// index the way `Array(mirror.children)[ordinal]` would. Measured rather
    /// than argued: a probe that seeds the cache from a three-child instance
    /// and then binds a one-child one survives here and dies with `Index out
    /// of range` under the old indexed body.
    ///
    /// **"Does not trap" is not "binds everything", and the difference is
    /// silent.** An ordinal past the end of a shorter `Mirror` is never bound
    /// at all, so that `@State` returns its initial value forever with no
    /// diagnostic.
    ///
    /// **And the MIRROR IMAGE of that case is the one to watch, because the
    /// cache makes it stick.** The hazard above needs the *first* instance of
    /// a type to be the longer one. If the first sighting is the SHORTER one,
    /// `shapes` records too few ordinals, and every later instance — however
    /// many children it reports — is bound against that truncated list for the
    /// life of the process. Nothing re-reflects a type once it is cached.
    /// Pre-existing rather than introduced here (the per-type cache has always
    /// worked this way), reachable only through a `CustomReflectable` element
    /// whose children vary by instance, and unpinned by any test.
    private static func bindOrdinals<E>(_ ordinals: [Int], in element: E,
                                        table: StateTable,
                                        environment: EnvironmentValues?,
                                        id: GlobalElementID) {
        var next = ordinals.startIndex
        for (index, child) in Mirror(reflecting: element).children.enumerated() {
            guard index == ordinals[next] else { continue }
            if let bindable = child.value as? BindableState {
                bindable.bind(to: table, id: id, slot: index)
            } else if let bindable = child.value as? BindableEnvironment,
                      let environment {
                // The element id and generation let an aliased box keep one
                // snapshot per occurrence (ruling ID-F).
                bindable.bind(environment, id: id, generation: table.generation)
            }
            next += 1
            if next == ordinals.endIndex { break }
        }
    }
}

import MetalUICore
import MetalUILayout

// MARK: - `onAppear`, `onDisappear`, `onChange` (rulings `LC-A`…`LC-P`)
//
// Probe `docs/probes/swiftui-lifecycle.swift`. One transparent scope,
// `LifecycleScope`, the shape of `TransactionScope` (`AN-Y`): layout- and
// identity-transparent, noting itself in layout into the window's
// `LifecycleStore` (held by its `AnimationStore`, `LC-D`). Nothing runs in a
// phase: `Frame.render` closes each build into events after its sweep, and
// `Window.drawFrameIfNeeded` runs them after the build, under `StateDispatch`
// (`LC-E`).

/// What one `LifecycleScope` contributes (`LC-B`): one write per scope, so
/// stacked modifiers are stacked scopes, each with its own store key.
enum LifecycleWrite {
    /// `.onAppear(perform:)`: run when the scope becomes present (`LC-C`).
    case appear(() -> Void)
    /// `.onDisappear(perform:)`: run when the scope stops being present.
    case disappear(() -> Void)
    /// `.onChange(of:initial:_:)`: `value` compared with the last build's
    /// (`LC-G`); both closure forms build this case.
    case change(value: Any, isEqual: (Any) -> Bool, action: (Any, Any) -> Void, initial: Bool)
    /// `.task` and `.task(id:)` (`PX-F`): started as an appearance, cancelled
    /// as a disappearance, restarted as a change when its id differs.
    case task(TaskSpec)
}

/// A `LifecycleScope`'s layout: its content's (the scope stores nothing — it
/// notes itself in layout and forwards prepaint and paint unchanged). A
/// `PresentationScope` (`SV-K`) uses it too, for the same reason.
public struct LifecycleScopeLayout<ContentLayout> {
    var content: ContentLayout
}

/// `content` with an appearance, disappearance or value-change action — what
/// `.onAppear(perform:)`, `.onDisappear(perform:)` and `.onChange(of:initial:_:)`
/// return (rulings `LC-B`, `LC-C`).
///
/// **Transparent**: `parent` and `cursor` are forwarded unchanged, so the
/// content keeps the ids it would have without the scope; no `@State`, focus
/// or `$anim` baseline moves when a lifecycle modifier is added or removed.
/// The scope's entry lives in the window's `LifecycleStore`, keyed by the
/// position it sits at, never in `StateTable` (`LC-D`).
///
/// **Presence** is membership in a build: the scope is present while its
/// content is built and registers at least one node — a hidden, transparent,
/// zero-sized or clipped-out element is present; an empty `ForEach` is not;
/// a `List` row out of its window is not (`LC-C`, `LC-P` item 1).
///
/// **A `Self`-returning decoration written after this scope does not compile**
/// (`Text("a").onAppear {}.onClick {}`; divergence 120): write it first.
public struct LifecycleScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let write: LifecycleWrite?

    init(content: Content, write: LifecycleWrite?) {
        self.content = content
        self.write = write
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], LifecycleScopeLayout<Content.GroupLayout>) {
        // Pre-order: the scope's order is reserved before its content's (LC-F).
        let start = cursor
        let order = pass.frame.reserveLifecycleOrder()
        let (nodes, layout) = pass.frame.withLifecycleScope {
            content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        // A group with no content is absent (LC-P item 1). A nil action still
        // notes an entry, so toggling an action to or from nil changes no
        // presence (LC-V).
        if !nodes.isEmpty {
            pass.frame.noteLifecycle(write, order: order, under: parent, at: start)
        }
        return (nodes, LifecycleScopeLayout(content: layout))
    }

    public mutating func prepaintGroup(layout: inout LifecycleScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paintGroup(layout: inout LifecycleScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// **The typed entry is a line-for-line copy of the untyped one, pinned on its
/// own** (spec test 1.10): a copy of a pinned implementation is unpinned.
extension LifecycleScope: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], LifecycleScopeLayout<Content.GroupLayout>) {
        let start = cursor
        let order = pass.frame.reserveLifecycleOrder()
        let (nodes, layout) = pass.frame.withLifecycleScope {
            content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        if !nodes.isEmpty {
            pass.frame.noteLifecycle(write, order: order, under: parent, at: start)
        }
        return (nodes, LifecycleScopeLayout(content: layout))
    }
}

extension Frame {
    /// The registration order of the scope being visited — the build's
    /// pre-order walk (`LC-F`).
    func reserveLifecycleOrder() -> Int {
        animationStore.lifecycle.reserveOrder()
    }

    /// Notes a present scope (`LC-C`). The key is `.named("$lifecycle<depth>")`
    /// under the scope's position `.child(of: parent, at: cursor)` — `depth`
    /// the lifecycle scopes enclosing it, so two stacked at one position keep
    /// two entries — a store key, never a `StateTable` id (no reserved name, no
    /// `noteNamed`). The owner, which the action is dispatched to, is the
    /// position.
    func noteLifecycle(_ write: LifecycleWrite?, order: Int, under parent: GlobalElementID?, at cursor: Int) {
        let owner = GlobalElementID.child(of: parent, at: cursor, name: nil)
        let scope = GlobalElementID.child(of: owner, at: 0, name: ElementID("$lifecycle\(lifecycleDepth)"))
        animationStore.lifecycle.note(write, scope: scope, owner: owner, order: order)
    }
}

/// One action the window runs after a build (`LC-E`), dispatched to `owner`,
/// reading `departed` while it runs when it is a disappearance (`LC-I`).
struct LifecycleEvent {
    let owner: GlobalElementID
    let action: () -> Void
    let departed: DepartedState?
}

/// The lifecycle's bookkeeping (ruling `LC-D`), held by the window's
/// `AnimationStore` — so a `Window`'s frames share one and a headless
/// `renderFrame` or a test-built `Frame` gets a fresh one.
///
/// It holds this build's entries and the last COMPLETED build's, the
/// disappearances parked on a removal ghost (`LC-H`) and the events the window
/// has not yet run. **Every entry a build does not touch is dropped at the end
/// of that build** (`AN-AB`'s rule): content that leaves and returns compares
/// against nothing (`C10`). Nothing here is a `StateTable` entry, a `$`-slot
/// or a reserved name.
///
/// **Work** (`LC-M`): a build with K scopes does K registrations plus one
/// visit per entry of each of the two builds — `3K` steady — and a tree with
/// no lifecycle modifier does nothing at all (`lastFrameWork == 0`): the store
/// is reached only from `LifecycleScope`.
@MainActor
final class LifecycleStore {
    struct Key: Hashable {
        let scope: GlobalElementID
        let occurrence: Int
    }

    struct Change {
        let value: Any
        let isEqual: (Any) -> Bool
        let action: (Any, Any) -> Void
        let initial: Bool
    }

    struct Entry {
        let order: Int
        let owner: GlobalElementID
        var onAppear: (() -> Void)?
        var onDisappear: (() -> Void)?
        var change: Change?
        /// A `.task` scope's spec (`PX-F`).
        var task: TaskSpec?
        /// Its running task's box — carried from the last build's entry when
        /// the key stays, or from a parked ghost when the key returns (`X17`).
        var running: RunningTask?
    }

    /// One parked disappearance: its key (so a return can cancel it, `LC-H`)
    /// and its event.
    struct Parked {
        let key: Key
        let event: LifecycleEvent
    }

    /// What one live removal ghost holds back (`LC-H`): every key that left
    /// under it — with an `onDisappear` or not, so a return cancels the
    /// appearance of each (`T4`: the re-inserted content runs no `onAppear`,
    /// its own or a descendant's) — and the parked disappearances, in the
    /// order they run.
    struct ParkedGhost {
        var keys: Set<Key> = []
        var events: [Parked] = []
        /// The running tasks of the keys that left, so a key that returns
        /// keeps its task — neither cancelled nor restarted (`PX-F` item 7).
        var running: [Key: RunningTask] = [:]
    }

    private var current: [Key: Entry] = [:]
    private var previous: [Key: Entry] = [:]
    /// Scopes noted this build per scope id — the occurrence rule (`MV-M` item 5).
    private var occurrences: [GlobalElementID: Int] = [:]
    private var nextOrder = 0
    /// Disappearances waiting for a removal ghost, by the ghost's key, each
    /// list in the order its events run.
    private var parked: [GlobalElementID: ParkedGhost] = [:]
    private var pending: [LifecycleEvent] = []
    private var workThisFrame = 0

    /// Work the last completed build did (`LC-M`): registrations plus the
    /// entries the end-of-build diff visited.
    private(set) var lastFrameWork = 0

    init() {}

    /// Entries the last completed build left — test observability (`LC-K`).
    var count: Int { previous.count }

    /// Disappearances parked on a live ghost.
    var parkedCount: Int { parked.values.reduce(0) { $0 + $1.events.count } }

    /// Whether the last completed build held an `onDisappear` — so the sweep
    /// keeps what it resets for that action to read (`LC-I` item 1).
    private(set) var hasDisappearActions = false
    private var currentHasDisappearActions = false

    /// The next registration order in the build being laid out.
    func reserveOrder() -> Int {
        defer { nextOrder += 1 }
        return nextOrder
    }

    /// A present scope (layout).
    /// A `nil` write is a present scope with no action (`LC-V`): its entry
    /// keeps presence steady while an action toggles to or from `nil`.
    func note(_ write: LifecycleWrite?, scope: GlobalElementID, owner: GlobalElementID, order: Int) {
        let occurrence = occurrences[scope, default: 0]
        occurrences[scope] = occurrence + 1
        var entry = Entry(order: order, owner: owner)
        switch write {
        case .appear(let action)?: entry.onAppear = action
        case .disappear(let action)?:
            entry.onDisappear = action
            currentHasDisappearActions = true
        case .change(let value, let isEqual, let action, let initial)?:
            entry.change = Change(value: value, isEqual: isEqual, action: action, initial: initial)
        case .task(let spec)?: entry.task = spec
        case nil: break
        }
        current[Key(scope: scope, occurrence: occurrence)] = entry
        workThisFrame += 1
    }

    /// Closes a build into events (`LC-E`, `LC-F`, `LC-H`), called by
    /// `Frame.render` after `StateTable.sweep()`: `liveGhosts` are the removal
    /// ghosts still alive, `departed` what the sweep reset (`LC-I`).
    ///
    /// Three buckets, in order: the changes of elements present in both builds,
    /// the appearances (with `initial: true` first firings), the
    /// disappearances — each in reverse registration order (disappearances in
    /// the last build's). A disappearance whose owner is, or descends from, a
    /// live ghost's position is parked on it and runs in the first build after
    /// the ghost ends — unless its key returns first, which cancels both it and
    /// the returning appearance (`T4`).
    func endFrame(liveGhosts: [(key: GlobalElementID, position: GlobalElementID)], departed: DepartedState?) {
        defer {
            occurrences.removeAll(keepingCapacity: true)
            nextOrder = 0
        }
        guard !current.isEmpty || !previous.isEmpty || !parked.isEmpty else {
            lastFrameWork = workThisFrame
            workThisFrame = 0
            return
        }

        // Parked disappearances whose key returned are cancelled with its
        // appearance; those whose ghost ended run now.
        var cancelled: Set<Key> = []
        var released: [LifecycleEvent] = []
        if !parked.isEmpty {
            let live = Set(liveGhosts.map(\.key))
            for (ghost, var held) in parked {
                for key in held.keys where current[key] != nil {
                    cancelled.insert(key)
                    // The returning key keeps its running task (`X17`).
                    if let box = held.running.removeValue(forKey: key) { current[key]?.running = box }
                }
                if !cancelled.isEmpty {
                    held.events.removeAll { cancelled.contains($0.key) }
                    held.keys.subtract(cancelled)
                }
                if live.contains(ghost) {
                    parked[ghost] = held.keys.isEmpty ? nil : held
                } else {
                    released.append(contentsOf: held.events.map(\.event))
                    parked[ghost] = nil
                }
            }
        }

        var changes: [(order: Int, event: LifecycleEvent)] = []
        var appearances: [(order: Int, event: LifecycleEvent)] = []
        // Running-task boxes this build's entries take (`PX-F` item 10),
        // written back after the walk: carried from the last build's entry,
        // or new for a task that starts.
        var boxes: [(key: Key, box: RunningTask)] = []
        for (key, entry) in current {
            workThisFrame += 1
            if let old = previous[key] {
                if let change = entry.change, let before = old.change, !change.isEqual(before.value) {
                    let (oldValue, newValue, action) = (before.value, change.value, change.action)
                    changes.append((entry.order, LifecycleEvent(owner: entry.owner,
                                                                action: { action(oldValue, newValue) },
                                                                departed: nil)))
                }
                if let spec = entry.task {
                    // Carried before anything reads it; an id that differs
                    // cancels the old task, then starts the new one (`X5`).
                    let box = old.running ?? RunningTask()
                    boxes.append((key, box))
                    if old.running == nil {
                        appearances.append((entry.order, Self.startEvent(spec, box, owner: entry.owner)))
                    } else if let isEqual = spec.isEqual, let before = old.task?.id, !isEqual(before) {
                        changes.append((entry.order, LifecycleEvent(owner: entry.owner, action: {
                            box.handle?.cancel()
                            box.handle = TaskStart.start(spec)
                        }, departed: nil)))
                    }
                } else if let box = old.running {
                    // The scope at this key stopped being a task.
                    changes.append((entry.order, Self.cancelEvent(box, owner: entry.owner)))
                }
            } else if let spec = entry.task, entry.running == nil, !cancelled.contains(key) {
                let box = RunningTask()
                boxes.append((key, box))
                appearances.append((entry.order, Self.startEvent(spec, box, owner: entry.owner)))
            } else if !cancelled.contains(key) {
                if let action = entry.onAppear {
                    appearances.append((entry.order, LifecycleEvent(owner: entry.owner, action: action,
                                                                    departed: nil)))
                }
                if let change = entry.change, change.initial {
                    let (value, action) = (change.value, change.action)
                    appearances.append((entry.order, LifecycleEvent(owner: entry.owner,
                                                                    action: { action(value, value) },
                                                                    departed: nil)))
                }
            }
        }

        for (key, box) in boxes { current[key]?.running = box }

        var disappearances: [(order: Int, key: Key, owner: GlobalElementID, event: LifecycleEvent?,
                              running: RunningTask?)] = []
        for (key, entry) in previous {
            workThisFrame += 1
            guard current[key] == nil else { continue }
            // A task's disappearance is its cancel (`PX-F` item 4), reading no
            // departed state.
            let event = entry.onDisappear.map { LifecycleEvent(owner: entry.owner, action: $0, departed: departed) }
                ?? entry.running.map { Self.cancelEvent($0, owner: entry.owner) }
            // A key with no `onDisappear` is kept only for a ghost's cancellation.
            guard event != nil || !liveGhosts.isEmpty else { continue }
            disappearances.append((entry.order, key, entry.owner, event, entry.running))
        }

        changes.sort { $0.order > $1.order }
        appearances.sort { $0.order > $1.order }
        disappearances.sort { $0.order > $1.order }
        pending.append(contentsOf: changes.map(\.event))
        pending.append(contentsOf: appearances.map(\.event))
        pending.append(contentsOf: released)
        for item in disappearances {
            if let ghost = liveGhosts.first(where: { item.owner.isOrDescends(from: $0.position) }) {
                parked[ghost.key, default: ParkedGhost()].keys.insert(item.key)
                if let box = item.running { parked[ghost.key, default: ParkedGhost()].running[item.key] = box }
                if let event = item.event {
                    parked[ghost.key, default: ParkedGhost()].events.append(Parked(key: item.key, event: event))
                }
            } else if let event = item.event {
                pending.append(event)
            }
        }

        swap(&current, &previous)
        current.removeAll(keepingCapacity: true)
        hasDisappearActions = currentHasDisappearActions
        currentHasDisappearActions = false
        lastFrameWork = workThisFrame
        workThisFrame = 0
    }

    /// The event that starts `spec` into `box` (`PX-F` item 3).
    private static func startEvent(_ spec: TaskSpec, _ box: RunningTask, owner: GlobalElementID) -> LifecycleEvent {
        LifecycleEvent(owner: owner, action: { box.handle = TaskStart.start(spec) }, departed: nil)
    }

    /// The event that cancels `box`'s task and empties it (`PX-F` item 4);
    /// it never waits for the task to finish.
    private static func cancelEvent(_ box: RunningTask, owner: GlobalElementID) -> LifecycleEvent {
        LifecycleEvent(owner: owner, action: {
            box.handle?.cancel()
            box.handle = nil
        }, departed: nil)
    }

    /// Running tasks the store holds — present entries' and parked ones'
    /// boxes with a task not cancelled (test observability, `PX-F`).
    var runningTaskCount: Int {
        let present = previous.values.compactMap(\.running)
        let held = parked.values.flatMap { $0.running.values }
        return (present + held).filter { $0.handle.map { !$0.isCancelled } ?? false }.count
    }

    /// The events not yet run, emptied.
    func takeEvents() -> [LifecycleEvent] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending
    }

    /// Window close (`LC-J`): every present element's `onDisappear` — and
    /// every running task's cancel (`PX-F` item 8) — in reverse registration
    /// order, then every parked one; everything is cleared, so a second call
    /// finds nothing. Unrun events are dropped with the window.
    func closeAll() -> [LifecycleEvent] {
        var events = previous.values.sorted { $0.order > $1.order }.compactMap { entry in
            entry.onDisappear.map { LifecycleEvent(owner: entry.owner, action: $0, departed: nil) }
                ?? entry.running.map { Self.cancelEvent($0, owner: entry.owner) }
        }
        for held in parked.values { events.append(contentsOf: held.events.map(\.event)) }
        current.removeAll()
        previous.removeAll()
        parked.removeAll()
        hasDisappearActions = false
        currentHasDisappearActions = false
        pending.removeAll()
        return events
    }
}

extension GlobalElementID {
    /// Whether `self` equals `ancestor` or descends from it.
    func isOrDescends(from ancestor: GlobalElementID) -> Bool {
        var cursor: GlobalElementID? = self
        while let id = cursor {
            if id == ancestor { return true }
            cursor = id.parent
        }
        return false
    }
}

extension ElementGroup {
    /// Runs `action` after the first frame this group is present in — built
    /// and registering at least one node — and again each time it returns
    /// after leaving (SwiftUI's `onAppear(perform:)`; rulings `LC-B`, `LC-C`).
    ///
    /// The action runs after the frame is built, never inside it, on the main
    /// actor and dispatched to this group (`LC-E`): `@State`, `Binding` and
    /// `@Observable` writes are legal, as in an input handler, and a write it
    /// makes is presented in the same frame (one settle build; divergence 121
    /// for a chain). Presence is membership, not visibility: a hidden or
    /// transparent group is present; a `List` row out of its window is not.
    /// Order: changes, then appearances, then disappearances, each in reverse
    /// pre-order — children first (`LC-F`, divergence 122).
    public func onAppear(perform action: (() -> Void)? = nil) -> LifecycleScope<Self> {
        LifecycleScope(content: self, write: action.map { .appear($0) })
    }

    /// Runs `action` after the first frame this group is no longer present
    /// in (SwiftUI's `onDisappear(perform:)`; rulings `LC-B`, `LC-C`).
    ///
    /// Reads the group's own `@State` as it was in its last frame; a write
    /// there is discarded, and content that returns starts fresh (`LC-I`).
    /// Under an animated removal it waits for the transition to end (`LC-H`);
    /// closing the window runs it (`LC-J`). Runs after the frame, dispatched
    /// to this group, like `onAppear(perform:)`.
    public func onDisappear(perform action: (() -> Void)? = nil) -> LifecycleScope<Self> {
        LifecycleScope(content: self, write: action.map { .disappear($0) })
    }

    /// Runs `action` with the old and new value when `value` differs from the
    /// one this group was built with in the last frame (SwiftUI's
    /// `onChange(of:initial:_:)`; ruling `LC-G`).
    ///
    /// Compared once per frame, so writes between frames coalesce (first old,
    /// last new) and an undone change fires nothing. Not on first appearance
    /// unless `initial` is `true`, which fires `(value, value)` with the
    /// appearances. A new identity compares against nothing. Runs after the
    /// frame, dispatched to this group, like `onAppear(perform:)`.
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void)
        -> LifecycleScope<Self> {
        LifecycleScope(content: self, write: .change(
            value: value, isEqual: { ($0 as? V) == value },
            action: { old, new in
                // Both values were stored by a scope of this type at this key.
                if let old = old as? V, let new = new as? V { action(old, new) }
            },
            initial: initial))
    }

    /// Runs `action` when `value` differs from the one this group was built
    /// with in the last frame — the zero-parameter form of the two-parameter
    /// `onChange(of:initial:_:)` above (SwiftUI's; ruling `LC-G`).
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping () -> Void) -> LifecycleScope<Self> {
        LifecycleScope(content: self, write: .change(
            value: value, isEqual: { ($0 as? V) == value },
            action: { _, _ in action() },
            initial: initial))
    }
}

import MetalUICore

/// SwiftUI's `@FocusState` (plan task 12 part 1, ruling `IX-J`): a property an
/// element reads to learn whether — or which of its bound elements — holds
/// keyboard focus, and writes from input to move it.
///
/// ```swift
/// struct Form: Component {
///     enum Field: Hashable { case name, email }
///     @FocusState var field: Field?
///     @FocusState var searching: Bool
///     var content: some ElementGroup {
///         TextField("Name", text: $name).focused($field, equals: .name)
///         TextField("Email", text: $email).focused($field, equals: .email)
///         Box().focusable().focused($searching)
///         Box().onClick { field = .email }
///     }
/// }
/// ```
///
/// **Reading** returns the window's focus as of the last completed frame:
/// `true` (or the bound value) iff the focused element carries a `.focused`
/// binding to this property with that value, `false`/`nil` otherwise.
///
/// **Writing** — from input, as a `@State` write is — moves focus at the next
/// frame to the element that registered the written value (or `true`) on the
/// last frame, **if that element was focusable there**; otherwise focus stays
/// where it is (`IX-J` item 2, `IX-S`). Writing `false`/`nil` clears focus
/// **only if** the focused element is bound to this property.
///
/// **It follows every other focus mover** — Tab, a `TextField` press,
/// `Window.focus(_:)`, `IX-I`'s drop when the focused identity goes away —
/// updating its value after the frame that moved focus, and **it never writes
/// from a phase**: `Window` reconciles it between frames (`Window.drawFrameIfNeeded`),
/// applying a pending write before the frame is built and writing the value
/// back after the frame's focus read-back, and only when it changed.
///
/// **`.focused` does not make an element focusable** (`IX-J` item 3): it binds
/// one that is (`.focusable()`, a control, a `TextField`).
///
/// Seeded by reflection exactly as `@State` is (`StateBinder`): its slot is the
/// `$state<n>` sibling at its own ordinal — **no new reserved name**, the seven
/// retention slots stay seven. Its value is reset with its element, as `@State`
/// is (`ID-C`, `ID-R`, `DD-C`).
///
/// **One element VALUE placed twice shares one box**, as `@State`'s does; unlike
/// `@State`, no dispatch-time occurrence resolution (`ID-F`) is applied — a
/// write from a handler reaches the last-bound occurrence. `@FocusedValue`,
/// `focusedSceneValue`, `defaultFocus`, `focusScope`, `prefersDefaultFocus` and
/// `focusSection` are not offered (`IX-J`, owner none).
@propertyWrapper
@MainActor
public struct FocusState<Value: Hashable> {
    let box: Box

    /// A Boolean focus state: `true` while the focused element carries
    /// `.focused($this)`.
    public init() where Value == Bool {
        box = Box(defaultValue: false)
    }

    /// An optional focus state: the value an element bound with
    /// `.focused($this, equals:)` while that element holds focus, `nil` otherwise.
    public init<T: Hashable>() where Value == T? {
        box = Box(defaultValue: nil)
    }

    /// The focused element's value as of the last completed frame. A write
    /// moves focus before the next frame builds, only to an element focusable
    /// last frame (`IX-J`); write from input, never from a phase.
    public var wrappedValue: Value {
        get {
            guard let table = box.table, let slot = box.slotID else { return box.defaultValue }
            return table.peek(slot, as: FocusStateValue<Value>.self)?.value ?? box.defaultValue
        }
        nonmutating set {
            guard let table = box.table, let slot = box.slotID else { return }
            // A dirtying write, as `@State`'s is: the window draws the frame that
            // applies it (`Window.applyPendingFocusStateWrites`).
            table.write(slot, FocusStateValue(value: newValue, pending: true))
        }
    }

    /// The binding `.focused(_:)` and `.focused(_:equals:)` take.
    public var projectedValue: Binding { Binding(box: box) }

    /// A focus state handed to `.focused` or to a child element — SwiftUI's
    /// `FocusState<Value>.Binding`.
    @MainActor
    public struct Binding {
        let box: FocusState<Value>.Box

        /// The bound focus state's value; reading and writing behave as
        /// `FocusState.wrappedValue` does.
        public var wrappedValue: Value {
            get { FocusState(box: box).wrappedValue }
            nonmutating set { FocusState(box: box).wrappedValue = newValue }
        }

        /// The binding itself, so `$focus` can be passed on.
        public var projectedValue: Binding { self }
    }

    private init(box: Box) { self.box = box }

    /// The storage `StateBinder` binds, shared by reference between the
    /// property and every `Binding` it projects.
    @MainActor
    final class Box: FocusStateReconciling {
        let defaultValue: Value
        var table: StateTable?
        var slotID: GlobalElementID?

        init(defaultValue: Value) { self.defaultValue = defaultValue }

        var currentSlot: GlobalElementID? { slotID }

        func takePendingWrite(in table: StateTable, slot: GlobalElementID) -> PendingFocusWrite? {
            guard let stored = table.peek(slot, as: FocusStateValue<Value>.self), stored.pending else {
                return nil
            }
            // Consumed without dirtying: the frame this runs before is already
            // being drawn.
            table.withState(slot, initial: stored) { $0.pending = false }
            return PendingFocusWrite(value: AnyHashable(stored.value), clears: stored.value == defaultValue)
        }

        func reconcile(in table: StateTable, slot: GlobalElementID, focusedValue: AnyHashable?) {
            let expected = focusedValue.flatMap { $0.base as? Value } ?? defaultValue
            let current = table.peek(slot, as: FocusStateValue<Value>.self)
            if current == nil, expected == defaultValue { return }
            guard current?.value != expected || current?.pending == true else { return }
            table.write(slot, FocusStateValue(value: expected, pending: false))
        }
    }
}

extension FocusState: BindableState {
    func bind(to table: StateTable, id: GlobalElementID, slot: Int) {
        box.table = table
        let slotID = GlobalElementID.child(of: id, at: slot, name: ElementID("$state\(slot)"))
        box.slotID = slotID
        table.mark(slotID)
        table.noteFocusState(box, at: slotID)
    }
}

/// What a `FocusState` stores in its `$state<n>` slot: the value as of the last
/// reconciliation, and whether input wrote it since.
struct FocusStateValue<Value: Hashable>: Equatable {
    var value: Value
    var pending: Bool
}

/// A write from input the window applies before its next frame.
struct PendingFocusWrite {
    /// The written value, boxed as `.focused(_:equals:)` boxes its own.
    let value: AnyHashable
    /// `false`/`nil`: clear focus if this state's element holds it.
    let clears: Bool
}

/// A `FocusState`'s box, type-erased so the window can reconcile every one
/// the last frame bound (`StateTable.noteFocusState`).
@MainActor
protocol FocusStateReconciling: AnyObject {
    /// The slot this box was last bound to.
    var currentSlot: GlobalElementID? { get }
    /// The pending write at `slot`, consumed, or `nil`.
    func takePendingWrite(in table: StateTable, slot: GlobalElementID) -> PendingFocusWrite?
    /// Writes the value the window's focus implies — `focusedValue` when the
    /// focused element is bound to `slot`, the default otherwise — only if it
    /// differs from the stored one.
    func reconcile(in table: StateTable, slot: GlobalElementID, focusedValue: AnyHashable?)
}

/// What `.focused(_:)`/`.focused(_:equals:)` stored on an element: the state it
/// binds and the value it stands for. A class box, one reference in `Handlers`
/// (`IX-N`'s Windows stack budget).
final class FocusBindingTarget {
    let state: any FocusStateReconciling
    let value: AnyHashable

    init(state: any FocusStateReconciling, value: AnyHashable) {
        self.state = state
        self.value = value
    }
}

extension StyledElement {
    /// Binds this element's focus to a Boolean `@FocusState`: the state reads
    /// `true` while this element holds focus, and writing `true` from input
    /// focuses it — **if it is focusable**; `.focused` does not make it so
    /// (`IX-J` item 3). A second `.focused` replaces the first.
    public func focused(_ condition: FocusState<Bool>.Binding) -> Self {
        handling { $0.focusBinding = FocusBindingTarget(state: condition.box, value: AnyHashable(true)) }
    }

    /// Binds this element's focus to an optional (or any `Hashable`)
    /// `@FocusState`: the state reads `value` while this element holds focus,
    /// and writing `value` from input focuses it — if it is focusable.
    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> Self {
        handling { $0.focusBinding = FocusBindingTarget(state: binding.box, value: AnyHashable(value)) }
    }
}

import MetalUICore

// `@GestureState` and `Gesture.updating(_:body:)` (item G1, rulings `GS-A`…`GS-F`;
// `docs/superpowers/2026-10-21-gesture-state-decisions.md`; probe `docs/probes/swiftui-gesture-state.swift`).

/// The per-event write base (`GS-D`): `Window.runGestureCallbacks` increments `current` once per call, so
/// every `updating` body of one event starts from the value committed before the event.
@MainActor
enum GestureStateBatch {
    static var current = 0
}

/// What every copy of one `GestureState` shares besides its `State` box: the reset's settings, which slots
/// have been written since the last reset, and the per-event base (`GS-D`).
@MainActor
final class GestureStateBox<Value> {
    let resetTransaction: Transaction
    let reset: (@MainActor (Value, inout Transaction) -> Void)?
    var dirty: Set<GlobalElementID> = []
    var batch = -1
    var baseSlot: GlobalElementID?
    var base: Value?

    init(resetTransaction: Transaction, reset: (@MainActor (Value, inout Transaction) -> Void)?) {
        self.resetTransaction = resetTransaction
        self.reset = reset
    }
}

/// A property that holds a value only while a gesture runs and returns to its initial value when the gesture
/// ends, fails or is cancelled — SwiftUI's `GestureState` (ruling `GS-B`).
///
/// ```swift
/// @GestureState private var drag = Size<Pixels>(width: Pixels(0), height: Pixels(0))
/// Box().offset(x: drag.width, y: drag.height)
///     .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation })
/// ```
///
/// **Storage is a `@State` slot** (`$state<n>`, `GS-A`): the wrapper holds a `State` and seeds it by the very walk
/// `@State` uses, so a write is a state write for the content memo and the retained paths. `wrappedValue` is
/// get-only; only `updating` writes it, from the gesture arena, and the arena's finish hook resets it once
/// (`GS-C`). `projectedValue` is the wrapper itself, for `updating(_:body:)`.
@propertyWrapper
@MainActor
public struct GestureState<Value> {
    let state: State<Value>
    let control: GestureStateBox<Value>

    private init(initialValue: Value, resetTransaction: Transaction,
                 reset: (@MainActor (Value, inout Transaction) -> Void)?) {
        state = State(wrappedValue: initialValue)
        control = GestureStateBox(resetTransaction: resetTransaction, reset: reset)
    }

    /// A state that reads `wrappedValue` until a gesture writes it, and again after the gesture ends.
    public init(wrappedValue: Value) {
        self.init(initialValue: wrappedValue, resetTransaction: Transaction(), reset: nil)
    }

    /// `init(wrappedValue:)`, spelled by its initial value.
    public init(initialValue: Value) {
        self.init(initialValue: initialValue, resetTransaction: Transaction(), reset: nil)
    }

    /// A state whose reset is made in `resetTransaction` (an animation here animates the return).
    public init(wrappedValue: Value, resetTransaction: Transaction) {
        self.init(initialValue: wrappedValue, resetTransaction: resetTransaction, reset: nil)
    }

    /// `init(wrappedValue:resetTransaction:)`, spelled by its initial value.
    public init(initialValue: Value, resetTransaction: Transaction) {
        self.init(initialValue: initialValue, resetTransaction: resetTransaction, reset: nil)
    }

    /// A state whose `reset` closure runs once at the reset, with the value before it, and may set the reset's
    /// transaction.
    public init(wrappedValue: Value, reset: @escaping @MainActor (Value, inout Transaction) -> Void) {
        self.init(initialValue: wrappedValue, resetTransaction: Transaction(), reset: reset)
    }

    /// `init(wrappedValue:reset:)`, spelled by its initial value.
    public init(initialValue: Value, reset: @escaping @MainActor (Value, inout Transaction) -> Void) {
        self.init(initialValue: initialValue, resetTransaction: Transaction(), reset: reset)
    }

    /// The gesture's current value, or the initial value when no gesture is writing it. Get-only.
    public var wrappedValue: Value { state.wrappedValue }

    /// The state itself, for `Gesture.updating(_:body:)`; its storage is shared with the property.
    public var projectedValue: GestureState<Value> { self }
}

extension GestureState where Value: ExpressibleByNilLiteral {
    /// An optional state that reads `nil` until a gesture writes it.
    public init(resetTransaction: Transaction = Transaction()) {
        self.init(initialValue: nil, resetTransaction: resetTransaction, reset: nil)
    }

    /// An optional state with a `reset` closure.
    public init(reset: @escaping @MainActor (Value, inout Transaction) -> Void) {
        self.init(initialValue: nil, resetTransaction: Transaction(), reset: reset)
    }
}

extension GestureState: BindableState {
    func bind(to table: StateTable, id: GlobalElementID, slot: Int) {
        state.bind(to: table, id: id, slot: slot)
    }

    /// Runs one `updating` body for an event (`GS-D`): from the event's base, writing the copy back always, under
    /// the body's transaction only when it set an animation (`GS-F`).
    func update<GestureValue>(_ value: GestureValue,
                              body: @MainActor (GestureValue, inout Value, inout Transaction) -> Void) {
        guard let table = state.box.table, let slot = state.box.resolvedSlot else { return }
        let committed = table.peek(slot, as: Value.self) ?? state.initialValue
        let batch = GestureStateBatch.current
        if batch == 0 || control.batch != batch || control.baseSlot != slot {
            control.batch = batch
            control.baseSlot = slot
            control.base = committed
        }
        var copy = control.base ?? committed
        var transaction = Transaction()
        body(value, &copy, &transaction)
        write(copy, in: transaction, table: table, slot: slot)
        control.dirty.insert(slot)
    }

    /// Returns the slot to its initial value, once, and only if a gesture wrote it since (`GS-C`, `GS-D`).
    func finish() {
        guard let table = state.box.table, let slot = state.box.resolvedSlot,
              control.dirty.remove(slot) != nil else { return }
        let current = table.peek(slot, as: Value.self) ?? state.initialValue
        var transaction = control.resetTransaction
        control.reset?(current, &transaction)
        write(state.initialValue, in: transaction, table: table, slot: slot)
    }

    private func write(_ value: Value, in transaction: Transaction, table: StateTable, slot: GlobalElementID) {
        if transaction.animation != nil || transaction.disablesAnimations {
            withTransaction(transaction) { table.write(slot, value) }
        } else {
            table.write(slot, value)
        }
    }

    var identity: ObjectIdentifier { ObjectIdentifier(control) }
}

/// One `updating` attached to a gesture of value type `Value`: the body, whether it was declared after
/// `onChanged` (`GS-E`), and its state's finish hook.
struct GestureUpdate<Value> {
    let run: @MainActor (Value) -> Void
    let afterChanged: Bool
    let finish: @MainActor () -> Void
    let identity: ObjectIdentifier

    @MainActor
    init<S>(_ state: GestureState<S>, afterChanged: Bool,
            body: @escaping @MainActor (Value, inout S, inout Transaction) -> Void) {
        run = { value in state.update(value, body: body) }
        finish = { state.finish() }
        identity = state.identity
        self.afterChanged = afterChanged
    }
}

/// `changed` and every update, in declaration order (`GS-E`); `changed` itself when there are no updates.
func composeChanged<Value>(_ changed: (@MainActor (Value) -> Void)?,
                           _ updates: [GestureUpdate<Value>]) -> (@MainActor (Value) -> Void)? {
    guard !updates.isEmpty else { return changed }
    return { value in
        for update in updates where !update.afterChanged { update.run(value) }
        changed?(value)
        for update in updates where update.afterChanged { update.run(value) }
    }
}

/// One closure that finishes every distinct state of `updates`, or `nil` with none.
func composeFinished<Value>(_ updates: [GestureUpdate<Value>]) -> (@MainActor () -> Void)? {
    guard !updates.isEmpty else { return nil }
    var seen: Set<ObjectIdentifier> = []
    let finishes = updates.filter { seen.insert($0.identity).inserted }.map(\.finish)
    return { for finish in finishes { finish() } }
}

import Foundation

/// A debug-only meter of how much stack a tree's build and layout use (ruling
/// `PE-L`, spec `2026-10-06-proposal-controls-design.md` §4 items 2–4).
///
/// **Why it exists.** A debug build reserves a stack slot for every temporary a
/// builder closure or `content` getter holds, in every branch of a `switch`
/// or `if` (record §50), and element values are large — so a big app's tree
/// can overflow a thread's stack in a debug build while each of its parts
/// builds fine alone (the SMK configurator's MG-15: an 8 MB main thread
/// overflowed in `___chkstk_darwin`). `ComponentLayout`'s heap box (`PE-J`)
/// removes the part MetalUI's own records caused; what a compiler property
/// leaves (an inline `switch` over large subtrees in one builder, `PE-K`) is
/// what this measures. **`PE-L` item 4's window warning is not wired yet**:
/// its 512 KiB threshold is under re-take, because the production demo trees
/// measure above it with this meter (record §78); until then the meter is the
/// instrument of `ComponentStackTests`.
///
/// **How.** `measuring(_:)` records the stack address at its entry and the
/// lowest address any `sample()` reaches while it runs; the difference is the
/// body's high-water mark. Samples sit at the deepest points a tree reaches:
/// every `ElementBuilder` method (so a `content` getter's own frame is seen —
/// a layout-time sample misses it, because the getter has returned before its
/// children register), both `Component` layout entries (which also remember
/// the deepest `Component`'s type), and `Frame.requestNativeLeaf`. **The stack
/// grows down on every platform MetalUI supports** (arm64 and x86-64 on
/// macOS, Linux and Windows), so deeper is a smaller address.
///
/// **Main thread only, and no isolation assertion** (ruling `PE-P`): a sample
/// counts only inside an open `measuring` scope **and** on the main thread.
/// `everyProductionTreeBuildsOnAOneMegabyteThread` runs every production
/// builder on a secondary thread through an `unsafeBitCast` of a `@MainActor`
/// function; a sample that asserted isolation would trap it, and one that
/// compared that thread's stack pointer with the main thread's entry address
/// would record nonsense. So `sample()` is `nonisolated` and reads its state
/// only after `Thread.isMainThread` holds — every write is on the main thread.
///
/// **Release builds** measure nothing: `_isDebugAssertConfiguration()` is
/// false, `measuring` returns `0`, and a sample is one branch. A release
/// build's frames are a fraction of a debug build's.
enum StackMeter {
    /// The open scope's entry address, the lowest address sampled under it,
    /// and the deepest `Component` entry sampled under it.
    private struct Scope {
        var entry: UInt
        var lowest: UInt
        var deepestComponentAddress: UInt = .max
        var deepestComponent: Any.Type?
    }

    /// The innermost open scope; `nil` outside every `measuring` call.
    /// Written only on the main thread (`measuring` is `@MainActor`, and a
    /// sample writes only after its main-thread check).
    nonisolated(unsafe) private static var scope: Scope?

    /// Whether this build measures at all: debug builds only (`PE-L` item 3).
    static var isEnabled: Bool { _isDebugAssertConfiguration() }

    /// Whether a `measuring` scope is open — for tests (a sample outside every
    /// scope must not open one).
    @MainActor static var isMeasuring: Bool { scope != nil }

    /// The address of a local in this function's frame — one frame below the
    /// caller's, which is the same offset for every sample and for the entry.
    @inline(never)
    private static func stackAddress() -> UInt {
        var local: UInt8 = 0
        return withUnsafeMutablePointer(to: &local) { UInt(bitPattern: $0) }
    }

    /// Runs `body` and returns its result, the stack it used below this call
    /// in bytes (its high-water mark: entry address − lowest sampled address),
    /// and the name of the deepest `Component` it laid out.
    ///
    /// A nested call returns its own figure and folds its lowest address (and
    /// deepest component) into the enclosing scope, so the outer figure is
    /// never below the inner one.
    @MainActor
    static func measuring<R>(_ body: () throws -> R) rethrows
        -> (R, highWater: Int, deepestComponent: String?) {
        guard isEnabled else { return (try body(), 0, nil) }
        let outer = scope
        let entry = stackAddress()
        scope = Scope(entry: entry, lowest: entry)
        defer {
            // Fold this scope into the enclosing one (or close the last), on
            // the way out of a throwing body too.
            if var restored = outer, let inner = scope {
                if inner.lowest < restored.lowest { restored.lowest = inner.lowest }
                if inner.deepestComponentAddress < restored.deepestComponentAddress {
                    restored.deepestComponentAddress = inner.deepestComponentAddress
                    restored.deepestComponent = inner.deepestComponent
                }
                scope = restored
            } else {
                scope = outer
            }
        }
        let result = try body()
        let mine = scope ?? Scope(entry: entry, lowest: entry)
        return (result, entry > mine.lowest ? Int(entry - mine.lowest) : 0,
                mine.deepestComponent.map { String(reflecting: $0) })
    }

    /// Records the current stack depth in the open scope. A no-op off the
    /// main thread, outside every scope, and in a release build.
    nonisolated static func sample() {
        guard isEnabled, Thread.isMainThread, scope != nil else { return }
        let address = stackAddress()
        if address < scope!.lowest { scope!.lowest = address }
    }

    /// `sample()`, remembering `component` when this is the deepest
    /// `Component` layout entry so far in the open scope.
    nonisolated static func sample(component: Any.Type) {
        guard isEnabled, Thread.isMainThread, scope != nil else { return }
        let address = stackAddress()
        if address < scope!.lowest { scope!.lowest = address }
        if address < scope!.deepestComponentAddress {
            scope!.deepestComponentAddress = address
            scope!.deepestComponent = component
        }
    }
}

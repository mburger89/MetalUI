/// The context of one state change — SwiftUI's `Transaction` (ruling `AN-Y`;
/// probe `docs/probes/swiftui-transactions-animation.swift`, arms T1–T13).
///
/// ```swift
/// withTransaction(Transaction(animation: .linear(duration: 1))) { model.width = 200 }
/// Box().animation(.easeOut(duration: 0.2), value: model.isOpen)
/// Box().transaction { $0.animation = nil }
/// ```
///
/// **Two fields**: the `animation` a changed value interpolates with (`nil`
/// snaps), and `disablesAnimations`, which suppresses every
/// `.animation(_:value:)` below it (T8, T8b) and never the transaction's own
/// animation (T8c).
///
/// **One root transaction reaches one build — divergence 99, kept.**
/// `withTransaction` and `withAnimation` park the transaction for the next
/// frame build (`AN-B`/`AN-C`, unchanged); a frame rebuilds the whole tree, so
/// two calls in one interval, or a nested call, animate every change of that
/// build with the one parked transaction, where SwiftUI attributes each write
/// to its own call (T9, T10). `.animation(_:value:)` is the per-value remedy,
/// and it matches SwiftUI.
///
/// **`Sendable`, not `Equatable`** (`AN-AH` item 5). SwiftUI's `Transaction` is
/// neither (the probe header's typecheck). Adding `Equatable` later is
/// additive and removing it would break callers, so it is left off;
/// `Sendable` is additive beyond SwiftUI, and the frame's value-typed stack
/// and a `Binding`'s stored copy want it.
public struct Transaction: Sendable {
    /// The animation a value changed under this transaction interpolates with,
    /// or `nil` to snap.
    public var animation: Animation?

    /// Whether `.animation(_:value:)` below is suppressed. `false` by default.
    /// The transaction's own `animation` still applies (T8, T8c).
    public var disablesAnimations: Bool = false

    /// An empty transaction: no animation, animations not disabled.
    public init() {}

    /// A transaction carrying `animation`.
    public init(animation: Animation?) {
        self.animation = animation
    }
}

/// Runs `body` with `transaction` as the ambient transaction and parks it for
/// the next frame build — `withAnimation`'s mechanism exactly (`AN-B`, `AN-C`),
/// with the transaction's `disablesAnimations` parked beside its animation
/// under the same rule (T5, T5n; ruling `AN-Y` item 2).
///
/// Returns what `body` returns and rethrows what it throws (SwiftUI's
/// signature).
@MainActor
public func withTransaction<Result>(_ transaction: Transaction,
                                    _ body: () throws -> Result) rethrows -> Result {
    try parkTransaction(transaction, body)
}

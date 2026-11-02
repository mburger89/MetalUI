import MetalUICore
import MetalUILayout
import MetalUIPlatform

// SwiftUI's `DropDelegate` family (ruling `DE-A`, reversing `DN-A` item 2 for
// the delegate): `onDrop(of:delegate:)` plus the delegate protocol, its
// `DropProposal`/`DropOperation` and `DropInfo`. `NSItemProvider` is stood in
// for by `DropItem`, as `PasteButton` already does (`CP-B`, `CP-D`). Evidence:
// `docs/probes/swiftui-drop-delegate.swift`.

/// What a drop delegate proposes for the drag over it — SwiftUI's
/// `DropOperation`, without the macOS 26 cases (`delete`, `alias`, the `Set`
/// conformance; ruling `DE-I`).
public enum DropOperation: Sendable, Hashable {
    /// Refuses the drag for good: nothing more is asked until it leaves
    /// (the cursor shows no drop, `dropUpdated` stops, nothing is performed).
    case cancel
    /// Refuses the drag at this position; `dropUpdated` keeps coming, so a
    /// later position can accept.
    case forbidden
    /// Accepts the drag as a copy.
    case copy
    /// Accepts the drag as a move — the source may remove the original.
    case move
}

/// A delegate's answer to a drag moving over it — SwiftUI's `DropProposal`,
/// without the macOS 26 initialisers (ruling `DE-I`).
public struct DropProposal: Sendable {
    /// The proposed operation.
    public var operation: DropOperation

    /// A proposal of `operation`.
    public init(operation: DropOperation) { self.operation = operation }
}

/// What a drag looks like to a drop delegate — SwiftUI's `DropInfo`, with the
/// differences of divergence 1056: the location is a `Point<Pixels>` local to
/// the destination, types are `ContentType`s and items are `DropItem`s, read
/// synchronously. It has no public initialiser; the delegate is handed one.
///
/// While a drag from outside the window hovers on SDL the items are not known
/// yet (ruling `DN-M`): ``hasItemsConforming(to:)`` answers `true` and
/// ``itemProviders(for:)`` is empty until `performDrop` (divergence amendment
/// 102).
public struct DropInfo {
    /// The pointer, in the destination's own coordinate space.
    public let location: Point<Pixels>
    let items: [DropItem]?

    init(location: Point<Pixels>, items: [DropItem]?) {
        self.location = location
        self.items = items
    }

    /// Whether some dragged item is, or conforms to, one of `types`.
    public func hasItemsConforming(to types: [ContentType]) -> Bool {
        guard let items else { return true }
        return items.contains { DropDestinationTarget.match($0, types) != nil }
    }

    /// Every dragged item that is, or conforms to, one of `types`, to read
    /// with `DropItem.load`; empty while the items are not known.
    public func itemProviders(for types: [ContentType]) -> [DropItem] {
        (items ?? []).filter { DropDestinationTarget.match($0, types) != nil }
    }
}

/// A drop destination's behaviour, as a value — SwiftUI's `DropDelegate`
/// (ruling `DE-A`). Only ``performDrop(info:)`` is required.
///
/// Call order (ruling `DE-B`): entering a destination runs ``validateDrop(info:)``,
/// then — if it answered `true` — ``dropEntered(info:)`` and ``dropUpdated(info:)``;
/// every pointer move runs one ``dropUpdated(info:)``; a release runs
/// ``dropUpdated(info:)`` then ``performDrop(info:)`` and no ``dropExited(info:)``;
/// leaving runs ``dropExited(info:)`` alone — also after a `validateDrop`
/// that answered `false`. A drag whose items match none of the declared types
/// reaches no callback. Every method runs from input, on the main actor.
@MainActor
public protocol DropDelegate {
    /// Whether the drag may be dropped here; `false` runs neither
    /// `dropEntered` nor `dropUpdated` nor `performDrop`. Default `true`.
    func validateDrop(info: DropInfo) -> Bool
    /// The drag entered the destination (after a `true` `validateDrop`). Default: nothing.
    func dropEntered(info: DropInfo)
    /// The drag moved over, or was released on, the destination. The proposal
    /// decides the cursor and whether a release performs: `nil` proposes `.copy`.
    func dropUpdated(info: DropInfo) -> DropProposal?
    /// The drag left the destination without dropping. Default: nothing.
    func dropExited(info: DropInfo)
    /// The drag was released on the destination with a copy or move proposed.
    /// The answer is what the platform is told.
    func performDrop(info: DropInfo) -> Bool
}

extension DropDelegate {
    /// `true`.
    public func validateDrop(info: DropInfo) -> Bool { true }
    /// Nothing.
    public func dropEntered(info: DropInfo) {}
    /// `nil`.
    public func dropUpdated(info: DropInfo) -> DropProposal? { nil }
    /// Nothing.
    public func dropExited(info: DropInfo) {}
}

extension StyledElement {
    /// Makes this element a drop destination driven by `delegate` for items
    /// conforming to `types` — SwiftUI's `onDrop(of:delegate:)` (ruling `DE-A`).
    ///
    /// Sets the same `Handlers.dropDestination` field as `dropDestination`, so
    /// the outermost drop modifier on one element wins, as SwiftUI's does
    /// (`DE-G`). A disabled or hidden destination is never validated (divergence
    /// 100); resolution is `DN-F`'s. Returns `Self`.
    public func onDrop(of types: [ContentType], delegate: any DropDelegate) -> Self {
        var copy = self
        copy.handlers.dropDestination = DropDestinationTarget(delegate: delegate, types: types)
        return copy
    }
}

extension ProposalElementGroup {
    /// `StyledElement.onDrop(of:delegate:)` on the proposal path: wraps once.
    public func onDrop(of types: [ContentType], delegate: any DropDelegate) -> DropDestinationModifier<Self> {
        DropDestinationModifier(content: self, target: DropDestinationTarget(delegate: delegate, types: types))
    }
}

/// A direction along which a layout is tested or a container lays out, SwiftUI's `Axis` (`VF-I`).
///
/// Introduced for ``ViewThatFits`` (`ViewThatFits(in: .horizontal)`); `ScrollView` and `ProposalScrollView` keep
/// ``ScrollAxis``. **A module that declares its own `Axis` and imports `MetalUI` sees an ambiguity** at an unqualified
/// use: qualify it (`MyModule.Axis`) or give it another name (`docs/migration.md`).
public enum Axis: Int8, CaseIterable, Sendable, Hashable {
    /// The horizontal axis.
    case horizontal
    /// The vertical axis.
    case vertical

    /// A set of axes, SwiftUI's `Axis.Set`.
    public struct Set: OptionSet, Sendable, Hashable {
        /// The bit mask: `1` horizontal, `2` vertical.
        public let rawValue: Int8

        /// The set with this raw value (`OptionSet`'s requirement).
        public init(rawValue: Int8) { self.rawValue = rawValue }

        /// The horizontal axis.
        public static let horizontal = Set(rawValue: 1 << 0)
        /// The vertical axis.
        public static let vertical = Set(rawValue: 1 << 1)

        /// The set holding the axis `axis`.
        public init(_ axis: Axis) {
            switch axis {
            case .horizontal: self = .horizontal
            case .vertical: self = .vertical
            }
        }
    }
}

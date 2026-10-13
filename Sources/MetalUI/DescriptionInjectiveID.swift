import Foundation

/// Marks id types whose `String(describing:)` is injective on values that are
/// not `==`-equal, so a `ForEach` over them names elements by description alone
/// and mints no `IdentityKey` (`FI-B`, `FI-K`). Everything else (a custom id
/// struct, an enum, a tuple, `AnyHashable`) carries its value.
///
/// Floating-point ids are marked too (description is injective on non-NaN
/// values) but keep the per-build name dedupe, because a NaN is unequal to itself.
protocol DescriptionInjectiveID {}

extension Int: DescriptionInjectiveID {}
extension Int8: DescriptionInjectiveID {}
extension Int16: DescriptionInjectiveID {}
extension Int32: DescriptionInjectiveID {}
extension Int64: DescriptionInjectiveID {}
extension UInt: DescriptionInjectiveID {}
extension UInt8: DescriptionInjectiveID {}
extension UInt16: DescriptionInjectiveID {}
extension UInt32: DescriptionInjectiveID {}
extension UInt64: DescriptionInjectiveID {}
extension String: DescriptionInjectiveID {}
extension Substring: DescriptionInjectiveID {}
extension Character: DescriptionInjectiveID {}
extension Bool: DescriptionInjectiveID {}
extension Double: DescriptionInjectiveID {}
extension Float: DescriptionInjectiveID {}
extension UUID: DescriptionInjectiveID {}

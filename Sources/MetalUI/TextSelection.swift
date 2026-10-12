/// A text field's selection, SwiftUI's `TextSelection` (macOS 15): a range of
/// the field's text, an insertion point (an empty range), or several ranges.
///
/// Bind it with `TextField(_:text:selection:)` or `TextEditor(text:selection:)`
/// (rulings `SL-A`, `SL-B`): the field writes it after each input that moved the
/// selection, and applies a value the caller writes on the next frame.
///
/// ```swift
/// @State var selection: TextSelection?
/// … TextField("Title", text: $title, selection: $selection)
/// // select everything:
/// selection = TextSelection(range: title.startIndex..<title.endIndex)
/// ```
///
/// **Availability** (ruling `SL-L`): `RangeSet` is the standard library's from
/// macOS 15, so the type and every initialiser that takes it are `@available(macOS 15, *)`
/// — SwiftUI's own availability — while the package still deploys to macOS 14. The
/// field's internal state holds the value type-erased and is not gated.
@available(macOS 15, *)
public struct TextSelection: Equatable, Hashable, Sendable {
    /// What is selected.
    public enum Indices: Equatable, Hashable, Sendable {
        /// One range; empty is an insertion point.
        case selection(Range<String.Index>)
        /// Several ranges; the field acts on the first (`SL-G`).
        case multiSelection(RangeSet<String.Index>)
    }

    /// The selected indices.
    public var indices: Indices

    /// Whether this is a single empty range — an insertion point.
    public var isInsertion: Bool {
        if case .selection(let range) = indices { return range.isEmpty }
        return false
    }

    /// Selects `range`.
    public init(range: Range<String.Index>) {
        indices = .selection(range)
    }

    /// An insertion point (caret) at `insertionPoint`.
    public init(insertionPoint: String.Index) {
        indices = .selection(insertionPoint..<insertionPoint)
    }

    /// Selects `ranges`.
    public init(ranges: RangeSet<String.Index>) {
        indices = .multiSelection(ranges)
    }

    /// Conversions performed by `offsets(of:in:)`; the work counter of test 4.19
    /// (`SL-J`). Main-actor use only.
    nonisolated(unsafe) static var conversionCount = 0

    /// The Character-offset range `selection` names in `text`: the first range of a
    /// multi-selection (`nil` with none), both ends clamped into the text and an
    /// unaligned index rounded down to a Character boundary (`SL-G`).
    static func offsets(of selection: TextSelection, in text: String) -> Range<Int>? {
        conversionCount += 1
        let range: Range<String.Index>
        switch selection.indices {
        case .selection(let r): range = r
        case .multiSelection(let set):
            guard let first = set.ranges.first else { return nil }
            range = first
        }
        let count = text.count
        func offset(_ index: String.Index) -> Int {
            if index <= text.startIndex { return 0 }
            if index >= text.endIndex { return count }
            return min(max(text.distance(from: text.startIndex, to: index), 0), count)
        }
        let lower = offset(range.lowerBound), upper = offset(range.upperBound)
        return min(lower, upper)..<max(lower, upper)
    }

    /// The selection over Character offsets `offsets` of `text`, clamped; empty is an
    /// insertion point.
    init(offsets: Range<Int>, in text: String) {
        let count = text.count
        func index(_ offset: Int) -> String.Index {
            text.index(text.startIndex, offsetBy: min(max(offset, 0), count))
        }
        let lower = index(offsets.lowerBound), upper = index(offsets.upperBound)
        self = lower == upper ? TextSelection(insertionPoint: lower) : TextSelection(range: lower..<upper)
    }
}

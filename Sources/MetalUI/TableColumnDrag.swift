// A column divider's drag (`TBL-R`, record 391): resizes the column it ends, writing the table's `columnState` only when the
// clamped width changes. Reorder is not built: headers do not reorder by default in SwiftUI (`TBL-S`, probe arm `R1`).

/// The divider drag in progress. A reference held by the table's `columnState`, so moving it is not a state write: the column the
/// drag is on, the width it started at and the width last written.
final class TableResizeDragBox: @unchecked Sendable {
    var key: TableColumnKey?
    var start = 0.0
    var last = 0.0
}

/// What a resizable column's divider does: the column, the width it has in this build, its limits and where to write.
struct TableResizeDrag {
    var key: TableColumnKey
    /// The column's resolved width in the build that made this handler (the drag's start, if it begins now).
    var width: Double
    var spec: TableColumnWidthSpec
    var state: Binding<TableColumnState>

    @MainActor func gesture() -> DragGesture {
        let drag = state.wrappedValue.resizeDrag
        let key = key, width = width, spec = spec, state = state
        return DragGesture(minimumDistance: Pixels(0))
            .onChanged { value in
                if drag.key != key { drag.key = key; drag.start = width; drag.last = width }
                let wanted = drag.start + Double(value.translation.width.value)
                let low = spec.min ?? TableMetrics.defaultMinWidth
                let clamped = Swift.min(Swift.max(wanted, low), spec.max ?? .infinity)
                // Only a changed width is a write (`FP-U`: a drag that moves nothing draws nothing).
                guard clamped != drag.last else { return }
                drag.last = clamped
                var next = state.wrappedValue
                next.widths[key] = clamped
                state.wrappedValue = next
            }
            .onEnded { _ in drag.key = nil }
            .onCancelled { drag.key = nil }
    }
}

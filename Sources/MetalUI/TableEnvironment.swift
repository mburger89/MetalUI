import MetalUICore

// The environment a `Table` reads (`TBL-V`, record 389): column header visibility, SwiftUI's `tableColumnHeaders(_:)`.

struct TableColumnHeadersKey: EnvironmentKey {
    static var defaultValue: Visibility { .automatic }
}

extension EnvironmentValues {
    /// Whether a `Table` below shows its column header row (`tableColumnHeaders(_:)`). `.automatic` shows it.
    var tableColumnHeaders: Visibility {
        get { self[TableColumnHeadersKey.self] }
        set { setCustom(TableColumnHeadersKey.self, newValue, reading: .value(newValue)) }
    }
}

extension ElementGroup {
    /// Shows or hides the column headers of every `Table` below this content: SwiftUI's `tableColumnHeaders(_:)`. `.hidden` removes
    /// the header row, so row 0 sits at the top of the table; `.automatic` and `.visible` show it.
    public func tableColumnHeaders(_ visibility: Visibility) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { $0.tableColumnHeaders = visibility })
    }
}

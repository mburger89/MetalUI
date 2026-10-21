import MetalUI

/// The sidebar's fill. An app palette is a `ThemeColorKey`: one value for
/// both schemes through `Color(light:dark:)`, read anywhere a colour goes.
struct SidebarFill: ThemeColorKey {
    static let defaultValue = Color(light: Color(red: 0.94, green: 0.94, blue: 0.96),
                                    dark: Color(red: 0.12, green: 0.12, blue: 0.14))
}

/// The accent the charts draw with.
struct ChartInk: ThemeColorKey {
    static let defaultValue = Color(light: Color(red: 0.16, green: 0.42, blue: 0.9),
                                    dark: Color(red: 0.45, green: 0.68, blue: 1))
}

extension Color {
    /// The sidebar's fill.
    static let sidebarFill = Color(SidebarFill.self)
    /// The charts' ink.
    static let chartInk = Color(ChartInk.self)
}

extension NotesModel {
    /// A `Binding` to one of the model's properties, so a control can write it.
    /// A binding write is a model write: it runs from input.
    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<NotesModel, Value>) -> Binding<Value> {
        nonisolated(unsafe) let keyPath = keyPath
        return Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}

/// Padding of `horizontal` points left and right and `vertical` top and bottom
/// (`Edges` has an all-sides initialiser and a per-side one, not this).
func inset(_ horizontal: Float, _ vertical: Float) -> Edges<Pixels> {
    Edges(top: Pixels(vertical), right: Pixels(horizontal), bottom: Pixels(vertical), left: Pixels(horizontal))
}

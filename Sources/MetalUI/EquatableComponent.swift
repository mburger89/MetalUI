/// A `Component` whose `content` is not evaluated again while its value is
/// unchanged (SwiftUI's `View.equatable()`, `IV-B`); made by
/// ``Component/equatable()``.
///
/// The component keeps its identity level, `@State` slots and cursor index: the
/// wrapper adds none of its own. Everything after the `content` getter —
/// `requestGroupLayout`, layout, prepaint, paint — runs exactly as for the
/// bare component, so only the getter's work is saved.
///
/// There is no initialiser: make one with `equatable()`.
public struct EquatableComponent<C: Component & Equatable>: ElementGroup {
    var component: C

    init(component: C) { self.component = component }

    public typealias GroupLayout = ComponentLayout<C>
    public typealias GroupPrepaint = ComponentPrepaint<C>

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], ComponentLayout<C>) {
        let id = component.enterComponent(under: parent, at: &cursor, pass: &pass)
        let table = pass.frame.stateTable
        let store = table.contentMemos
        var materialized: C.Content
        if let shape = StateBinder.memoShape(of: C.self), !shape.refused {
            let stateIDs = shape.stateOrdinals.map {
                GlobalElementID.child(of: id, at: $0, name: ElementID("$state\($0)"))
            }
            materialized = store.materialize(component, id: id, stateIDs: stateIDs, table: table) {
                component.content
            }
        } else {
            store.noteRefusal()
            materialized = component.content
        }
        return component.finishComponent(&materialized, id: id, pass: &pass)
    }

    public mutating func prepaintGroup(layout: inout ComponentLayout<C>,
                                       pass: inout PrepaintPass) -> ComponentPrepaint<C> {
        component.prepaintGroup(layout: &layout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout ComponentLayout<C>,
                                    prepaint: inout ComponentPrepaint<C>,
                                    pass: inout PaintPass) {
        component.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension Component where Self: Equatable {
    /// Skips this component's `content` getter while its value is `==` to the
    /// value of its last evaluation (SwiftUI's `View.equatable()`).
    ///
    /// The content is a function of the value, the component's own `@State` and
    /// the `@Observable` properties it reads; `==` decides for every stored
    /// property, closures and class references included. An `@Observable` read
    /// of the last evaluation that changes, or a write to the component's own
    /// `@State`, re-evaluates it whatever `==` says. A `Binding` input is a value:
    /// if `content` reads `binding.wrappedValue`, include it in `==`. A component
    /// that declares `@Environment` or `@FocusState` is never skipped (it is
    /// evaluated every frame and counted as a refusal).
    ///
    /// Only the getter is skipped: layout, prepaint and paint of the content run
    /// as usual, so the result is pixel-identical to the unmemoized component.
    public func equatable() -> EquatableComponent<Self> {
        EquatableComponent(component: self)
    }
}

import MetalUICore

// Opening a `Menu` from code (ruling `MN-AK`, Alloy gap G9, record 241): the public spellings. The binding is the
// `Menu.isPresented` storage (`MenuContent.swift`); noting it in layout and reconciling it after the frame is
// `PullDownMenu.swift`'s. Class `M`: SwiftUI has no way to open a `Menu` from code.

// MARK: - Opening a `Menu` from code (ruling `MN-AK`, Alloy gap G9)

extension Menu {
    /// A menu whose open state is `isPresented` — **MetalUI-only (class M); SwiftUI has no way to open a `Menu`
    /// from code.** Writing `true` from input (a key press, a submit, a button's action) opens the menu exactly as a
    /// click on its label does — at the label's bottom-leading corner, natively where the platform shows menus and
    /// drawn elsewhere; any dismissal (an item chosen, Escape, an outside click, the native menu closing) writes
    /// `false`; a click on the label writes `true`; writing `false` while it is open closes it.
    /// The open happens after the frame that read `true`, never inside a phase (`MN-AK`).
    @MainActor
    public init(isPresented: Binding<Bool>, @MenuContentBuilder content: @escaping @MainActor () -> Content,
                @ElementBuilder label: () -> Label) {
        self.init(content: content, label: label)
        self.isPresented = isPresented
    }

    /// Opens this menu from code while `isPresented` is `true` and writes it `false` on every dismissal —
    /// **MetalUI-only (class M)**; see `init(isPresented:content:label:)`. Meaningful on a menu button, not on a
    /// `Menu` used as a submenu item inside another menu's content, where it does nothing.
    public func menuPresented(_ isPresented: Binding<Bool>) -> Self {
        var copy = self
        copy.isPresented = isPresented
        return copy
    }
}

extension Menu where Label == Text {
    /// A menu titled `titleKey` whose open state is `isPresented` — **MetalUI-only (class M)**; see
    /// `init(isPresented:content:label:)`. A literal is parsed as inline Markdown.
    @MainActor
    public init(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                @MenuContentBuilder content: @escaping @MainActor () -> Content) {
        self.init(titleKey, content: content)
        self.isPresented = isPresented
    }

    /// A menu titled by the `StringProtocol` value `title`, shown verbatim, whose open state is `isPresented` —
    /// **MetalUI-only (class M)**; see `init(isPresented:content:label:)`.
    @_disfavoredOverload
    @MainActor
    public init<S: StringProtocol>(_ title: S, isPresented: Binding<Bool>,
                                   @MenuContentBuilder content: @escaping @MainActor () -> Content) {
        self.init(title, content: content)
        self.isPresented = isPresented
    }
}

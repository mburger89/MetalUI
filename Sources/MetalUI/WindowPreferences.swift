import Foundation

// The window-preference modifiers (rulings `AS-D`, `AS-G`; spec
// `docs/superpowers/specs/2026-10-08-app-shell-design.md` §1.2). Each is an
// `EnvironmentScope` — layout- and identity-transparent, proposal content
// keeping its type — whose write changes no value and reports to the frame
// after its content builds. Like `.preferredColorScheme`, a legacy decoration
// directly after one does not compile (`EV-B`), and none can be a window's
// root: write it inside the root's first container (divergence 120, `AS-N`).

extension ElementGroup {
    /// The window's title while this content is present — SwiftUI's
    /// `navigationTitle(_:)`, which on macOS with no navigation container is
    /// the window's title (ruling `AS-D` item 2, probe `swiftui-app-shell.swift`
    /// `N1`). It beats `Window.title`, which shows again when it leaves.
    ///
    /// **Precedence** (`N2`, `N5`): the first title reported in post-order —
    /// an inner title beats an enclosing one, the first of two siblings beats
    /// the second. In the window's first presented frame; followed when it
    /// changes. The `Text`, `LocalizedStringKey`, `Binding` and builder
    /// overloads are not offered.
    public func navigationTitle<S: StringProtocol>(_ title: S) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .navigationTitle(String(title)))
    }

    /// The file this window represents while this content is present —
    /// SwiftUI's `navigationDocument(_:)` (ruling `AS-D` item 3, probe `N3`,
    /// `N4`): AppKit's proxy icon and path menu (`NSWindow.representedURL`).
    /// It beats `Window.representedURL` and never changes the title; the same
    /// precedence as ``navigationTitle(_:)``. Only a file URL reaches the
    /// platform. SDL records it. The `Transferable` overloads are not offered.
    public func navigationDocument(_ url: URL) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .navigationDocument(url))
    }

    /// Runs `action` for each URL the application is asked to open while this
    /// content is present — SwiftUI's `onOpenURL(perform:)` (ruling `AS-G`):
    /// a Finder double-click, a drop on the Dock icon, Open Recent or a URL
    /// scheme on macOS (the bundle declares the types, `docs/packaging.md`);
    /// a file dropped on the application on SDL; `App.open(_:)` for launch
    /// arguments.
    ///
    /// **Routing** (MetalUI's, divergence 176 — SwiftUI's `WindowGroup` opens
    /// a new window per open): each URL goes to one window — the key window
    /// if it has a handler, else the first open window that has one — where
    /// every handler present in its last build runs once, in **reverse
    /// post-order** (outer before inner, later sibling first), under the
    /// declaring element's dispatch, so a `@State` write lands. No window with
    /// a handler: `App.onOpenURL`. MetalUI never opens a window itself.
    public func onOpenURL(perform action: @escaping @MainActor (URL) -> Void) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .onOpenURL(action))
    }
}

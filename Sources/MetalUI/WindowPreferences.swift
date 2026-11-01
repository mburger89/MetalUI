import Foundation

// The window-preference modifiers (rulings `AS-D`, `AS-G`; spec
// `docs/superpowers/specs/2026-10-08-app-shell-design.md` §1.2). Each is an
// `EnvironmentScope` — layout- and identity-transparent, proposal content
// keeping its type — whose write changes no value and reports to the frame
// after its content builds. Since `ES-A` a legacy decoration after one lands on
// its content and one over an element can be a window's root, setting the
// window title (`AS-N`'s restriction and divergence 120 retired).

extension ElementGroup {
    /// The window's title while this content is present — SwiftUI's
    /// `navigationTitle(_:)`, which on macOS with no navigation container is
    /// the window's title (ruling `AS-D` item 2, probe `swiftui-app-shell.swift`
    /// `N1`). It beats `Window.title`, which shows again when it leaves.
    ///
    /// **Precedence** (`N2`, `N5`): the first title reported in post-order —
    /// an inner title beats an enclosing one, the first of two siblings beats
    /// the second. In the window's first presented frame; followed when it
    /// changes. A `Binding<String>` (an editable title) and the builder
    /// overload (unavailable on macOS in SwiftUI) are not offered (`AE-A`).
    @_disfavoredOverload
    public func navigationTitle<S: StringProtocol>(_ title: S) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .navigationTitle(String(title)))
    }

    /// The window's title from a `Text` — SwiftUI's `navigationTitle(_:)` over a `Text` (ruling `AE-A`, probe
    /// `N6`): the title bar shows **plain text**, so the `Text`'s string is used and every style, font, colour
    /// and run attribute is dropped, as AppKit's `NSWindow.title` drops them in SwiftUI. Precedence as
    /// `navigationTitle(_:)`.
    public func navigationTitle(_ title: Text) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .navigationTitle(title.string))
    }

    /// The window's title from a string literal or interpolation — SwiftUI's `navigationTitle(_:)` over a
    /// `LocalizedStringKey` (ruling `AE-A`, probe `N7`). MetalUI has no string tables (`RT-C` item 5, divergence
    /// 151): the key is not looked up, its Markdown is parsed and shown as plain text — `"Lit **bold**"` reads
    /// `Lit bold`, as SwiftUI's does. A string literal now lands here rather than on the `StringProtocol`
    /// overload, as in SwiftUI; a `String` value still reaches that one and is shown as written.
    public func navigationTitle(_ titleKey: LocalizedStringKey) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .navigationTitle(Text(titleKey).string))
    }

    /// The line under the window's title while this content is present — SwiftUI's `navigationSubtitle(_:)`
    /// (ruling `AE-B`; `NSWindow.subtitle` on AppKit, probe `N8`). **Precedence is pre-order, unlike the
    /// title's** (`N9`, `N12`, `N13`): an enclosing subtitle beats an inner one and the first of two siblings
    /// beats the second. It is empty again when the content leaves. **SDL has no subtitle** and records it
    /// (divergence 1035).
    @_disfavoredOverload
    public func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .navigationSubtitle(String(subtitle)))
    }

    /// The subtitle from a `Text` — plain text, every style dropped (ruling `AE-B`, probe `N11`).
    public func navigationSubtitle(_ subtitle: Text) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .navigationSubtitle(subtitle.string))
    }

    /// The subtitle from a string literal or interpolation — a `LocalizedStringKey` without string tables,
    /// its Markdown shown as plain text, as `navigationTitle(_:)` does (ruling `AE-B`).
    public func navigationSubtitle(_ subtitleKey: LocalizedStringKey) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .navigationSubtitle(Text(subtitleKey).string))
    }

    /// Whether the user can dismiss the window while this content is present — SwiftUI's
    /// `windowDismissBehavior(_:)` (macOS 15; ruling `AE-D`, probes `D0`…`D6`): `.disabled` disables the close
    /// button, ⌘W and `performClose()`; `.enabled` and `.automatic` leave the window closable. It is a static
    /// switch, not a veto (`Window.onCloseRequest` is not asked). **Precedence is post-order, as the
    /// title's** (`D2`…`D4`): an inner behavior beats an enclosing one, the first sibling beats the second;
    /// it reverts when the content leaves. `Window.close()`, the app's quit walk and the platform's own
    /// `close()` are not dismissals and still close the window. On SDL the system title bar's button stays
    /// drawn and `Window` refuses the request it raises (divergence 1036).
    public func windowDismissBehavior(_ behavior: WindowInteractionBehavior) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .windowDismissBehavior(behavior))
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

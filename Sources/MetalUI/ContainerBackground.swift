import MetalUICore
import MetalUIPlatform

// The window's container background (rulings `WB-A`...`WB-H`, record 285; spec
// `docs/superpowers/specs/2026-11-13-window-container-background-design.md`). SwiftUI's macOS 15
// `containerBackground(_:for:)` with the `.window` placement: the window's own background is the style —
// a material is the compositor's behind-window blur of the desktop, a colour is the window's background
// colour. Alloy's request G40.

/// Where a ``ElementGroup/containerBackground(_:for:)`` style goes — SwiftUI's `ContainerBackgroundPlacement`
/// (macOS 15). Only `.window` exists: SwiftUI's other placements (`.tabView`, `.navigation`,
/// `.navigationSplitView`) are unavailable on macOS.
public struct ContainerBackgroundPlacement: Sendable, Hashable {
    enum Kind: Sendable, Hashable { case window }
    let kind: Kind

    /// The window the content is the root of.
    public static let window = ContainerBackgroundPlacement(kind: .window)
}

/// What `.containerBackground(_:for: .window)` asks for (ruling `WB-A`).
enum WindowBackdropSpec: Equatable {
    case color(Color)
    case material(Material)
}

extension Material {
    /// The platform's name for this level (`WB-B`).
    var backdropLevel: WindowBackdropMaterial {
        switch kind {
        case .ultraThin: .ultraThin
        case .thin: .thin
        case .regular: .regular
        case .thick: .thick
        case .ultraThick: .ultraThick
        case .bar: .bar
        }
    }
}

extension ElementGroup {
    /// Makes `color` the window's background while this content is present — SwiftUI's
    /// `containerBackground(_:for: .window)` (macOS 15; ruling `WB-A`). The colour is the window's own
    /// background, behind everything MetalUI draws: opaque, or translucent with the desktop showing
    /// through unblurred. It follows the colour scheme. **The first report in post-order wins**, as
    /// `navigationTitle` does, from any depth (`WB-D`); it reverts to the window's own background when the
    /// content leaves. There is no `ShapeStyle` generic (carried, `SS-G`): each style is its own overload.
    public func containerBackground(_ color: Color, for container: ContainerBackgroundPlacement)
        -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .windowBackdrop(.color(color)))
    }

    /// The `ColorToken` spelling of the `Color` overload: the token resolves with the window's scheme.
    @_disfavoredOverload
    public func containerBackground(_ token: ColorToken, for container: ContainerBackgroundPlacement)
        -> EnvironmentScope<Self> {
        containerBackground(Color(token), for: container)
    }

    /// Makes `material` the window's background: on AppKit the desktop behind the window, blurred and
    /// tinted by the system (a behind-window `NSVisualEffectView` under MetalUI's content, the window
    /// non-opaque; the level maps as `WB-B` records), so a translucent panel drawn over it shows the
    /// desktop through it. Under Reduce Transparency it is the opaque grey of the material (`WB-F`,
    /// `Material.opaqueColor`, as every material site is). **On SDL there is no compositor blur**: the
    /// window is filled with that same opaque grey (`WB-C`, divergence 241). Applying and removing work
    /// at run time; precedence as ``containerBackground(_:for:)-(Color,_)``.
    public func containerBackground(_ material: Material, for container: ContainerBackgroundPlacement)
        -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .windowBackdrop(.material(material)))
    }
}

extension Window {
    /// Resolves the last build's window backdrop against the window's scheme and Reduce Transparency, and
    /// tells the platform when the answer changed (`WB-A`, `WB-C`, `WB-F`). A window that never set one
    /// compares `.none` with `.none` and does nothing — no platform call, no redraw (`WB-G`).
    func reconcileWindowBackdrop() {
        var wanted = WindowBackdrop.none
        var fallback: Color?
        if let spec = shell.treeBackdrop {
            var env = environment
            env.colorScheme = colorScheme
            env.theme = theme
            switch spec {
            case .color(let color):
                let c = color.resolve(in: env)
                wanted = .color(red: c.red, green: c.green, blue: c.blue, alpha: c.opacity)
                fallback = Color(srgb: c.red, c.green, c.blue, c.opacity)
            case .material(let material):
                let opaque = material.opaqueColor(in: colorScheme)
                let c = opaque.resolve(in: env)
                fallback = opaque
                wanted = accessibilityReduceTransparency
                    ? .color(red: c.red, green: c.green, blue: c.blue, alpha: 1)
                    : .material(material.backdropLevel)
            }
        }
        guard wanted != shell.sentBackdrop else {
            // The same ask, a different grey (a scheme change): the fill `Window` paints follows it (`WB-C`).
            if wanted != .none, !shell.backdropHonoured, fallback != shell.backdropFallback {
                shell.backdropFallback = fallback
                setNeedsRedraw()
            }
            return
        }
        shell.sentBackdrop = wanted
        shell.backdropHonoured = platformWindow.setWindowBackdrop(wanted) && wanted != .none
        shell.backdropFallback = shell.backdropHonoured || wanted == .none ? nil : fallback
        setNeedsRedraw()
    }
}

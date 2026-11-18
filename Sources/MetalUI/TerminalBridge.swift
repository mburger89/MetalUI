import MetalUICore
import MetalUITextSystem

// What `MetalUITerminalUI` reads from a paint pass that the public API does not expose (`TRM-BA`). `package`: the
// terminal view is in this package and in no MetalUI target's dependencies. Nothing here is public.

extension PaintPass {
    /// The frame's device pixels per point.
    package var terminalScaleFactor: Float { frame.scaleFactor }

    /// The frame's text system, which shapes and rasterizes the terminal's glyphs.
    package var terminalTextSystem: any TextSystem { frame.textSystem }

    /// The font the terminal draws in: the environment's `.font(_:)` at this position, else the system face's
    /// monospaced design at 13 points (a terminal with no font modifier must still be monospace).
    package var terminalFont: FontDescriptor {
        let font = frame.environmentTop.font ?? .system(size: 13, design: .monospaced)
        return font.descriptor()
    }

    /// Whether the window is active (key) at this position; an inactive window shows the unfocused cursor.
    package var terminalWindowIsActive: Bool { frame.environmentTop.controlActiveState != .inactive }

    /// `color` resolved at this position as 8-bit sRGB plus an alpha in 0...1.
    package func terminalRGBA(_ color: Color) -> (r: UInt8, g: UInt8, b: UInt8, a: Float) {
        let rgba = frame.resolve(color).toRgba()
        func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return (byte(rgba.r), byte(rgba.g), byte(rgba.b), rgba.a)
    }
}

extension PrepaintPass {
    /// Publishes a read-only multi-line text area node at `id` while an accessibility client is present (`TRM-BH`):
    /// `value()` is read now, and again by the window after every surface-only frame (which builds nothing), so output
    /// reaches the client without a rebuild. With no client this is one `Bool` read.
    package func terminalDeclareAccessibility(_ id: GlobalElementID, bounds: Bounds<Pixels>, label: String,
                                              value: @escaping @MainActor () -> String) {
        guard frame.collectsAccessibility else { return }
        var node = AXNode()
        node.role = .textArea
        node.label = label
        node.value = value()
        frame.recordAccessibility(text: nil, declared: node, at: bounds, id: id)
        frame.liveAccessibilityValues[id] = value
    }
}

extension TextMeasurer {
    /// The frame's text system (nil in a bare environment).
    package var terminalTextSystem: (any TextSystem)? { box?.system }
}

extension Optional where Wrapped == Font {
    /// The font a terminal draws in: this, else the system face's monospaced design at 13 points.
    package var terminalDescriptor: FontDescriptor {
        (self ?? .system(size: 13, design: .monospaced)).descriptor()
    }
}

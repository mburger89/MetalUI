import MetalUI
import MetalUICore

// Accessibility display settings (R3-10 item 7; rulings `AD-A`...`AD-L`; human checks AD1-AD8): a
// panel that shows every value the window stamps, live. The values have no built-in reader
// (divergences 1076-1079), so this panel is the only place a change is visible.

/// One row per display value, read through `@Environment` exactly as an author's view would.
struct LooksAccessibilityDisplay: Component {
    @Environment(\.colorSchemeContrast) var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiate
    @Environment(\.accessibilityInvertColors) var invert
    @Environment(\.accessibilityShowBorders) var borders
    @Environment(\.accessibilityDimFlashingLights) var flashing
    @Environment(\.accessibilityPlayAnimatedImages) var animated
    @Environment(\.legibilityWeight) var weight
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(2)) {
            Text("colorSchemeContrast: \(contrast == .increased ? "increased" : "standard")").font(size: 12)
            Text("accessibilityDifferentiateWithoutColor: \(String(differentiate))").font(size: 12)
            Text("accessibilityInvertColors: \(String(invert))").font(size: 12)
            Text("accessibilityShowBorders: \(String(borders))").font(size: 12)
            Text("accessibilityDimFlashingLights: \(String(flashing))").font(size: 12)
            Text("accessibilityPlayAnimatedImages: \(String(animated))").font(size: 12)
            Text("legibilityWeight: \(weight.map { $0 == .bold ? "bold" : "regular" } ?? "nil")").font(size: 12)
        }
    }
}

/// The demo, reached with `METALUI_ACCESSIBILITY_DEMO=1 swift run MetalUIDemo`: a root of its own holding
/// the panel. **Not under `looksDemoContent()`**: its pins read the looks layout
/// (`theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges` finds the stepper's hitboxes and failed
/// with the panel added), the same reason as `liquidGlassDemoContent()`.
@MainActor
public func accessibilityDisplayDemoContent() -> some Element {
    accessibilityDisplayCard()
}

/// The panel with its heading. **Its own function** (Windows' 1 MB stack, `CI-AI`).
@MainActor
@inline(never)
func accessibilityDisplayCard() -> some Element {
    VStack(alignment: .leading, spacing: Pixels(8)) {
        Text("Accessibility display settings — human checks AD1–AD8").font(size: 16)
        LooksAccessibilityDisplay()
    }
    .padding(Pixels(24))
}

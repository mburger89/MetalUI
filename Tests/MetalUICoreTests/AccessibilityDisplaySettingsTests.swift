import Testing
import MetalUICore

// R3-10 item 7 (`AD-B`): the portable value types. SwiftUI's side is
// `docs/probes/swiftui-accessibility-display.swift`, arms A and V0.

/// **1** (V0). A default-constructed `AccessibilityDisplaySettings` is a bare SwiftUI
/// `EnvironmentValues()`'s reading -- standard contrast, every flag off, and
/// `playAnimatedImages` **false** (the plan guessed true; V0 read false). Mutations: the
/// `playAnimatedImages` default `true`; the `colorSchemeContrast` default `.increased`.
@Test func theSettingsDefaultToSwiftUIsBareValuesV0() {
    let bare = AccessibilityDisplaySettings()
    #expect(bare.colorSchemeContrast == .standard)
    #expect(bare.differentiateWithoutColor == false)
    #expect(bare.invertColors == false)
    #expect(bare.showBorders == false)
    #expect(bare.dimFlashingLights == false)
    #expect(bare.playAnimatedImages == false, "V0: a bare EnvironmentValues() reads playAnimatedImages false")
    #expect(bare == AccessibilityDisplaySettings(colorSchemeContrast: .standard, differentiateWithoutColor: false,
                                                 invertColors: false, showBorders: false, dimFlashingLights: false,
                                                 playAnimatedImages: false))
}

/// **2** (A). `ColorSchemeContrast` is `.standard` then `.increased` (SwiftUI's order,
/// `CaseIterable`); `LegibilityWeight` is `.regular` and `.bold`. Mutation: swap the two
/// `ColorSchemeContrast` cases.
@Test func colorSchemeContrastCasesAreSwiftUIsInOrder() {
    #expect(ColorSchemeContrast.allCases == [.standard, .increased])
    #expect(Set([LegibilityWeight.regular, .bold]).count == 2)
}

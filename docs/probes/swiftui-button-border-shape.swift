// SwiftUI probe: `buttonBorderShape(_:)` and `ButtonBorderShape` (Alloy gap G46, ruling `BY-L`, record 294).
//
// HOW TO RUN (a type-check: the evidence is that every spelling MetalUI offers compiles against SwiftUI's):
//
//   xcrun swiftc -typecheck docs/probes/swiftui-button-border-shape.swift
//
// RECORDED OUTPUT (macOS 27 SDK, 2026-11-13, agent session): no diagnostics. The declarations, read from
// `SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface` (`xcrun --show-sdk-path`):
//
//   extension View { func buttonBorderShape(_ shape: ButtonBorderShape) -> some View }   // iOS 15, macOS 12
//   struct ButtonBorderShape: Equatable, Sendable {
//     static let automatic                                  // macOS 12
//     static let capsule                                    // macOS 14
//     static let roundedRectangle                           // macOS 12
//     static func roundedRectangle(radius: CGFloat)         // macOS 14
//     static let circle                                     // macOS 14
//   }
//   extension ButtonBorderShape: Shape, InsettableShape     // macOS 14
//   extension Shape where Self == ButtonBorderShape { static var buttonBorder: ButtonBorderShape }
//   the modifier is `environment(\._buttonBorderShape, shape)`, an internal environment value.
//
// BO0 below: the five spellings, written as MetalUI's tests write them. NOT MEASURED: how a `.circle` on a non-square button
// is drawn, and which of `Menu`, `Picker(.menu)` and `Picker(.segmented)` honour the modifier on macOS: every offscreen
// capture on macOS 27 is blank (`swiftui-segmented-thumb.swift`, record 260), so MetalUI follows the documented rule that
// the bordered button styles read it, and gives the segmented picker its own MetalUI-only modifier (`SD-E`).
import SwiftUI

@available(macOS 14, *)
struct BO0: View {
    var body: some View {
        VStack {
            Button("a") {}.buttonStyle(.bordered).buttonBorderShape(.automatic)
            Button("b") {}.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            Button("c") {}.buttonBorderShape(.roundedRectangle)
            Button("d") {}.buttonBorderShape(.roundedRectangle(radius: 9))
            Button("e") {}.buttonBorderShape(.circle)
            Menu("m") { Button("x") {} }.buttonBorderShape(.capsule)
        }
        .buttonBorderShape(.capsule)
    }
}

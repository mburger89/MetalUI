// SwiftUI probe, arm H: which concrete ShapeStyle a leading-dot static infers
// in a generic `S: ShapeStyle` position — the parameter shape of SwiftUI's
// `foregroundStyle(_:)`, `background(_:)`, `fill(_:)`, `border(_:)`. Evidence
// for ruling CR-U (divergence 119) in
// docs/superpowers/2026-10-03-colour-decisions.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-colour-hierarchical.swift -o /tmp/colour-h
//   /tmp/colour-h
//
// POSITIVE CONTROL: H0, an explicit `Color.secondary`, must read "Color".
// SEPARATING ARMS: H1/H2 (`.secondary`, `.primary`) against H3 (`.red`): the
// same leading-dot spelling picks a different type depending on the static.
// H4 (`.tint`) shows a third style type. This probe measures the TYPE only;
// how a hierarchical style renders under a tinted parent is not measured and
// not claimed.
//
// RECORDED 2026-10-03 by the colour critic session, macOS 27.0.1, Apple Swift
// 6.4 (swiftlang-6.4.0.33.1). Run three times, stdout byte-identical
// (shasum feef4aee552131499b9a3cbf44f73abcc244153b), exit 0, stderr empty:
//
//   H0 control Color.secondary -> Color
//   H1 .secondary -> HierarchicalShapeStyle
//   H2 .primary -> HierarchicalShapeStyle
//   H3 .red -> Color
//   H4 .tint -> TintShapeStyle
//
// READING: in SwiftUI, `.foregroundStyle(.secondary)` and `.primary` are
// `HierarchicalShapeStyle`, not `Color.secondary`/`Color.primary`; `.red` is a
// `Color`. MetalUI's concrete `Color` parameter (CR-E) makes the same spelling
// resolve to the `Color` statics.
import SwiftUI
func which<S: ShapeStyle>(_ s: S) -> String { String(describing: S.self) }
print("H0 control Color.secondary ->", which(Color.secondary))
print("H1 .secondary ->", which(.secondary))
print("H2 .primary ->", which(.primary))
print("H3 .red ->", which(.red))
print("H4 .tint ->", which(.tint))

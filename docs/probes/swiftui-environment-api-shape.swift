// SwiftUI probe (compile-only): which EnvironmentValues members SwiftUI lets a
// caller WRITE, and the shape of the environment API a MetalUI design copies.
// Evidence for rulings EV-C (API shape) and EV-J (platform metrics are
// read-only) in docs/superpowers/2026-09-15-environment-decisions.md.
//
// HOW TO RUN. This file is meant to FAIL typechecking; the diagnostics are the
// observation:
//
//   swiftc -typecheck -diagnostic-style=llvm docs/probes/swiftui-environment-api-shape.swift
//
// Every line marked NEGATIVE must produce exactly one error and every line
// marked CONTROL must produce none, so an error count that is not the number of
// NEGATIVE lines means the reading below is stale.
//
// RECORDED: see the bottom of this file.
import SwiftUI

struct ShapeKey: EnvironmentKey {
    static let defaultValue: Int = 0              // CONTROL: `static let` satisfies the requirement
}

extension EnvironmentValues {
    var shape: Int {                              // CONTROL: custom key through the subscript
        get { self[ShapeKey.self] }
        set { self[ShapeKey.self] = newValue }
    }
}

struct ShapeView: View {
    @Environment(\.shape) var shape               // CONTROL: the wrapper takes a key path
    @Environment(\.pixelLength) var pixelLength   // CONTROL: a get-only value is readable
    var body: some View {
        Color.clear
            .environment(\.shape, 1)                               // CONTROL
            .environment(\.isEnabled, false)                       // CONTROL: isEnabled is writable
            .environment(\.layoutDirection, .rightToLeft)          // CONTROL
            .environment(\.locale, Locale(identifier: "de_DE"))    // CONTROL
            .environment(\.dynamicTypeSize, .xLarge)               // CONTROL
            .environment(\.displayScale, 3)                        // CONTROL: displayScale is writable
            .transformEnvironment(\.shape) { $0 += 1 }             // CONTROL
            .disabled(true)                                        // CONTROL
            .dynamicTypeSize(.accessibility1)                      // CONTROL
    }
}

func writes(_ e: inout EnvironmentValues) {
    e.isEnabled = false                           // CONTROL
    e.displayScale = 1                            // CONTROL
    e.pixelLength = 1                             // NEGATIVE: get-only
}

struct NegativeView: View {
    var body: some View {
        Color.clear.environment(\.pixelLength, 1) // NEGATIVE: no WritableKeyPath
    }
}

// RECORDED 2026-09-14, macOS 26.6.2 (25G83), Apple Swift 6.4
// (swiftlang-6.4.0.33.1), `swiftc -typecheck -diagnostic-style=llvm`, exit 1.
// Output filtered to `error:` lines, paths shortened:
//
//   swiftui-environment-api-shape.swift:49:7: error: cannot assign to property: 'pixelLength' is a get-only property
//   swiftui-environment-api-shape.swift:54:33: error: cannot convert value of type 'KeyPath<EnvironmentValues, CGFloat>' to expected argument type 'WritableKeyPath<EnvironmentValues, Int>'
//
// Two errors, both on NEGATIVE lines; no CONTROL line errored.
//
// READING:
// - `EnvironmentKey` needs only `static var defaultValue: Value { get }`,
//   satisfied by `static let`; custom values go through
//   `subscript<K: EnvironmentKey>(K.Type)`.
// - `.environment(_:_:)` takes a `WritableKeyPath`, `.transformEnvironment`
//   exists, `.disabled(_:)` and `.dynamicTypeSize(_:)` are modifiers of their own.
// - `isEnabled`, `layoutDirection`, `locale`, `dynamicTypeSize` and
//   `displayScale` are writable. `pixelLength` is GET-ONLY: it cannot be
//   assigned and `.environment(\.pixelLength, …)` does not typecheck (the
//   second diagnostic names `Int` only because the literal `1` was inferred
//   after the key path failed to be writable).

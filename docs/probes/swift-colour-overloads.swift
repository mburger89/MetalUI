// Swift probe: the overload and isolation shape of MetalUI's `Color` value
// (colour item, rulings CR-E (overloads) and CR-D (isolation) in
// docs/superpowers/2026-10-03-colour-decisions.md). A language question, not a
// SwiftUI one: does the planned spelling resolve every call site the spec
// names without ambiguity, and does an `Element` conformance written on the
// primary declaration make `Color`'s statics main-actor isolated?
//
// HOW TO RUN:
//
//   xcrun swiftc -swift-version 6 docs/probes/swift-colour-overloads.swift -o /tmp/colour-overloads && /tmp/colour-overloads
//   xcrun swiftc -swift-version 6 -typecheck docs/probes/swift-colour-isolation-negative.swift
//
// `C` stands for `Color`, `Tok` for `ColorToken`, `El` for the `@MainActor`
// protocol `Element`, `Mod` for `ModifiedContent`.
//
// THE ARMS (all in this file, which must typecheck clean):
// - O1 `bg(.surface)`: both overloads viable (Tok.surface, C.surface); the
//   `@_disfavoredOverload` Tok twin loses, the call resolves to the C one.
// - O2 `bg(t)` with `t: Tok`: only the Tok twin is viable.
// - O3 `bg(.red)`: only C has `.red`.
// - O4 `sh(r: 1)`: both overloads default `color:`; the disfavored one loses.
// - O5 `fc(.surface)`, `fc(nil)`, `fc(.red)` against `fc(_: C?)`: implicit
//   member lookup looks through Optional; `fc(t)` takes the Tok twin.
// - O6 `C.red.opacity(0.5)` is a `C` (the concrete type's method beats the
//   protocol extension's `opacity(_: Float)`), while `C.red.opacity(f)` with
//   `f: Float` is the view modifier — SwiftUI's own `Color.opacity` shape.
// - O7 a static `shadow`/`background` on C coexists with the instance
//   modifiers `shadow(color:radius:)`/`background(_:)` on the same type.
// - I1 with the `El` conformance in an EXTENSION, `C.red` is a nonisolated
//   default argument and a nonisolated `static let` of a key type builds it.
//
// THE SEPARATING ARM is swift-colour-isolation-negative.swift: the same type
// with `El` on its primary declaration, which must FAIL with
// "main actor-isolated default value in a nonisolated context".
//
// RECORDED 2026-10-03, Apple Swift 6.4 (swiftlang-6.4.0.33.1), macOS 27.0.1:
//   this file: compiled clean, run exit 0, stdout exactly
//     OK: O1 bg(.surface)->C, O2 bg(tok)->Tok, O4 sh(r:)->C
//   the negative file: exit 1,
//     error: main actor-isolated default value in a nonisolated context
//   (on `nonisolated func f(_ c: C = .red)`).

@MainActor public protocol El {}
public struct Tok: Hashable, Sendable {
    public static let surface = Tok()
    public static let shadow = Tok()
    public static let background = Tok()
}
public struct C: Hashable, Sendable {
    var v: Double
    public init(v: Double) { self.v = v }
    public static let red = C(v: 1)
    public static let surface = C(v: 2)
    public static let shadow = C(v: 3)
    public static let background = C(v: 4)
    public func opacity(_ o: Double) -> C { C(v: v * o) }
}
extension C: El {}                                  // I1: conformance in an extension
public protocol Key { static var defaultValue: C { get } }
struct Brand: Key { static let defaultValue = C.red.opacity(0.5) }      // I1
nonisolated func f(_ c: C = .red) -> Double { c.v + Brand.defaultValue.v } // I1

public struct Mod<T>: El { var t: T }
extension El {
    public func shadow(color: C = .shadow, radius: Double) -> Mod<Self> { Mod(t: self) }
    @_disfavoredOverload public func shadow(color: Tok = .shadow, radius: Double) -> Mod<Self> { Mod(t: self) }
    public func background(_ c: C) -> Mod<Self> { Mod(t: self) }
    @_disfavoredOverload public func background(_ t: Tok) -> Mod<Self> { Mod(t: self) }
    public func opacity(_ f: Float) -> Mod<Self> { Mod(t: self) }
}

@MainActor struct B {
    func bg(_ c: C) -> Int { 1 }
    @_disfavoredOverload func bg(_ t: Tok) -> Int { 2 }
    func sh(color: C = .red, r: Int) -> Int { 1 }
    @_disfavoredOverload func sh(color: Tok = .surface, r: Int) -> Int { 2 }
    func fc(_ c: C?) -> Int { 1 }
    @_disfavoredOverload func fc(_ t: Tok) -> Int { 2 }
    func test() {
        let t: Tok = .surface
        let o1: Int = bg(.surface); precondition(o1 == 1)
        let o2: Int = bg(t); precondition(o2 == 2)
        _ = bg(.red)                                            // O3
        let o4: Int = sh(r: 1); precondition(o4 == 1)
        _ = (fc(.surface), fc(nil), fc(.red)); _ = fc(t)        // O5
    }
}

@MainActor func modifiers() {
    let c: C = C.red.opacity(0.5)                               // O6
    let f: Float = 0.5
    let d: Mod<C> = C.red.opacity(f)                            // O6
    let a: Mod<C> = C.red.shadow(color: .shadow, radius: 4)     // O7
    let b: Mod<C> = C.red.shadow(radius: 4)                     // O4 on a modifier
    let e: Mod<C> = C.red.background(.background)               // O7
    let t: Tok = .background
    let g: Mod<C> = C.red.background(t)                         // O2 on a modifier
    _ = (a, b, c, d, e, g)
}

// Running the file (not only typechecking it) checks WHICH overload won:
// each precondition above traps if the disfavored twin was chosen.
MainActor.assumeIsolated {
    B().test()
    modifiers()
}
print("OK: O1 bg(.surface)->C, O2 bg(tok)->Tok, O4 sh(r:)->C")

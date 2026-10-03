// Swift probe, NEGATIVE arm of swift-colour-overloads.swift (ruling CR-D):
// `Element`'s conformance written on `Color`'s PRIMARY declaration infers
// `@MainActor` for the whole type, so its statics cannot be a nonisolated
// default argument. This file must FAIL to typecheck.
//
// HOW TO RUN:
//   xcrun swiftc -swift-version 6 -typecheck docs/probes/swift-colour-isolation-negative.swift
//
// RECORDED 2026-10-03, Apple Swift 6.4, macOS 27.0.1: exit 1,
//   error: main actor-isolated default value in a nonisolated context
// on line `nonisolated func f(_ c: C = .red)`. The positive control is
// swift-colour-overloads.swift's I1 arm (conformance in an extension: clean).

@MainActor public protocol El { func paint() }
public struct C: El, Hashable, Sendable {
    var v: Double
    public init(v: Double) { self.v = v }
    public static let red = C(v: 1)
    public func paint() {}
}
nonisolated func f(_ c: C = .red) -> Double { c.v }

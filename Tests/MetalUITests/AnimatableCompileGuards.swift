import Testing
import MetalUITestSupport

// R4-3 PR D, the isolation spike (rulings `VA-A`, `VA-B`; SwiftUI's side is probe
// `docs/probes/swiftui-animatable.swift`, arms `VT1`-`VT16`). Whole-file Swift 6 (`typecheckFile`, ruling
// SA-P) against a PLAIN import, because a `@testable` test cannot prove what an external module can write.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log
// for `VA-A isolation` and `VA-B conformers` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private let isolationError = "crosses into main actor-isolated code"

/// `VA-A` isolation: a custom `Shape`'s `animatableData`.
///
/// Spike arms `S1` and `S2` (measured 2026-11-04). `Element` is `@MainActor`, so a MetalUI `Shape` conformer is
/// main-actor isolated, unlike SwiftUI's nonisolated `Shape` (`VT1`): **`S1`, SwiftUI's own spelling, is an
/// error in MetalUI** (the conformance to the nonisolated ``Animatable`` crosses into main-actor code), and
/// **`S2`, with `nonisolated var animatableData`, compiles** and reads the stored property. `nonisolated struct`
/// compiles with the plain spelling, and `@MainActor` on the witness does not help. Divergence 215 states the
/// difference. Marking the `Animatable` requirement `@MainActor` instead would make `S1` compile (measured, not
/// shipped: it would make `Double` and a keyframe timeline main-actor, and it would let `S3` through, which
/// SwiftUI rejects).
///
/// Mutations: remove `nonisolated` from the `S2` fixture (the positive fails); make `animatableData` a
/// `@MainActor` requirement (the `S1` negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aShapesAnimatableDataNeedsNonisolatedInSwift6() throws {
    let preamble = "import MetalUICore\nimport MetalUILayout\n"
    func shape(_ qualifier: String, typeQualifier: String = "") -> String {
        """
        \(preamble)
        public \(typeQualifier)struct S: Shape {
            public var t = 0.0
            public init() {}
            public \(qualifier)var animatableData: Double { get { t } set { t = newValue } }
            public func path(in rect: Bounds<Pixels>) -> Path { Path() }
        }
        @MainActor func use() {
            var s = S()
            s.animatableData = 2
            _ = s.animatableData
            _ = HStack { S() }
        }
        """
    }
    let s1 = try typecheckFile(shape(""), importing: "MetalUI")
    #expect(!s1.succeeded, "S1 (SwiftUI's spelling) must fail in a MetalUI Shape:\n\(s1.output)")
    #expect(s1.messages.contains(isolationError), "failed, but not for the isolation:\n\(s1.output)")
    let s2 = try typecheckFile(shape("nonisolated "), importing: "MetalUI")
    #expect(s2.succeeded, "S2 (nonisolated) must compile:\n\(s2.output)")
    let nonisolatedType = try typecheckFile(shape("", typeQualifier: "nonisolated "), importing: "MetalUI")
    #expect(nonisolatedType.succeeded, "a nonisolated struct with the plain spelling must compile:\n\(nonisolatedType.output)")
    let onWitness = try typecheckFile(shape("@MainActor "), importing: "MetalUI")
    #expect(!onWitness.succeeded, "@MainActor on the witness must not help:\n\(onWitness.output)")
    print("VA-A isolation: S1 error=\(!s1.succeeded) S2 compiles=\(s2.succeeded)")
}

/// `VA-A` isolation, arms `S3` and `S4`: a `Component` that is `Animatable` matches SwiftUI's `View`
/// (`VT2`, `VT3`) exactly: the plain spelling is an error in Swift 6, `nonisolated var animatableData` compiles.
///
/// Mutation: remove `nonisolated` from the `S4` fixture.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aComponentThatIsAnimatableNeedsNonisolatedLikeSwiftUIsView() throws {
    func component(_ qualifier: String) -> String {
        """
        import MetalUICore
        public struct C: Component, Animatable {
            public var x = 0.0
            public init() {}
            public \(qualifier)var animatableData: Double { get { x } set { x = newValue } }
            public var content: some Element { Text("a") }
        }
        """
    }
    let s3 = try typecheckFile(component(""), importing: "MetalUI")
    #expect(!s3.succeeded && s3.messages.contains(isolationError), "S3 must fail for the isolation:\n\(s3.output)")
    let s4 = try typecheckFile(component("nonisolated "), importing: "MetalUI")
    #expect(s4.succeeded, "S4 (nonisolated) must compile:\n\(s4.output)")
}

/// `VA-B` conformers, arms `S5` and `S6`. A shape with no `animatableData` compiles (`VT9`); `Double`,
/// `CGFloat`, `Angle`, `UnitPoint`, `CGPoint`, `CGSize`, `CGRect` and `EdgeInsets` are `Animatable` (`VT11`) in a
/// nonisolated generic function; **`Float` is too, a MetalUI extra** (SwiftUI's is not, `VT11`; divergence 169);
/// `Int` and `Color` are not.
///
/// Mutations: drop a conformance (the positive fails); conform `Int` (the separating arm compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theBuiltInAnimatablesAndAShapeWithNoDataCompile() throws {
    let positive = try typecheckFile("""
        import Foundation
        import MetalUICore
        import MetalUILayout

        public struct Plain: Shape {
            public init() {}
            public func path(in rect: Bounds<Pixels>) -> Path { Path() }
        }
        func probe<A: Animatable>(_ a: A) {}
        @MainActor func all() {
            probe(1.0); probe(CGFloat(1)); probe(Angle.zero); probe(UnitPoint.center)
            probe(CGPoint.zero); probe(CGSize.zero); probe(CGRect.zero); probe(EdgeInsets())
            probe(Float(1))
            probe(Plain()); probe(Circle())
        }
        @MainActor func empty(_ s: Plain) -> EmptyAnimatableData { s.animatableData }
        """, importing: "MetalUI")
    #expect(positive.succeeded, "the conformers must compile:\n\(positive.output)")
    for (name, value) in [("Int", "Int"), ("Color", "Color")] {
        let negative = try typecheckFile("""
            func probe<A: Animatable>(_ a: A) {}
            func f(_ v: \(value)) { probe(v) }
            """, importing: "MetalUI")
        #expect(!negative.succeeded && negative.messages.contains("conform to 'Animatable'"),
                "\(name) must not be Animatable:\n\(negative.output)")
    }
    print("VA-B conformers: ran")
}

/// `VA-B` keyframes, arm `S7` (`VT14`-`VT16`): a keyframe track over a custom `Animatable` struct compiles from
/// a plain import, in SwiftUI's call shape, and a type that is not `Animatable` is refused. **`Float` compiles
/// here and does not in SwiftUI** (`VT16`; the MetalUI extra of divergence 169).
///
/// Mutations: constrain `LinearKeyframe`'s `Value` to `VectorArithmetic` (the positive fails); drop the
/// constraint (the separating arm compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aKeyframeTrackOverACustomAnimatableCompiles() throws {
    let positive = try typecheckFile("""
        struct Pos: Animatable {
            var a = 0.0
            var b = 0.0
            var animatableData: AnimatablePair<Double, Double> {
                get { AnimatablePair(a, b) }
                set { a = newValue.first; b = newValue.second }
            }
        }
        struct Wobble { var pos = Pos(); var x = 0.0 }
        func timeline() -> KeyframeTimeline<Wobble> {
            KeyframeTimeline(initialValue: Wobble()) {
                KeyframeTrack(\\.pos) { LinearKeyframe(Pos(a: 100, b: 50), duration: 0.4) }
                KeyframeTrack(\\.x) { CubicKeyframe(1.0, duration: 0.2); SpringKeyframe(0.0, duration: 0.2) }
            }
        }
        func floats() { _ = LinearKeyframe(Float(1), duration: 0.1) }
        """, importing: "MetalUI")
    #expect(positive.succeeded, "S7 must compile:\n\(positive.output)")
    let negative = try typecheckFile("""
        struct P { var a = 0.0 }
        func f() { _ = LinearKeyframe(P(), duration: 1) }
        """, importing: "MetalUI")
    #expect(!negative.succeeded && negative.messages.contains("conform to 'Animatable'"),
            "a non-Animatable value must be refused:\n\(negative.output)")
    print("VA-B keyframes: ran")
}

import Testing
import MetalUITestSupport

// Compile-time guards for the proposal-layout protocol and its migration story
// (lane 1 of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`;
// rulings SA-C, SA-F, SA-P, SA-R).
//
// **Every guard here uses `typecheckFile`, never `typecheck`.** The older helper
// wraps its body in `func fixture() { … }` and passes no `-swift-version`: the
// wrapper makes every fixture type a local type and rejects the migration
// story's own `extension Leaf: ProposalElementGroup {}` (its spelling until
// ruling MC-G made the leaf a `ProposalElement`) with `declaration is only
// valid at file scope`, and Swift 5 mode reports a `Sendable` violation in an
// outside `ProposalLayout` as a warning, exit 0. `typecheckFile` compiles a
// whole file, `public` declarations at file scope, in Swift 6 mode, which is
// what an external module writes. The first guard below proves the mode is on.
//
// Each fixture compiles against a plain `import MetalUI`, which re-exports
// `MetalUILayout`. This file's own imports are irrelevant (shape 16); the
// fixture's import is the one that counts.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "When CI lands"). Each of these was mutated red once on a
// `--build-system native` build; the mutations are recorded under SA-F.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// An outside `ProposalLayout`, reading every proxy member the protocol offers
/// and both alignment factors. Shared by the positive fixture and the
/// negatives that need a layout to call.
private let diagonalSource = """
    public struct Diagonal: ProposalLayout {
        public var alignment: ProposalAlignment
        public init(alignment: ProposalAlignment = .center) { self.alignment = alignment }

        public func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
            var width = 0.0
            var height = 0.0
            for subview in subviews where !subview.isSpacer {
                let answer = subview.sizeThatFits(.unspecified)
                width += answer.size.width
                height = max(height, answer.size.height)
            }
            return LayoutMeasurement(size: SizeD(width: width, height: height))
        }

        public func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                                  subviews: PlacementSubviews) {
            let ordered = subviews.sorted { $0.priority > $1.priority }
            let total = ordered.reduce(0.0) { $0 + $1.sizeThatFits(.unspecified).size.width }
            var x = bounds.x + max(0, bounds.width - total) * alignment.horizontalFactor
            for subview in ordered where !subview.isSpacer {
                let answer = subview.sizeThatFits(.unspecified)
                let y = bounds.y + (bounds.height - answer.size.height) * alignment.verticalFactor
                subview.place(at: Point(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                x += answer.size.width
            }
        }
    }
    """

/// **The instrument guard.** `typecheckFile` must compile in the Swift 6
/// language mode, or every other guard here checks a weaker language than the
/// package's. A non-`Sendable` stored property in a `ProposalLayout` is an
/// error in Swift 6 mode and only a warning (exit 0) in Swift 5 mode (ruling
/// SA-P, measured on the design skeleton).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func typecheckFileChecksInTheSwift6LanguageMode() throws {
    let result = try typecheckFile("""
        public final class Box {
            public init() {}
        }

        public struct Leaky: ProposalLayout {
            public var box = Box()

            public func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
                LayoutMeasurement(size: SizeD(width: 0, height: 0))
            }

            public func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                                      subviews: PlacementSubviews) {}
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "a non-Sendable stored property in a ProposalLayout must fail in Swift 6 mode:\n\(result.output)")
    #expect(result.messages.contains("has non-Sendable type 'Box'"),
            "rejected, but not for the Sendable violation the language mode decides:\n\(result.output)")
}

/// **The migration story compiles from public API alone** (ruling SA-F, the
/// table in the kernel completion design): an outside module declares a
/// `ProposalLayout`, a leaf `ProposalElement` over `requestNativeLeaf`, and a
/// container `ProposalElement` that calls `requestProposalGroupLayout` then
/// `requestNativeLayout` (both written on the typed entry since ruling MC-G;
/// until then an `Element` marked `ProposalElementGroup` calling
/// `requestGroupLayout`), and uses all three through
/// `callAsFunction` (both spellings), `ProposalLayoutContainer`, and a
/// proposal modifier.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anExternalModuleCanBuildACustomLeafAndContainerFromPublicAPI() throws {
    let result = try typecheckFile(diagonalSource + """


        public struct Leaf: ProposalElement {
            public init() {}

            public func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
                (pass.requestNativeLeaf { proposal in
                    LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: 10))
                }, ())
            }

            public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                                 pass: inout PrepaintPass) {}

            public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                              prepaint: inout Void, pass: inout PaintPass) {}
        }

        public struct Container<Content: ProposalElementGroup>: ProposalElement {
            public var content: Content

            public init(@ElementBuilder content: () -> Content) { self.content = content() }

            public mutating func requestProposalLayout(_ id: GlobalElementID,
                                                       pass: inout LayoutPass) -> (ProposalNodeID, Content.GroupLayout) {
                var cursor = 0
                let (children, layout) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
                return (pass.requestNativeLayout(Diagonal(alignment: .bottom), children: children), layout)
            }

            public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                          layout: inout Content.GroupLayout,
                                          pass: inout PrepaintPass) -> Content.GroupPrepaint {
                content.prepaintGroup(layout: &layout, pass: &pass)
            }

            public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                       layout: inout Content.GroupLayout,
                                       prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
                content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
            }
        }

        @MainActor public func probe() {
            _ = VStack {
                HStack {
                    Diagonal() { Leaf(); Spacer() }
                    Container { Leaf() }
                    Diagonal(alignment: .top) { Leaf() }
                }
                ProposalLayoutContainer(Diagonal()) { Leaf() }
                Diagonal { Leaf() }.padding(Edges(all: Pixels(3)))
            }
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "the external-module migration story must compile from public API alone:\n\(result.output)")
}

/// **Measurement cannot place** (ruling SA-C): `sizeThatFits` receives
/// `MeasurementSubviews`, whose elements have no `place`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aMeasurementSubviewCannotBePlaced() throws {
    let result = try typecheckFile("""
        public struct Placer: ProposalLayout {
            public func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
                subviews[0].place(at: Point(x: 0, y: 0), proposal: .unspecified)
                return LayoutMeasurement(size: SizeD(width: 0, height: 0))
            }

            public func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                                      subviews: PlacementSubviews) {}
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "a measurement subview must not be placeable:\n\(result.output)")
    #expect(result.messages.contains("value of type 'MeasurementSubview' has no member 'place'"),
            "rejected, but not because MeasurementSubview lacks place:\n\(result.output)")
}

/// **No proxy can be made outside the kernel** (ruling SA-C): a forged
/// `MeasurementSubviews` or `PlacementSubview` would reach a run it does not
/// belong to.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func subviewProxiesCannotBeConstructedOutsideTheKernel() throws {
    for type in ["MeasurementSubviews", "PlacementSubview"] {
        let result = try typecheckFile("""
            @MainActor public func probe() {
                _ = \(type)()
            }
            """, importing: "MetalUI")
        #expect(!result.succeeded, "\(type) must have no public initializer:\n\(result.output)")
        #expect(result.messages.contains("'\(type)' initializer is inaccessible due to 'internal' protection level"),
                "rejected, but not because \(type)'s initializer is internal:\n\(result.output)")
    }
}

/// **A custom layout rejects legacy content in every call spelling** (ruling
/// SA-F). The two `callAsFunction` spellings fail on the method's constraint;
/// the container spelling on the struct's.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aCustomLayoutContainerRejectsLegacyContent() throws {
    let cases: [(spelling: String, diagnostic: String)] = [
        ("Diagonal() { Text(\"legacy\") }",
         "instance method 'callAsFunction' requires that 'Text' conform to 'ProposalElementGroup'"),
        ("Diagonal { Text(\"legacy\") }",
         "instance method 'callAsFunction' requires that 'Text' conform to 'ProposalElementGroup'"),
        ("ProposalLayoutContainer(Diagonal()) { Text(\"legacy\") }",
         "generic struct 'ProposalLayoutContainer' requires that 'Text' conform to 'ProposalElementGroup'"),
    ]
    for (spelling, diagnostic) in cases {
        let result = try typecheckFile(diagonalSource + """


            @MainActor public func probe() {
                _ = \(spelling)
            }
            """, importing: "MetalUI")
        #expect(!result.succeeded, "\(spelling) must not accept legacy content:\n\(result.output)")
        #expect(result.messages.contains(diagnostic),
                "\(spelling) was rejected, but not by the proposal-content constraint:\n\(result.output)")
    }
}

/// A public proposal leaf, for the frame guard's fixtures.
private let frameLeafSource = """
    public struct Leaf: ProposalElement {
        public init() {}

        public func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
            (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
        }

        public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                             pass: inout PrepaintPass) {}

        public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                          prepaint: inout Void, pass: inout PaintPass) {}
    }
    """

/// **A fixed and a flexible frame dimension cannot be combined** (lane 3,
/// ruling SA-K item 6). SwiftUI has no overload that spells the combination
/// (`Color.red.frame(width: 10, minWidth: 5)` → `extra argument 'minWidth' in
/// call`), so the proposal element API splits into SwiftUI's two overloads —
/// on the modifier, on `nativeFrame`, on `ProposalFrame`'s initializers and on
/// `LayoutModifier` (`.frame` and `.flexibleFrame`) — rather than turning a
/// spelling SwiftUI authors never meet into a run-time crash. The kernel
/// registrar keeps one signature and traps on one axis as a backstop
/// (`aFixedFrameDimensionCombinedWithAFlexibleOneTraps`).
///
/// The positive half proves the split kept both SwiftUI spellings, including
/// an alignment on each.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aFixedAndAFlexibleFrameDimensionCannotBeCombined() throws {
    let rejected: [(spelling: String, diagnostic: String)] = [
        ("Leaf().frame(width: Pixels(10), minWidth: Pixels(5))",
         "extra argument 'minWidth' in call"),
        ("Leaf().frame(width: Pixels(10), minHeight: Pixels(5))",
         "extra argument 'minHeight' in call"),
        ("ProposalFrame(width: Pixels(10), maxWidth: Pixels(20)) { Leaf() }",
         "extra arguments at positions #2, #3 in call"),
        ("ModifiedContent(content: Leaf(), modifier: .frame(width: Pixels(10), minWidth: Pixels(5)))",
         "extra argument 'minWidth' in call"),
        ("Leaf().nativeFrame(width: Pixels(10), minWidth: Pixels(5))",
         "extra argument 'minWidth' in call"),
    ]
    for (spelling, diagnostic) in rejected {
        let result = try typecheckFile(frameLeafSource + """


            @MainActor public func probe() {
                _ = \(spelling)
            }
            """, importing: "MetalUI")
        #expect(!result.succeeded, "\(spelling) must not combine a fixed and a flexible dimension:\n\(result.output)")
        #expect(result.messages.contains(diagnostic),
                "\(spelling) was rejected, but not by the overload split:\n\(result.output)")
    }

    let accepted = try typecheckFile(frameLeafSource + """


        @MainActor public func probe() {
            _ = Leaf().frame(width: Pixels(10), alignment: .leading)
            _ = Leaf().frame(minWidth: Pixels(5), maxWidth: Pixels(20))
        }
        """, importing: "MetalUI")
    #expect(accepted.succeeded, "both SwiftUI frame spellings must still compile:\n\(accepted.output)")
}

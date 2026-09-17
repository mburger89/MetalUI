// The frame OVERLOAD-RESOLUTION probe — plan task 4, lane 2's first step
// (`docs/superpowers/specs/2026-09-15-frame-sizing-design.md`, "The
// overload-resolution risk"; rulings FR-J and FR-S).
//
// This is a probe of the SWIFT COMPILER, not of SwiftUI: it answers which
// `frame` overload wins when the legacy and the proposal path declare the same
// signatures, and it does so on a standalone skeleton of the real protocol
// shape — two protocols, one refining the other, `ModifiedElement<Base>` and
// `ModifiedContent<C>`, the fixed and flexible overloads on each plus the
// deprecated no-argument `frame()`, and one type conforming to each protocol.
// Every `frame` body prints which declaration ran, so two overloads returning
// the SAME type can still be told apart.
//
// Three variants, by flag:
//
//   xcrun swiftc -swift-version 6 -DTWO_PARAM_LEGACY -DTHREE_PARAM_LEGACY \
//       swift-frame-overload-resolution.swift -o skel && ./skel   # A
//   xcrun swiftc -swift-version 6 -DTHREE_PARAM_LEGACY  … -o skel && ./skel   # B (shipped)
//   xcrun swiftc -swift-version 6 -DTWO_PARAM_LEGACY    … -o skel && ./skel   # C (before lane 2)
//
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), macOS 26.6.2, 2026-09-15.
//
// VARIANT B — the shipped set: ONE fixed legacy overload (three parameters),
// one flexible legacy overload, the proposal path's two. Recorded output:
//
//   proposal .frame(width:): ModifiedContent<Leaf>
//   proposal .frame(width:height:alignment:): ModifiedContent<Leaf>
//   proposal .frame(minWidth:idealWidth:maxWidth:): ModifiedContent<Leaf>
//   proposal .frame(idealWidth:): ModifiedContent<Leaf>
//   proposal .frame(maxWidth:): ModifiedContent<Leaf>
//   proposal .frame(alignment:): ModifiedContent<Leaf>
//   proposal .frame(): Leaf
//   legacy .frame(): LegacyBox
//     [legacy body: THREE-PARAM fixed]
//   legacy .frame(width:): ModifiedElement<LegacyBox>
//     [legacy body: THREE-PARAM fixed]
//   legacy .frame(width:height:alignment:): ModifiedElement<LegacyBox>
//     [legacy body: THREE-PARAM fixed]
//   legacy .frame(alignment:): ModifiedElement<LegacyBox>
//     [legacy body: FLEXIBLE]
//   legacy .frame(maxWidth:): ModifiedElement<LegacyBox>
//
// The refined protocol wins every shape on a proposal element, and nothing is
// ambiguous. The same seven rows were then re-taken against the REAL module by
// the runtime guard `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload`
// (`Tests/MetalUITests/FrameSizingCompileGuards.swift`), which asserts the
// inferred types rather than only that the calls compile; no row moved.
//
// VARIANT A — both a two-parameter and a three-parameter fixed legacy overload,
// which is what "declare the new one in FrameLayer.swift and leave lane 1's in
// place" would have shipped. It COMPILES, with no ambiguity: `.frame(width:)`
// silently takes the TWO-PARAM body and `.frame(width:height:alignment:)` the
// three-parameter one. The reason the shipped set is variant B is not
// ambiguity but solver work — see ruling FR-S: against the real module the
// 24-modifier chain of `ModifiedElementCompileGuards` fails
// `-solver-scope-threshold=16000` under variant A and needs 186 scopes under
// variant B.
//
// VARIANT C — the module before lane 2: `legacy .frame(width:height:alignment:)`
// is rejected with `extra argument 'alignment' in call`, which is the red this
// lane's tests opened on.
//
// THE TWO REJECTIONS, under variant A's (largest) overload set, compiled
// with `-DREJECT` added to variant A's command line (the block at the end of
// this file):
//
//   error: extra argument 'minWidth' in call
//   error: extra argument 'minHeight' in call
//   error: extra argument 'minWidth' in call
//   error: extra argument 'minHeight' in call
//
// verbatim on BOTH paths — so `ProposalLayoutCompileGuards`'
// `aFixedAndAFlexibleFrameDimensionCannotBeCombined` needs no re-fixture
// (critic finding 4), and the legacy path rejects the same combination for the
// same reason SwiftUI does.


public struct Pixels { public var value: Float; public init(_ v: Float) { self.value = v } }
public enum ProposalAlignment { case topLeading, center, bottomTrailing }

public struct ModifiedElement<Base> { public init() {} }
public struct ModifiedContent<C> { public init() {} }

public protocol ElementGroup {
    associatedtype LayerBase: ElementGroup = Self
}

public protocol ProposalElementGroup: ElementGroup {}

// MARK: - the LEGACY surface (what lane 2 declares)

extension ElementGroup {
    public func _wrap(_ tag: String) -> ModifiedElement<LayerBase> { print("  [legacy body: \(tag)]"); return ModifiedElement<LayerBase>() }

    // ROW A: the two-parameter declaration lane 1's step 0 left in
    // ModifiedElement.swift. Commented in/out by the two variants below.
    #if TWO_PARAM_LEGACY
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<LayerBase> {
        _wrap("TWO-PARAM fixed")
    }
    #endif

    #if THREE_PARAM_LEGACY
    public func frame(width: Pixels? = nil, height: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedElement<LayerBase> {
        _wrap("THREE-PARAM fixed")
    }
    #endif

    public func frame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil,
                      minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedElement<LayerBase> {
        _wrap("FLEXIBLE")
    }

    @available(*, deprecated, message: "Please pass one or more parameters.")
    public func frame() -> Self { self }
}

// MARK: - the PROPOSAL surface (what NativeModifiedContent.swift declares today)

extension ProposalElementGroup {
    public func frame(width: Pixels? = nil, height: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedContent<Self> {
        ModifiedContent()
    }

    public func frame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil,
                      minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedContent<Self> {
        ModifiedContent()
    }

    @available(*, deprecated, message: "Please pass one or more parameters.")
    public func frame() -> Self { self }
}

public struct Leaf: ProposalElementGroup { public init() {} }
public struct LegacyBox: ElementGroup { public init() {} }

func report(_ label: String, _ value: Any) {
    print("\(label): \(type(of: value))")
}

// The seven inference rows, on a PROPOSAL element.
report("proposal .frame(width:)", Leaf().frame(width: Pixels(10)))
report("proposal .frame(width:height:alignment:)",
       Leaf().frame(width: Pixels(10), height: Pixels(10), alignment: .center))
report("proposal .frame(minWidth:idealWidth:maxWidth:)",
       Leaf().frame(minWidth: Pixels(1), idealWidth: Pixels(2), maxWidth: Pixels(3)))
report("proposal .frame(idealWidth:)", Leaf().frame(idealWidth: Pixels(2)))
report("proposal .frame(maxWidth:)", Leaf().frame(maxWidth: Pixels(3)))
report("proposal .frame(alignment:)", Leaf().frame(alignment: .topLeading))
// Row 7 is `.frame()`, which must infer the receiver's own type on both paths.
let noArg: Leaf = Leaf().frame()
report("proposal .frame()", noArg)
let noArgLegacy: LegacyBox = LegacyBox().frame()
report("legacy .frame()", noArgLegacy)

// The LEGACY rows: every shape must infer `ModifiedElement<LegacyBox>`.
report("legacy .frame(width:)", LegacyBox().frame(width: Pixels(10)))
report("legacy .frame(width:height:alignment:)",
       LegacyBox().frame(width: Pixels(10), height: Pixels(10), alignment: .topLeading))
report("legacy .frame(alignment:)", LegacyBox().frame(alignment: .topLeading))
report("legacy .frame(maxWidth:)", LegacyBox().frame(maxWidth: Pixels(3)))

#if REJECT
// Never called: the point is the four diagnostics, quoted in the header.
func rejected() {
    _ = Leaf().frame(width: Pixels(10), minWidth: Pixels(5))
    _ = Leaf().frame(height: Pixels(10), minHeight: Pixels(5))
    _ = LegacyBox().frame(width: Pixels(10), minWidth: Pixels(5))
    _ = LegacyBox().frame(height: Pixels(10), minHeight: Pixels(5))
}
#endif

import Testing
import MetalUITestSupport

// Compile-time guard for plan task 7's layout authority
// (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §6 lane 1,
// guard G1; ruling LR-B: the authority is internal until stage 6b).
//
// **A plain `import MetalUI` fixture through `typecheckFile`** (ruling SA-P;
// taxonomy shape 16): a `@testable` test file sees `internal` and cannot show
// that an external module cannot choose the authority.
//
// **The guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, CI section). It was run red once, with `LayoutAuthority` and
// `Window.layoutAuthority` made `public` (record §18, lane 1).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.** Outside `MetalUI`, `window.layoutAuthority = …` does not compile.
/// The positive control writes `theme` on the same `Window`, so the negative's
/// failure is about the authority's access level and not about the fixture.
///
/// Mutation that must redden it: `LayoutAuthority` and `Window.layoutAuthority`
/// made `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImportCannotChooseTheLayoutAuthority() throws {
    let choose = try typecheckFile("""
        @MainActor public func choose(_ window: Window) {
            window.layoutAuthority = .proposal
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        @MainActor public func control(_ window: Window) {
            window.theme = .dark
        }
        """, importing: "MetalUI")
    print("LAYOUT-AUTHORITY GUARD G1 choose: succeeded=\(choose.succeeded)\n\(choose.messages)")
    print("LAYOUT-AUTHORITY GUARD G1 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(choose.succeeded != control.succeeded,
                 "the choice and the control must disagree, or the instrument cannot fail:\n\(choose.output)\n\(control.output)")
    #expect(control.succeeded, "the control must compile:\n\(control.output)")
    #expect(!choose.succeeded, "an external module must not choose the layout authority:\n\(choose.output)")
    #expect(choose.messages.contains("'layoutAuthority' is inaccessible due to 'internal' protection level"),
            "rejected, but not because the property is internal:\n\(choose.output)")
}

/// **Stage 6a's guard** (spec §7 test 3.2, `LR-CX`): outside `MetalUI`, a caller
/// of the public legacy registrars **still compiles** and is **warned**, once
/// per registrar, toward the native ones. The control calls only
/// `requestNativeLeaf` and carries no deprecation.
///
/// A `@testable` test cannot see this: the attribute is what an external module
/// meets, and inside the suite every caller was moved in the same change so the
/// build stays at 0 `warning:` — the gate is the deprecation's other half. The
/// child `swiftc`'s output is captured through a pipe, so the fixture's
/// warnings never reach the suite's log as a `warning:` line of its own.
///
/// **Red before** (lane 3's red-first commit, no attribute yet): both fixtures'
/// messages are empty, and the `#require` that they disagree fails.
///
/// Mutations that must redden it: **M3a**, the attribute removed from
/// `requestNode(style:children:)`; **M3b**, removed from
/// `requestLeaf(style:measure:)`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes() throws {
    let legacy = try typecheckFile("""
        public struct LegacyCaller: Element {
            public init() {}
            public func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
                let leaf = pass.requestLeaf(style: Style()) { _, _ in SizeD(width: 10, height: 10) }
                return (pass.requestNode(style: Style(), children: [leaf]), ())
            }
            public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                                 pass: inout PrepaintPass) {}
            public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                              prepaint: inout Void, pass: inout PaintPass) {}
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        public struct NativeCaller: Element {
            public init() {}
            public func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
                (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
            }
            public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                                 pass: inout PrepaintPass) {}
            public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                              prepaint: inout Void, pass: inout PaintPass) {}
        }
        """, importing: "MetalUI")
    print("LAYOUT-AUTHORITY GUARD 6a legacy: succeeded=\(legacy.succeeded)\n\(legacy.messages)")
    print("LAYOUT-AUTHORITY GUARD 6a control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(legacy.messages.contains("is deprecated") != control.messages.contains("is deprecated"),
                 "the legacy caller and the control must disagree on a deprecation, or the instrument cannot fail:\n\(legacy.output)\n\(control.output)")
    #expect(legacy.succeeded, "a deprecated registrar must still compile:\n\(legacy.output)")
    #expect(control.succeeded, "the control must compile:\n\(control.output)")
    #expect(legacy.messages.contains("'requestNode(style:children:)' is deprecated"),
            "requestNode must carry the deprecation:\n\(legacy.output)")
    #expect(legacy.messages.contains("'requestLeaf(style:measure:)' is deprecated"),
            "requestLeaf must carry the deprecation:\n\(legacy.output)")
    #expect(legacy.messages.contains("requestNativeLeaf"),
            "the deprecation must point at the native registrar:\n\(legacy.output)")
    #expect(!control.messages.contains("is deprecated"), "the control must not be warned:\n\(control.output)")
}

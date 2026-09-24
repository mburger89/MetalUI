import Testing
import MetalUITestSupport

// Compile-time guards for plan task 7's layout authority
// (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §6 lane 1,
// guard G1; ruling LR-B: the authority was internal until stage 6b) and its
// legacy registrars (stage 6a's guard, `LR-CX`).
//
// **Stage 9** (spec `2026-09-24-engine-stage-9-design.md` §6 lane 3; `LR-FC`,
// `LR-FG` item 6) deleted both — the `LayoutAuthority` enum with
// `Window.layoutAuthority`, and `LayoutPass.requestNode`/`requestLeaf` — so
// each guard is re-spelled to read the deleted symbol's **absence**: the
// negative fixture fails with "has no member", not with an access-level or a
// deprecation message. A `@testable` test cannot show absence from an external
// module's view any more than it could show a narrowing (taxonomy shape 16).
//
// **A plain `import MetalUI` fixture through `typecheckFile`** (ruling SA-P;
// taxonomy shape 16).
//
// **The guards skip silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, CI section). G1 was run red once, with `LayoutAuthority` and
// `Window.layoutAuthority` made `public` (record §18, lane 1); its re-spelling
// and 6a's were each run red once at stage 9 (record §51, lane 3, M3d/M3e).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.** Outside `MetalUI`, `window.layoutAuthority = …` does not compile,
/// because `Window` has no such member since stage 9 (`LR-FC`). The positive
/// control writes `theme` on the same `Window`, so the negative's failure is
/// about the authority and not about the fixture.
///
/// Mutation that must redden it (**M3d**, stage 9): an internal
/// `var layoutAuthority = 0` restored on `Window` — the message becomes the
/// access-level one. (Before stage 9: `LayoutAuthority` and
/// `Window.layoutAuthority` made `public`.)
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
    #expect(choose.messages.contains("value of type 'Window' has no member 'layoutAuthority'"),
            "rejected, but not because the property is gone:\n\(choose.output)")
}

/// **Stage 6a's guard** (spec §7 test 3.2, `LR-CX`), **re-spelled and renamed by
/// stage 9** (`LR-FF`; it was `aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes`):
/// outside `MetalUI`, a caller of the legacy registrars **no longer compiles** —
/// `LayoutPass` has neither `requestLeaf` nor `requestNode` — while the control,
/// which calls only `requestNativeLeaf`, compiles with no deprecation. Until
/// stage 9 the legacy caller compiled with one deprecation per registrar.
///
/// **Red before** (at lane 2's head): the legacy fixture compiles with two
/// deprecations, and the `#require` that the two disagree on compiling fails.
///
/// Mutation that must redden it (**M3e**): the public deprecated
/// `requestNode(style:children:)` restored on `LayoutPass` (body
/// `fatalError()`) — the fixture's `requestNode` error vanishes.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles() throws {
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
    try #require(legacy.succeeded != control.succeeded,
                 "the legacy caller and the control must disagree, or the instrument cannot fail:\n\(legacy.output)\n\(control.output)")
    #expect(!legacy.succeeded, "the legacy registrars must be gone:\n\(legacy.output)")
    #expect(control.succeeded, "the control must compile:\n\(control.output)")
    #expect(legacy.messages.contains("value of type 'LayoutPass' has no member 'requestLeaf'"),
            "requestLeaf must be absent:\n\(legacy.output)")
    #expect(legacy.messages.contains("value of type 'LayoutPass' has no member 'requestNode'"),
            "requestNode must be absent:\n\(legacy.output)")
    #expect(!control.messages.contains("is deprecated"), "the control must not be warned:\n\(control.output)")
}

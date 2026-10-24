import Testing
import MetalUITestSupport

// Liquid Glass, lane C, guards 35 (rulings `LG-A`, `LG-R`, `LG-U`; probe arms A4, A15, A17 of
// `docs/probes/swiftui-liquid-glass.swift`). Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN
// `import MetalUI`: what an external module may write with the glass surface. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for `GLASS GUARD` to know it ran.

private let glassSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **35a** (`LG-A`). Every glass spelling of the spec's §1 compiles from a plain import, and an outside exhaustive
/// `switch` over `LayoutModifier` that names the old cases is the migration note's break. **Negative arms**, each its
/// own fixture so a failure names which one leaked: `Glass()` (no public initialiser, A14), a `Hashable` use of
/// `Glass` (A15), `glassEffect(isEnabled:)` (the SDK has none, A4/A17) and the non-public `GlassLook`.
///
/// Mutation that must redden it (mutated red once, `IX-R`): add `public init()` to `Glass` (the `Glass()` arm
/// compiles); add `Hashable` to `Glass` (the set arm compiles); widen `GlassLook` to `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), glassSkipReason))
func theGlassSpellingsCompileAndTheNonSDKOnesDoNot() throws {
    let positive = try typecheckFile("""
        @MainActor public struct Panel: Component {
            @Namespace var ns
            public init() {}
            public var content: some ProposalElementGroup {
                GlassEffectContainer(spacing: Pixels(20)) {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: Pixels(60), height: Pixels(60))
                            .glassEffect(.regular.tint(Color.blue.opacity(0.3)).interactive(), in: Circle())
                            .glassEffectID("a", in: ns)
                            .glassEffectUnion(id: "u", namespace: ns)
                            .glassEffectTransition(.materialize)
                        Color.clear.frame(width: Pixels(60), height: Pixels(60)).glassEffect()
                    }
                }
            }
        }
        @MainActor public func spellings() {
            let glasses: [Glass] = [.regular, .clear, .identity, Glass.regular.tint(nil), .clear.interactive(false)]
            let _: Bool = glasses[0] == glasses[1]
            let transitions: [GlassEffectTransition] = [.matchedGeometry, .materialize, .identity]
            _ = transitions
            let styles: [ButtonStyle] = [.glass, .glassProminent]
            _ = Button("Go") {}.buttonStyle(styles[0])
            _ = Button("Go") {}.buttonStyle(.glassProminent)
            _ = Box().glassEffect(.regular, in: RoundedRectangle(cornerRadius: Pixels(8)))
            let id: Namespace.ID? = nil
            _ = id
        }
        """, importing: "MetalUI")
    print("GLASS GUARD 35a positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let noInit = try typecheckFile("""
        public func make() -> Glass { Glass() }
        """, importing: "MetalUI")
    let hashable = try typecheckFile("""
        public func make() -> Set<Glass> { [.regular] }
        """, importing: "MetalUI")
    let isEnabled = try typecheckFile("""
        @MainActor public func make() -> some ProposalElementGroup { Color.clear.glassEffect(.regular, isEnabled: false) }
        """, importing: "MetalUI")
    let look = try typecheckFile("""
        public func make() { _ = GlassLook.self }
        """, importing: "MetalUI")
    print("GLASS GUARD 35a negatives: noInit=\(noInit.succeeded) hashable=\(hashable.succeeded) "
          + "isEnabled=\(isEnabled.succeeded) look=\(look.succeeded)")
    try #require(positive.succeeded && !noInit.succeeded && !hashable.succeeded && !isEnabled.succeeded && !look.succeeded,
                 """
                 the arms must disagree, or the guard measures nothing:
                 \(positive.output)
                 \(noInit.output)
                 \(hashable.output)
                 \(isEnabled.output)
                 \(look.output)
                 """)
    #expect(positive.succeeded, "every glass spelling must compile from a plain import:\n\(positive.output)")
    #expect(!noInit.succeeded, "Glass has no public initialiser:\n\(noInit.output)")
    #expect(!hashable.succeeded, "Glass is not Hashable (A15):\n\(hashable.output)")
    #expect(!isEnabled.succeeded, "glassEffect has no isEnabled: (A4, A17):\n\(isEnabled.output)")
    #expect(!look.succeeded, "GlassLook stays non-public:\n\(look.output)")
}

/// **35b** (`LG-U`). `GlassSpec` and the container's registration stay non-public: an outside module cannot name
/// the registration types. Mutation: widen `GlassGroup` to `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), glassSkipReason))
func theGlassRegistrationTypesStayNonPublic() throws {
    let group = try typecheckFile("""
        public func make() { _ = GlassGroup.self }
        """, importing: "MetalUI")
    let member = try typecheckFile("""
        public func make() { _ = GlassMember.self }
        """, importing: "MetalUI")
    print("GLASS GUARD 35b: group=\(group.succeeded) member=\(member.succeeded)")
    #expect(!group.succeeded, "GlassGroup is internal:\n\(group.output)")
    #expect(!member.succeeded, "GlassMember is internal:\n\(member.output)")
}

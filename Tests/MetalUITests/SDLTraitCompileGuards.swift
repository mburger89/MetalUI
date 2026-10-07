import Testing
import MetalUITestSupport

// Compile-time guard for the consumable SDL backend (spec
// `docs/superpowers/specs/2026-10-07-portable-app-design.md` §4.1, guard 1.6;
// ruling `PX-H` item 4). The root package declares `MetalUISDL` on every
// platform behind the `SDL` trait; this package's own build enables no trait,
// so the `MetalUISDL` module here is the one a consumer gets when it forgets
// `traits:`.
//
// **`typecheckFile`** — whole-file, Swift 6, a PLAIN `import MetalUISDL`, as an
// external module writes it (`SA-P`). **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); once
// MetalUI's modules are there, `MetalUISDL` must be there too.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **1.6 — an `SDLPlatform` without the `SDL` trait names the trait.** Without
/// the trait `MetalUISDL` declares only an unavailable `SDLPlatform` whose
/// message is the remedy; `_ = try SDLPlatform()` fails with it. **Control**:
/// a file that only imports `MetalUISDL` compiles — the module exists, so the
/// failure is the stub's, not a missing module's.
///
/// Mutation: delete the stub → "cannot find 'SDLPlatform' in scope" → red.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anSDLPlatformWithoutTheSDLTraitNamesTheTrait() throws {
    try #require(canTypecheck(module: "MetalUISDL"),
                 "MetalUISDL is not among the root build's modules (PX-H item 1)")
    let control = try typecheckFile("""
        public func ok() {}
        """, importing: "MetalUISDL")
    let platform = try typecheckFile("""
        @MainActor public func bad() throws { _ = try SDLPlatform() }
        """, importing: "MetalUISDL")

    print("""
        1.6 SDLPlatform without the trait: control succeeded=\(control.succeeded) \
        messages=[\(control.messages)]; platform succeeded=\(platform.succeeded) \
        messages=[\(platform.messages)]
        """)

    try #require(control.succeeded, "importing MetalUISDL must compile:\n\(control.output)")
    #expect(!platform.succeeded, "SDLPlatform() must not compile without the SDL trait:\n\(platform.output)")
    #expect(platform.messages.contains("enable the trait 'SDL'"),
            "rejected, but not with the trait's remedy:\n\(platform.output)")
    #expect(platform.messages.contains("docs/getting-started.md"), "\(platform.output)")
}

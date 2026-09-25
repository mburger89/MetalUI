import Testing
import MetalUITestSupport

// Compile-time guards for plan task 9, the environment and control-state track
// (`docs/superpowers/specs/2026-09-15-environment-design.md`; rulings `EV-`).
//
// Each fixture compiles against a plain `import MetalUI`. This file's own
// imports are irrelevant (shape 16); the fixture's import is the one that
// counts.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "When CI lands"). Each guard here was mutated red once on a
// `--build-system native` build; the mutations are recorded under the ruling
// the guard cites and in `docs/record/11-environment.md`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G5 — the keymap's old `Binding` spelling still compiles, and is
/// deprecated toward `KeyBinding`** (ruling EV-N, lane 1).
///
/// Two halves, and each is reddened by a different mutation:
///
/// - `succeeded`: deleting the typealias makes `Binding` unresolvable, so an
///   external caller who wrote the old spelling stops compiling instead of
///   getting a release to move.
/// - `messages` naming `KeyBinding`: dropping `@available(*, deprecated,
///   renamed:)` leaves the alias compiling silently, so nobody is told to move
///   before task 10 deletes the name. The assertion reads `messages`, never
///   `output`: the fixture's own source never spells `KeyBinding`, but a
///   diagnostic-free `output` must not be able to satisfy it by accident either.
///
/// **This guard is deleted by task 10** in the change that introduces a
/// SwiftUI-like `Binding<Value>`, since a module cannot declare both (EV-N).
///
/// The deprecation warning is printed by the child `swiftc`, whose output the
/// helper captures through a pipe, so it does not reach the suite log's
/// `warning:` count.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding() throws {
    let result = try typecheck("""
        struct A: Action {}
        let k = Keymap([Binding("cmd-k", A())])
        _ = k
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "the deprecated `Binding` spelling must still compile:\n\(result.output)")
    #expect(result.messages.contains("'Binding' is deprecated"),
            "`Binding` must carry a deprecation diagnostic:\n\(result.output)")
    #expect(result.messages.contains("KeyBinding"),
            "the deprecation must name its replacement, `KeyBinding`:\n\(result.output)")
}

// MARK: - Lane 2: the environment's public shape (EV-C, EV-G, EV-J, EV-U, EV-W)

/// A custom key and a phase-reading element, at file scope as an external
/// module writes them. Shared by the guards below.
private let probeKeySource = """
    public struct ProbeKey: EnvironmentKey {
        public static let defaultValue = 0
    }

    extension EnvironmentValues {
        public var probe: Int {
            get { self[ProbeKey.self] }
            set { self[ProbeKey.self] = newValue }
        }
    }
    """

/// **G1+ — every public environment value is readable in every phase**
/// (rulings EV-C, EV-L), through `pass.environment` on all three passes and
/// through `@Environment` on a struct.
///
/// **The struct is `@MainActor`**, as every `Element` and `Component` is
/// through its protocol. `Environment` is main-actor-isolated like `State`, and
/// a nonisolated struct declaring either fails in the Swift 6 language mode
/// with "memberwise initializer for 'Reader' cannot be both nonisolated and
/// main actor-isolated" — measured on this fixture's first draft (record 11,
/// lane 2).
///
/// The positive half of G1−: without it, G1− could pass against a module whose
/// passes had no `environment` at all.
///
/// Task 9's closing lane 1 added `displayScale`, `controlActiveState` and
/// `controlSize` (rulings EV-AA, EV-AB, EV-AC); **MG1** (`displayScale` made
/// `internal`) reddens it. It reads only, so it cannot tell a public setter
/// from an internal one — G6 is the write half (MG6a).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func environmentValuesAreReadableInEveryPhase() throws {
    let result = try typecheckFile(probeKeySource + """

        @MainActor
        func readAll(_ e: EnvironmentValues) {
            let _: Bool = e.isEnabled
            let _: LayoutDirection = e.layoutDirection
            let _: String = e.locale.identifier
            let _: DynamicTypeSize = e.dynamicTypeSize
            let _: Double = e.pixelLength
            let _: Double = e.displayScale
            let _: ControlActiveState = e.controlActiveState
            let _: ControlSize = e.controlSize
            let _: Int = e.probe
            let _: Int = e[ProbeKey.self]
        }

        @MainActor
        func layout(_ pass: inout LayoutPass) { readAll(pass.environment) }
        @MainActor
        func prepaint(_ pass: inout PrepaintPass) { readAll(pass.environment) }
        @MainActor
        func paint(_ pass: inout PaintPass) { readAll(pass.environment) }

        @MainActor
        public struct Reader {
            @Environment(\\.isEnabled) var isEnabled
            @Environment(\\.probe) var probe
            @Environment(\\.pixelLength) var pixelLength
            @Environment(\\.displayScale) var displayScale
            @Environment(\\.controlActiveState) var controlActiveState
            @Environment(\\.controlSize) var controlSize
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "every public environment value must be readable in every phase:\n\(result.output)")
}

/// **G1− — the theme is not reachable through the environment** (ruling EV-G):
/// neither `pass.environment.theme` nor `@Environment(\.theme)` compiles
/// outside the module. `PaintPass.theme` stays the only reader, so the theme
/// stays paint-only; `PhaseSeparationTests`' three theme guards cover the pass
/// spelling, and this covers the environment spelling.
///
/// The messages are matched as `'theme' is inaccessible`, not the bare word
/// `theme`: a nonisolated fixture struct is rejected with a note naming the
/// property `_theme`, which a bare `theme` would accept for the wrong reason.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theThemeIsNotReachableThroughTheEnvironment() throws {
    let throughPass = try typecheckFile("""
        @MainActor
        func layout(_ pass: inout LayoutPass) {
            _ = pass.environment.theme
        }
        """, importing: "MetalUI")
    #expect(!throughPass.succeeded,
            "`pass.environment.theme` must not compile outside the module:\n\(throughPass.output)")
    #expect(throughPass.messages.contains("'theme' is inaccessible"),
            "rejected, but not for `theme`:\n\(throughPass.output)")

    let throughWrapper = try typecheckFile("""
        @MainActor
        public struct Reader {
            @Environment(\\.theme) var theme
        }
        """, importing: "MetalUI")
    #expect(!throughWrapper.succeeded,
            "`@Environment(\\.theme)` must not compile outside the module:\n\(throughWrapper.output)")
    #expect(throughWrapper.messages.contains("'theme' is inaccessible"),
            "rejected, but not for `theme`:\n\(throughWrapper.output)")
}

/// **G2 — environment values cannot be written through a pass** (ruling
/// EV-C). A pass-level setter would be an unscoped push: a write in one
/// element's paint would change what every later sibling reads.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func environmentValuesCannotBeWrittenThroughAPass() throws {
    let result = try typecheckFile("""
        @MainActor
        func paint(_ pass: inout PaintPass) {
            pass.environment.isEnabled = false
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "writing through `pass.environment` must not compile:\n\(result.output)")
    #expect(result.messages.contains("'environment' is a get-only property"),
            "rejected, but not for `environment`:\n\(result.output)")
}

/// **G3 — `pixelLength` has no writable key path outside the module, and a
/// whole-value write still compiles** (rulings EV-J, EV-U, EV-AA).
///
/// - **Negative**: `.environment(\.pixelLength, 1.0)` fails, because the
///   field's key path is a `KeyPath`, not a `WritableKeyPath`. Since `EV-AA`
///   `pixelLength` is a get-only computed property derived from
///   `displayScale` (SwiftUI's shape), not a `public internal(set)` stored
///   one; the diagnostic still names `WritableKeyPath` (measured on lane 1's
///   build). **MG3** (a public setter) reddens this half.
/// - **Positive premise**: `.environment(\.self, EnvironmentValues())`
///   compiles. Since `EV-AA` the premise is **aligned with SwiftUI**, not
///   re-stamped: the reset lands for `displayScale` (and so `pixelLength`),
///   reading 1 and 1 as pixel-length probe X2 does in SwiftUI, while `theme` is
///   still re-stamped (`aWholeValueWriteResetsTheDisplayScaleButNotTheTheme`).
///   If this half ever fails, the premise of EV-U's theme half has changed and
///   the ruling should be re-read, not this assertion deleted.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func pixelLengthIsNotWritableFromOutsideButAWholeValueWriteCompiles() throws {
    let negative = try typecheckFile("""
        @MainActor
        func content() -> some ElementGroup {
            Box().environment(\\.pixelLength, 1.0)
        }
        """, importing: "MetalUI")
    #expect(!negative.succeeded,
            "`.environment(\\.pixelLength, _)` must not compile outside the module:\n\(negative.output)")
    #expect(negative.messages.contains("WritableKeyPath"),
            "rejected, but not for the key path's writability:\n\(negative.output)")

    let premise = try typecheckFile("""
        @MainActor
        func content() -> some ElementGroup {
            Box().environment(\\.self, EnvironmentValues())
        }
        """, importing: "MetalUI")
    #expect(premise.succeeded,
            "a whole-value write is EV-U's premise and must compile:\n\(premise.output)")
}

/// **G4+ — a proposal container accepts a scope over proposal content**
/// (ruling EV-B): `EnvironmentScope` is `ProposalElementGroup` where its
/// content is. In the Swift 6 language mode, as an external module writes it.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aProposalContainerAcceptsAScopeOverProposalContent() throws {
    let result = try typecheckFile(probeKeySource + """

        @MainActor
        func content() -> some Element {
            HStack { Rectangle(width: Pixels(1), height: Pixels(1)).environment(\\.probe, 1) }
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "a scope over proposal content must be proposal content:\n\(result.output)")
}

/// **G4− — a proposal container rejects a scope over legacy content**
/// (ruling EV-B). The conformance is conditional: a scope does not launder a
/// legacy element across the engine boundary (ruling SA-G).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aProposalContainerRejectsAScopeOverLegacyContent() throws {
    let result = try typecheckFile(probeKeySource + """

        @MainActor
        func content() -> some Element {
            HStack { Box().environment(\\.probe, 1) }
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "a scope over legacy content must not be proposal content:\n\(result.output)")
    #expect(result.messages.contains("ProposalElementGroup"),
            "rejected, but not for the ProposalElementGroup requirement:\n\(result.output)")
}

// MARK: - Lane 2b: the public writers (EV-C)

/// **G6 — every public environment writer compiles from outside the module**
/// (ruling EV-C, shape 16).
///
/// Every other environment test is `@testable`, and G1+–G4 only read or spell
/// `.environment(_:_:)`, so `.theme(_:)`, `.transformEnvironment`,
/// `.dynamicTypeSize(_:)`, `Window.environment`'s setter,
/// `DynamicTypeSize.isAccessibilitySize` and the setters of `isEnabled`,
/// `layoutDirection`, `locale` and `dynamicTypeSize` could each be narrowed
/// with the suite green. This fixture calls each of them through a plain
/// `import MetalUI`, in the Swift 6 language mode, in three spellings: the
/// modifiers, a key-path write through `.environment(\.field, …)`, and a member
/// assignment on `Window.environment` and on a local `EnvironmentValues`.
/// Lane 3 added `.disabled(_:)` to the chain (ruling EV-D): the gate reads the
/// value, but the modifier is how a caller outside the module writes it.
/// Task 9's closing lane 1 added the writes of `displayScale`,
/// `controlActiveState` and `controlSize`, `.controlSize(_:)`, and both new
/// enums' `allCases` (rulings EV-AA…EV-AC); **MG6a** (`displayScale`
/// `public internal(set)`) reddens this guard and not G1+, and **MG6b**
/// (`.controlSize(_:)` internal) reddens it too.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theEnvironmentsPublicWritersCompileFromOutsideTheModule() throws {
    // `Locale` is Foundation's, and an external module names it only by
    // importing Foundation: `import MetalUI` alone reports "cannot find
    // 'Locale' in scope" (measured on this fixture's first draft).
    let result = try typecheckFile("import Foundation\n" + probeKeySource + """

        @MainActor
        func content() -> some ElementGroup {
            Box()
                .environment(\\.isEnabled, false)
                .environment(\\.layoutDirection, .rightToLeft)
                .environment(\\.locale, Locale(identifier: "de_DE"))
                .environment(\\.dynamicTypeSize, .accessibility1)
                .environment(\\.probe, 1)
                .transformEnvironment(\\.probe) { $0 += 1 }
                .dynamicTypeSize(.xLarge)
                .theme(.dark)
                .disabled(true)
                .environment(\\.displayScale, 3)
                .environment(\\.controlActiveState, .inactive)
                .environment(\\.controlSize, .mini)
                .controlSize(.small)
        }

        @MainActor
        func f(_ w: Window) {
            w.environment = EnvironmentValues()
            w.environment.isEnabled = false
            var e = EnvironmentValues()
            e.isEnabled = false
            e.layoutDirection = .rightToLeft
            e.locale = Locale(identifier: "de_DE")
            e.dynamicTypeSize = .accessibility2
            e[ProbeKey.self] = 3
            e.displayScale = 3
            e.controlActiveState = .active
            e.controlSize = .large
            w.environment = e
            _ = DynamicTypeSize.accessibility2.isAccessibilitySize
            _ = ControlSize.allCases
            _ = ControlActiveState.allCases
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "every public environment writer must compile outside the module:\n\(result.output)")
}

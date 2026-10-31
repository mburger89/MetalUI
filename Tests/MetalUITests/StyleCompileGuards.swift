import Testing
import MetalUITestSupport

// Round 3, item R3-1 (`BY-A`…): whole-file Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`, ruling
// SA-P) — what an external module may write against the open style protocols. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for `STYLE GUARD`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G-BY1 — a third-party module declares its own `ButtonStyle`, `PrimitiveButtonStyle` and `ToggleStyle`** and
/// applies them, with every built-in spelling, from a plain import. **Negative arms**, each its own fixture so a
/// failure names which one leaked: a style whose `Body` is not an `ElementGroup`, a `ButtonStyleConfiguration`
/// built outside the module (its initialiser is internal) and `.buttonStyle` with a value that is no style.
///
/// Mutation that must redden it: `ButtonStyle` made `internal`, or its `makeBody` requirement removed.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aThirdPartyModuleCanDeclareButtonAndToggleStyles() throws {
    let positive = try typecheckFile("""
        public struct Chip: ButtonStyle {
            public init() {}
            public func makeBody(configuration: ButtonStyleConfiguration) -> some ElementGroup {
                configuration.label.padding(8).background(configuration.isPressed ? Color.white : Color.black)
            }
        }
        public struct Tap: PrimitiveButtonStyle {
            public init() {}
            public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some ElementGroup {
                let _: ButtonRole? = configuration.role
                return configuration.label.onClick { configuration.trigger() }
            }
        }
        public struct Tick: ToggleStyle {
            public init() {}
            public func makeBody(configuration: ToggleStyleConfiguration) -> some ElementGroup {
                let _: Bool = configuration.isOn
                let _: Binding<Bool> = configuration.$isOn
                let _: Bool = configuration.isMixed
                return configuration.label.onClick { configuration.isOn.toggle() }
            }
        }
        @MainActor public func spellings() {
            let buttons: [any PrimitiveButtonStyle] = [.automatic, .bordered, .borderless, .plain,
                                                       .borderedProminent, .link, .glass, .glassProminent, Tap()]
            _ = buttons
            _ = Button("Go") { }.buttonStyle(Chip()).buttonStyle(.link).buttonStyle(Tap())
            _ = Column { Button("A") { } }.buttonStyle(Chip())
            _ = Toggle("T", isOn: .constant(true)).toggleStyle(.switch).toggleStyle(.checkbox)
                .toggleStyle(.button).toggleStyle(Tick())
            _ = Column { Toggle("T", isOn: .constant(true)) }.toggleStyle(Tick())
            _ = Picker("P", selection: .constant(1)) { Text("A").tag(1) }.pickerStyle(.inline)
        }
        """, importing: "MetalUI")
    print("STYLE GUARD G-BY1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let badBody = try typecheckFile("""
        public struct Bad: ButtonStyle {
            public init() {}
            public func makeBody(configuration: ButtonStyleConfiguration) -> Int { 0 }
        }
        """, importing: "MetalUI")
    let forged = try typecheckFile("""
        @MainActor public func forged(label: ButtonStyleConfiguration.Label) {
            _ = ButtonStyleConfiguration(role: nil, label: label, isPressed: true)
        }
        """, importing: "MetalUI")
    let notAStyle = try typecheckFile("""
        @MainActor public func notAStyle() { _ = Button("Go") { }.buttonStyle(42) }
        """, importing: "MetalUI")
    print("STYLE GUARD G-BY1 negatives: badBody=\(badBody.succeeded) forged=\(forged.succeeded) "
          + "notAStyle=\(notAStyle.succeeded)")
    try #require(positive.succeeded != badBody.succeeded && positive.succeeded != forged.succeeded
                    && positive.succeeded != notAStyle.succeeded,
                 """
                 the arms must disagree, or the guard measures nothing:
                 \(positive.output)
                 \(badBody.output)
                 \(forged.output)
                 \(notAStyle.output)
                 """)
    #expect(positive.succeeded, "every style spelling must compile from a plain import:\n\(positive.output)")
    #expect(!badBody.succeeded, "a Body that is no ElementGroup is rejected:\n\(badBody.output)")
    #expect(!forged.succeeded, "a configuration cannot be built outside the module:\n\(forged.output)")
    #expect(!notAStyle.succeeded, "a non-style is rejected:\n\(notAStyle.output)")
}

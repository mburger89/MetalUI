import Testing
import MetalUITestSupport

// Presentations and hover, lane 2, guards 2.G5–2.G11 (rulings `SV-C`, `SV-D`,
// `SV-I`, `SV-K`, `SV-N`, `SV-AD` items 2–3; spec §6.2). Whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import — a `@testable` test
// cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `SV-I closed`, `SV-I non-text`,
// `SV-K spellings`, `SV-K decoration order`, `SV-D read-only`,
// `SV-I titleVisibility` and `SV-N spellings` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **2.G5** (`SV-I` item 2). `AlertActions` is closed: a type outside MetalUI
/// cannot conform (its one requirement is SPI); the control — a `Button` in
/// an alert — compiles.
///
/// Mutation **MG2.5**: make the requirement public (the fabricated conformance
/// compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anOutsideTypeCannotConformToAlertActions() throws {
    let fabricated = try typecheckFile("""
        struct Mine: AlertActions {
            func _alertButtons() -> _AlertButtons { fatalError() }
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        @MainActor func good(_ shown: Binding<Bool>) -> some ElementGroup {
            Box().alert("A", isPresented: shown) { Button("OK") {} }
        }
        """, importing: "MetalUI")
    print("""
        SV-I closed: fabricated succeeded=\(fabricated.succeeded) messages=[\(fabricated.messages)]; \
        control succeeded=\(control.succeeded) messages=[\(control.messages)]
        """)
    try #require(fabricated.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(fabricated.output)\n\(control.output)")
    #expect(!fabricated.succeeded, "an outside conformance to AlertActions must not compile:\n\(fabricated.output)")
    #expect(control.succeeded, "a Button action must compile outside the module:\n\(control.output)")
}

/// **2.G6** (`SV-AD` item 3, amended by `SV-AO` item 4). A `Button` whose
/// label is not a `Text` **is** an alert action now (its title is the label's
/// first `Text`); a `TextField` still is not (carried, `SV-AO` item 5), so a
/// call putting one in the actions does not compile (the negative), and the
/// control with only buttons does.
///
/// Mutations **MG2.6a**: restrict the conformance back to `Label == Text` (the
/// non-Text arm fails to compile); **MG2.6b**: make `TextField` an
/// `AlertActions` (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aNonTextButtonIsAnAlertActionButATextFieldIsNot() throws {
    let nonText = try typecheckFile("""
        @MainActor func good(_ shown: Binding<Bool>) -> some ElementGroup {
            Box().alert("A", isPresented: shown) {
                Button(action: {}) { Box().frame(width: Pixels(10), height: Pixels(10)) }
                Button(action: {}) { Text("Delete") }
            }
        }
        """, importing: "MetalUI")
    let field = try typecheckFile("""
        @MainActor func bad(_ shown: Binding<Bool>, _ text: Binding<String>) -> some ElementGroup {
            Box().alert("A", isPresented: shown) {
                TextField("Name", text: text)
                Button("OK") {}
            }
        }
        """, importing: "MetalUI")
    print("""
        SV-AO non-text button: succeeded=\(nonText.succeeded) messages=[\(nonText.messages)]; \
        text field succeeded=\(field.succeeded) messages=[\(field.messages)]
        """)
    try #require(nonText.succeeded && !field.succeeded,
                 """
                 a non-Text-labelled button must compile and a TextField must not, or this \
                 guard cannot fail:
                 non-text:
                 \(nonText.output)
                 field:
                 \(field.output)
                 """)
}

/// **2.G7** (`SV-C`, `SV-D`, `SV-I`, `SV-K`, `SV-AD` item 2). Every
/// presentation spelling of spec §2 typechecks from an external module, each
/// closure calling a `@MainActor` model: both importers, the exporter with and
/// without its defaults, the async calls from a `Task` in a `Button` action
/// and from a `Window`, every alert and confirmation-dialog form with `if`,
/// `if`/`else` and `for` in the actions builder, `ContentType.json` and a
/// custom type with extensions, on legacy and typed content.
///
/// Mutation **MG2.7**: rename one spelling's label in the fixture
/// (`allowedContentTypes:` → `contentTypes:` on the importer — it fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func thePresentationSpellingsTypecheckFromAnExternalModule() throws {
    let result = try typecheckFile("""
        import Foundation
        @MainActor final class Model {
            var urls: [URL] = []
            var log: [String] = []
            func note(_ s: String) { log.append(s) }
        }
        let keymap = ContentType("com.example.keymap", conformingTo: [.json], filenameExtensions: ["keymap"])
        @MainActor func tree(_ m: Model, _ shown: Binding<Bool>, _ names: [String], _ flag: Bool,
                             _ item: String?) -> some Element {
            Column {
                Text("a")
                    .fileImporter(isPresented: shown, allowedContentTypes: [.json, keymap],
                                  allowsMultipleSelection: true) { result in
                        m.urls = (try? result.get()) ?? []
                    }
                    .fileImporter(isPresented: shown, allowedContentTypes: [ContentType.json]) { result in
                        if case .success(let url) = result { m.urls = [url] }
                    }
                    .fileExporter(isPresented: shown, item: Data(), contentTypes: [.json],
                                  defaultFilename: "keymap") { result in
                        m.note("\\(result)")
                    } onCancellation: {
                        m.note("cancelled")
                    }
                    .fileExporter(isPresented: shown, item: "text") { _ in m.note("done") }
                    .alert("Delete?", isPresented: shown) {
                        Button("Delete", role: .destructive) { m.note("delete") }
                        Button("Cancel", role: .cancel) { m.note("cancel") }
                    } message: {
                        Text("This cannot be undone.")
                    }
                    .alert("Choose", isPresented: shown) {
                        if flag { Button("A") { m.note("a") } } else { Button("B") { m.note("b") } }
                        if flag { Button("C") { m.note("c") } }
                        for name in names { Button(name) { m.note(name) } }
                    }
                    .alert("Item", isPresented: shown, presenting: item) { name in
                        Button("Delete \\(name)", role: .destructive) { m.note(name) }
                    } message: { name in
                        Text(name)
                    }
                    .alert("Item", isPresented: shown, presenting: item) { name in
                        Button("Open \\(name)") { m.note(name) }
                    }
                    .confirmationDialog("Confirm?", isPresented: shown) {
                        Button("Delete", role: .destructive) { m.note("delete") }
                    }
                    .confirmationDialog("Confirm?", isPresented: shown) {
                        Button("OK") { m.note("ok") }
                    } message: {
                        Text("Sure?")
                    }
                    .alert("Empty", isPresented: shown) {}
                HStack {
                    ProposalText("typed")
                        .fileImporter(isPresented: shown, allowedContentTypes: [.json]) { _ in m.note("t") }
                        .alert("Typed", isPresented: shown) { Button("OK") { m.note("ok") } }
                }
            }
        }
        struct Opener: Component {
            let m: Model
            @Environment(\\.fileDialogs) var dialogs
            var content: some ElementGroup {
                let dialogs = dialogs
                return Button("Open") {
                    Task { @MainActor in
                        do {
                            m.urls = try await dialogs.openFiles(allowedContentTypes: [.json],
                                                                 allowsMultipleSelection: true)
                            if let url = try await dialogs.saveFile(contentTypes: [.json],
                                                                   defaultFilename: "theme") {
                                m.urls.append(url)
                            }
                            _ = try await dialogs.saveFile()
                        } catch let error as FileDialogError {
                            switch error {
                            case .noWindow, .unavailable, .busy, .platform: m.note("\\(error)")
                            }
                        } catch {
                            m.note("\\(error)")
                        }
                    }
                }
            }
        }
        @MainActor func command(_ window: Window, _ m: Model) async throws {
            m.urls = try await window.fileDialogs.openFiles(allowedContentTypes: [.json])
            let failure: FileExportError = .noItem
            m.note("\\(failure) \\(ContentType.json.preferredFilenameExtension ?? "")")
        }
        """, importing: "MetalUI")
    print("SV-K spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "every presentation spelling must compile:\n\(result.output)")
}

/// **2.G8** (`SV-K` item 1; divergence 120 retired for this scope by `ES-A`). A legacy
/// `Self`-returning decoration written after a presentation modifier compiles.
///
/// Mutation **MG2.8** (`ES-A`): delete `extension PresentationScope: StyledElement` (refused for `onClick`).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aLegacyDecorationAfterAPresentationModifierCompiles() throws {
    let after = try typecheckFile("""
        @MainActor func tree(_ shown: Binding<Bool>) -> some Element {
            Column { Text("a").alert("A", isPresented: shown) {}.onClick {}.padding(4) }
        }
        """, importing: "MetalUI")
    print("SV-K decoration order: after succeeded=\(after.succeeded) messages=[\(after.messages)]")
    #expect(after.succeeded, "\(after.output)")
}

/// **2.G9** (`SV-D` item 4). `EnvironmentValues.fileDialogs` is read-only
/// outside MetalUI: reading it compiles (the control), writing it does not —
/// the window is its one source.
///
/// Mutation **MG2.9**: make the setter public (the write compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func fileDialogsIsReadOnlyOutsideMetalUI() throws {
    let read = try typecheckFile("""
        @MainActor func read(_ values: EnvironmentValues) -> FileDialogs { values.fileDialogs }
        """, importing: "MetalUI")
    let write = try typecheckFile("""
        @MainActor func write(_ values: inout EnvironmentValues, _ other: EnvironmentValues) {
            values.fileDialogs = other.fileDialogs
        }
        """, importing: "MetalUI")
    print("""
        SV-D read-only: read succeeded=\(read.succeeded); write succeeded=\(write.succeeded) \
        messages=[\(write.messages)]
        """)
    try #require(read.succeeded && !write.succeeded,
                 "the read must compile and the write must not:\nread:\n\(read.output)\nwrite:\n\(write.output)")
}

/// **2.G10** (`SV-I` item 1, amended by `SV-AO` item 3). `confirmationDialog`'s
/// `titleVisibility:` is offered with SwiftUI's `Visibility`, on both the
/// actions-only and the message spellings; the call without it compiles too.
///
/// Mutation **MG2.10**: remove the parameter from the message spelling (the
/// second arm fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func titleVisibilityIsOffered() throws {
    let control = try typecheckFile("""
        @MainActor func tree(_ shown: Binding<Bool>) -> some ElementGroup {
            Box().confirmationDialog("A", isPresented: shown) { Button("OK") {} }
        }
        """, importing: "MetalUI")
    let offered = try typecheckFile("""
        @MainActor func tree(_ shown: Binding<Bool>) -> some ElementGroup {
            Box().confirmationDialog("A", isPresented: shown, titleVisibility: .visible) { Button("OK") {} }
                .confirmationDialog("B", isPresented: shown, titleVisibility: Visibility.hidden) {
                    Button("OK") {}
                } message: { Text("m") }
        }
        """, importing: "MetalUI")
    print("""
        SV-AO titleVisibility: control succeeded=\(control.succeeded); offered \
        succeeded=\(offered.succeeded) messages=[\(offered.messages)]
        """)
    try #require(control.succeeded && offered.succeeded,
                 "both must compile:\n\(control.output)\n\(offered.output)")
}

/// **2.G11** (`SV-N` item 1). `onHover` and `onContinuousHover` typecheck from
/// an external module on both vocabularies — a legacy `Box`/`Text` (returning
/// `Self`, so a legacy decoration may follow) and typed content (a
/// `HoverModifier`) — matching on `HoverPhase`.
///
/// Mutation **MG2.11**: rename `onContinuousHover` to `onContinousHover` in
/// the fixture (it fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func onHoverTypechecksOnBothVocabularies() throws {
    let result = try typecheckFile("""
        @MainActor final class Model {
            var hovered = false
            var at: Point<Pixels>?
        }
        @MainActor func tree(_ m: Model) -> some Element {
            Column {
                Box().frame(width: Pixels(10), height: Pixels(10))
                    .onHover { m.hovered = $0 }
                    .onClick {}
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): m.at = point
                        case .ended: m.at = nil
                        }
                    }
                    .background(.accent)
                Text("t").onHover(perform: { hovering in m.hovered = hovering })
                HStack {
                    ProposalText("typed").onHover { m.hovered = $0 }
                    Rectangle().onContinuousHover { if case .active = $0 { m.hovered = true } }
                }
            }
        }
        """, importing: "MetalUI")
    print("SV-N spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "every hover spelling must compile:\n\(result.output)")
}

import Testing
import MetalUITestSupport

// Text selection typecheck guards G1–G3 (spec §4, rulings `SL-A`, `SL-L`, `SL-M`).
// Whole-file Swift 6 against a PLAIN import (`typecheckFile`, ruling SA-P) or a
// function body (`typecheck`): what an external module may write.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `SL GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — SL GUARD skipped"

/// **G1 — `TextSelection` has SwiftUI's shape.** The three initialisers, a
/// `switch` over both `Indices` cases and `isInsertion` compile from a plain
/// import; the control asks for a spelling SwiftUI does not have (`isEmpty`)
/// and must not compile, so the positive is not vacuous.
///
/// Mutation that must redden it: rename `isInsertion`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func textSelectionIsSwiftUIsShape() throws {
    let positive = try typecheckFile("""
        @available(macOS 15, *)
        public func spellings(_ text: String) -> Bool {
            let range = text.startIndex..<text.endIndex
            let a = TextSelection(range: range)
            let b = TextSelection(insertionPoint: text.startIndex)
            var set = RangeSet<String.Index>()
            set.insert(contentsOf: range)
            let c = TextSelection(ranges: set)
            for selection in [a, b, c] {
                switch selection.indices {
                case .selection(let r): _ = r
                case .multiSelection(let s): _ = s
                }
            }
            return a.isInsertion || b.isInsertion || c.isInsertion
        }
        """, importing: "MetalUI")
    #expect(positive.succeeded, "SL GUARD G1: the SwiftUI spellings must compile:\n\(positive.output)")

    let control = try typecheckFile("""
        @available(macOS 15, *)
        public func notSwiftUIs(_ text: String) -> Bool {
            TextSelection(insertionPoint: text.startIndex).isEmpty
        }
        """, importing: "MetalUI")
    #expect(!control.succeeded, "a spelling SwiftUI lacks must not compile")
    #expect(control.messages.contains("isEmpty"), "it fails because of isEmpty:\n\(control.output)")
}

/// **G2 — the selection initialisers are SwiftUI's.** `TextField(_:text:selection:)`
/// and `TextEditor(_:text:selection:)` take a `Binding<TextSelection?>`; the
/// separating arm hands a non-optional `Binding<TextSelection>` to each and must
/// not compile (SwiftUI's own signature is optional).
///
/// Mutation that must redden it: make the parameter non-optional (the separating
/// arm then compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSelectionInitialisersAreSwiftUIs() throws {
    let positive = try typecheckFile("""
        @available(macOS 15, *) @MainActor
        public func spellings() {
            let text = Binding<String>(get: { "" }, set: { _ in })
            let selection = Binding<TextSelection?>(get: { nil }, set: { _ in })
            _ = TextField("Title", text: text, selection: selection)
            _ = TextEditor(text: text, selection: selection)
            _ = TextEditor("Note", text: text, selection: selection)
            _ = TextField("Title", text: "", selection: nil, onChange: { _ in }, onSelectionChange: { _ in })
            _ = TextEditor("Note", text: "", selection: nil, onChange: { _ in }, onSelectionChange: { _ in })
        }
        """, importing: "MetalUI")
    #expect(positive.succeeded, "SL GUARD G2: the spellings must compile:\n\(positive.output)")

    for call in ["TextField(\"Title\", text: text, selection: bare)",
                 "TextEditor(text: text, selection: bare)"] {
        let separating = try typecheckFile("""
            @available(macOS 15, *) @MainActor
            public func separating() {
                let text = Binding<String>(get: { "" }, set: { _ in })
                let bare = Binding<TextSelection>(get: { TextSelection(insertionPoint: "".startIndex) }, set: { _ in })
                _ = \(call)
            }
            """, importing: "MetalUI")
        #expect(!separating.succeeded, "a non-optional binding must not be accepted: \(call)")
        #expect(separating.messages.contains("TextSelection"),
                "it fails because of the binding's type:\n\(separating.output)")
    }
}

/// **G3 — the selection internals are unreachable from an external module**
/// (`SA-P`, plain import): `TextSelection.conversionCount`,
/// `init(offsets:in:)`, `TextInputTarget` (with its `selectionSink`) and
/// `TextEditState.seenBinding`. The positive control is the public surface in
/// the same file; each negative must fail for its own name.
///
/// Mutation that must redden it: make `conversionCount` `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSelectionInternalsAreUnreachableFromAnExternalModule() throws {
    let positive = try typecheckFile("""
        @available(macOS 15, *)
        public func publicOnly(_ text: String) -> TextSelection {
            TextSelection(insertionPoint: text.startIndex)
        }
        """, importing: "MetalUI")
    #expect(positive.succeeded, "SL GUARD G3: the control must compile:\n\(positive.output)")

    let negatives: [(name: String, message: String, body: String)] = [
        ("conversionCount", "conversionCount", "@available(macOS 15, *) public func f() -> Int { TextSelection.conversionCount }"),
        ("init(offsets:in:)", "no exact matches in call to initializer", "@available(macOS 15, *) public func f() -> TextSelection { TextSelection(offsets: 0..<1, in: \"a\") }"),
        ("TextInputTarget", "TextInputTarget", "public func f(_ target: TextInputTarget) -> Bool { target.selectionSink == nil }"),
        ("TextEditState", "TextEditState", "public func f(_ state: TextEditState) -> Bool { state.seenBinding == nil }"),
    ]
    for negative in negatives {
        let result = try typecheckFile(negative.body, importing: "MetalUI")
        #expect(!result.succeeded, "\(negative.name) must be unreachable from a plain import")
        #expect(result.messages.contains(negative.message),
                "it must fail because of \(negative.name):\n\(result.output)")
    }
}

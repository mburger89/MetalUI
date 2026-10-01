import Testing
import MetalUITestSupport

// Drag and drop, lane 2, guard G2.1 (ruling `DN-J` item 3; spec §6.4b). Whole-
// file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import — a
// `@testable` test cannot prove what an external module can write (practices
// shape 16). Skips silently where guards skip (CLAUDE.md, "Guards"); grep the
// log for `DN-J preview spelling` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1** (`DN-J` item 3). `draggable(_:preview:)` compiles under
/// `import MetalUI` on a `StyledElement` and on a `ProposalElementGroup`,
/// with SwiftUI's trailing-closure shape and `DraggablePreviewModifier` as
/// the spelled type; a preview closure with no payload does not.
///
/// Mutation **MG2.1**: the `StyledElement` overload removed (the positive
/// fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theDraggablePreviewSpellingCompilesFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        import Foundation
        import MetalUICore

        @MainActor func styled() -> some ElementGroup {
            Box().draggable("s") {
                Text("preview")
            }
        }

        @MainActor func styledType() -> DraggablePreviewModifier<Text, Box<EmptyGroup>> {
            Text("t").draggable(URL(string: "https://example.com")!) { Box() }
        }

        @MainActor func proposal() -> some ProposalElementGroup {
            Rectangle().draggable(Data([1, 2])) {
                Rectangle()
            }
        }

        @MainActor func inAStack() -> some ProposalElementGroup {
            HStack { Rectangle().draggable("s") { Text("p") }; Rectangle() }
        }
        """, importing: "MetalUI")
    let noPayload = try typecheckFile("""
        @MainActor func noPayload() -> some ElementGroup {
            Box().draggable { Text("p") }
        }
        """, importing: "MetalUI")

    print("""
        DN-J preview spelling: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        noPayload succeeded=\(noPayload.succeeded)
        """)

    try #require(spellings.succeeded && !noPayload.succeeded,
                 """
                 the spellings must compile and a payload-less preview must not, or this \
                 guard cannot fail:
                 spellings:
                 \(spellings.output)
                 noPayload:
                 \(noPayload.output)
                 """)
}

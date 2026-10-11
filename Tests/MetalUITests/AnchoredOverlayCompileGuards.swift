import Testing
import MetalUITestSupport

// Overlays and coordinates (C15), lane B guards GB1–GB2 (rulings `OV-A`,
// `OV-B`; spec `docs/superpowers/specs/2026-10-10-overlays-coords-design.md`
// §4.2). Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN
// import — a `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `OV attachment anchor spellings` and
// `OV anchoredOverlay spellings` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **Guard GB1** (`OV-B`; probe T11–T13). SwiftUI's attachment-anchor
/// spellings compile from a plain import on both vocabularies and both
/// presentations: `.rect(.bounds)`, `.rect(.rect(b))`, `.point(.topLeading)`,
/// a stored `PopoverAttachmentAnchor`, and `item:` with the anchor before
/// `arrowEdge:`. **Separating arm**: the anchor written after `arrowEdge:` does
/// not compile (SwiftUI's argument order).
///
/// Mutation **MG-B1**: drop `attachmentAnchor:` from the proposal `item:`
/// overload (the spellings refuse).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func thePopoverAttachmentAnchorSpellingsCompile() throws {
    let spellings = try typecheckFile("""
        struct Note: Identifiable { let id: Int }
        let stored: PopoverAttachmentAnchor = .rect(.rect(Bounds(origin: Point(x: Pixels(1), y: Pixels(2)),
                                                                  size: Size(width: Pixels(3), height: Pixels(4)))))

        @MainActor func legacy(shown: Binding<Bool>, note: Binding<Note?>) -> some Element {
            Column {
                Box().popover(isPresented: shown, attachmentAnchor: .rect(.bounds)) { Text("A") }
                Box().popover(isPresented: shown, attachmentAnchor: .point(.topLeading), arrowEdge: .bottom) { Text("B") }
                Box().popover(item: note, attachmentAnchor: stored, arrowEdge: .leading) { n in Text("\\(n.id)") }
            }
        }

        @MainActor func proposal(shown: Binding<Bool>, note: Binding<Note?>) -> some Element {
            HStack {
                Rectangle().popover(isPresented: shown, attachmentAnchor: .point(.center)) { Text("C") }
                Rectangle().popover(item: note, attachmentAnchor: .point(.bottomTrailing)) { n in Text("\\(n.id)") }
            }
        }
        """, importing: "MetalUI")
    let order = try typecheckFile("""
        @MainActor func view(shown: Binding<Bool>) -> some ElementGroup {
            Box().popover(isPresented: shown, arrowEdge: .top, attachmentAnchor: .rect(.bounds)) { Text("A") }
        }
        """, importing: "MetalUI")
    print("""
        OV attachment anchor spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        order succeeded=\(order.succeeded)
        """)
    try #require(spellings.succeeded && !order.succeeded,
                 "the spellings must compile and the reordered call must not:\n\(spellings.output)\n\(order.output)")
}

/// **Guard GB2** (`OV-A`). The `anchoredOverlay` spellings compile from a
/// plain import on both vocabularies: `isPresented:` and `item:`, the point
/// alone (`.local`, `.topLeading` by default), `in: .global`, `in:
/// .named("canvas")` and an explicit `anchor:`; the result is a
/// `PopoverModifier`. **Separating arm**: `at:` is required.
///
/// Mutation **MG-B2**: drop `in:`'s default (the point-alone spellings refuse).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theAnchoredOverlaySpellingsCompile() throws {
    let spellings = try typecheckFile("""
        struct Request: Identifiable { let id: Int }
        let p = Point(x: Pixels(10), y: Pixels(20))

        @MainActor func legacy(shown: Binding<Bool>, request: Binding<Request?>) -> some ElementGroup {
            Column {
                Box().anchoredOverlay(isPresented: shown, at: p) { Text("A") }
                Box().anchoredOverlay(isPresented: shown, at: p, in: .global, anchor: .bottomTrailing) { Text("B") }
                Box().anchoredOverlay(item: request, at: p) { r in Text("\\(r.id)") }
            }
            .coordinateSpace(.named("canvas"))
        }

        @MainActor func proposal(shown: Binding<Bool>, request: Binding<Request?>) -> some Element {
            HStack {
                Rectangle().anchoredOverlay(isPresented: shown, at: p, in: .named("canvas")) { Text("C") }
                Rectangle().anchoredOverlay(item: request, at: p, anchor: .center) { r in Text("\\(r.id)") }
            }
        }

        @MainActor func type(shown: Binding<Bool>) -> PopoverModifier<Rectangle, Text> {
            Rectangle().anchoredOverlay(isPresented: shown, at: p) { Text("T") }
        }
        """, importing: "MetalUI")
    let noPoint = try typecheckFile("""
        @MainActor func view(shown: Binding<Bool>) -> some ElementGroup {
            Box().anchoredOverlay(isPresented: shown) { Text("A") }
        }
        """, importing: "MetalUI")
    print("""
        OV anchoredOverlay spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        noPoint succeeded=\(noPoint.succeeded)
        """)
    try #require(spellings.succeeded && !noPoint.succeeded,
                 "the spellings must compile and the point-less call must not:\n\(spellings.output)\n\(noPoint.output)")
}

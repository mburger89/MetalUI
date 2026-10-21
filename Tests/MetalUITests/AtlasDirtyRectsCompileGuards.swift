import Testing
import MetalUITestSupport

// Plain-import guard for the atlas's dirty rects (`RG-H`, spec test guard `dirtyRectStaysReadableAsATuple`;
// `SA-P`). **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIScene not found — guard skipped"

private let modulesBuilt = canTypecheck(module: "MetalUIScene")

/// `dirtyRect` (the union) and `dirtyRects` (the list) are readable as tuples from a plain import: an
/// app's renderer reads them. Mutation: `dirtyRect` made `internal` -> red.
@Test(.enabled(if: modulesBuilt, skipReason))
func dirtyRectStaysReadableAsATuple() throws {
    let result = try typecheckFile("""
        import MetalUIScene

        public func read(_ atlas: GlyphAtlas) -> Int {
            var total = 0
            if let union = atlas.dirtyRect { total += union.x + union.y + union.width * union.height }
            for rect in atlas.dirtyRects { total += rect.x + rect.y + rect.width * rect.height }
            return total
        }
        """, importing: "MetalUIScene")
    #expect(result.succeeded, "the dirty rects are public tuples:\n\(result.output)")
}

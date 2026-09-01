import Testing
import Foundation
@testable import MetalUILayout

@MainActor
@Test func generatorProducesRawAndRoundedForAFixture() async throws {
    let g = try await generateGolden(fixture: "flex_row_fixed_and_grow",
                                     viewport: CGSize(width: 800, height: 600))
    #expect(g.fixture == "flex_row_fixed_and_grow")
    #expect(g.viewport == [800, 600])
    #expect(g.raw.count == 4)
    #expect(g.rounded.count == g.raw.count)
    #expect(g.rounded.map(\.id) == g.raw.map(\.id))

    // This fixture is exact, so rounding is the identity.
    #expect(g.raw == g.rounded)
}

@MainActor
@Test func generatorRoundsWhenTheBrowserQuantizes() async throws {
    let g = try await generateGolden(fixture: "flex_row_seven_equal",
                                     viewport: CGSize(width: 400, height: 200))
    // Raw carries WebKit's 1/64 values; rounded closes the row on its parent.
    #expect(g.raw.contains { abs($0.width - 14.28125) < 1e-9 })
    let children = g.rounded.filter { $0.id != "root" }
    #expect(children.map(\.width).reduce(0, +) == 100)
}

/// Regenerates every golden from its fixture. Disabled by default: it writes
/// into the source tree, and a golden that regenerates itself on every run
/// cannot catch a regression. Enable deliberately:
///   METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_REGENERATE_GOLDENS"] == "1"))
func regenerateAllGoldens() async throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // MetalUILayoutTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .path
    for (fixture, viewport) in allFixtures {
        let g = try await generateGolden(fixture: fixture, viewport: viewport)
        try writeGolden(g, toSourceTree: root)
    }
}

/// Every fixture in the corpus, with the viewport it is measured at.
@MainActor
let allFixtures: [(String, CGSize)] = [
    ("flex_row_fixed_and_grow", CGSize(width: 800, height: 600)),
    ("flex_row_seven_equal",    CGSize(width: 400, height: 200)),
    ("flex_row_three_fixed",    CGSize(width: 800, height: 600)),
    ("flex_column_three_fixed", CGSize(width: 800, height: 600)),
    ("flex_row_gap",            CGSize(width: 800, height: 600)),
    ("flex_row_grow_uneven",    CGSize(width: 800, height: 600)),
    ("flex_row_shrink",         CGSize(width: 800, height: 600)),
    ("flex_row_fractional_grow", CGSize(width: 800, height: 600)),
    ("flex_row_fractional_grow_clamped", CGSize(width: 800, height: 600)),
    ("flex_row_grow_with_max",  CGSize(width: 800, height: 600)),
    ("flex_row_grow_nonzero_basis", CGSize(width: 800, height: 600)),
    ("flex_row_fractional_shrink", CGSize(width: 800, height: 600)),
    ("flex_column_grow_with_max", CGSize(width: 800, height: 600)),
    ("flex_row_explicit_min",    CGSize(width: 800, height: 600)),
    ("flex_row_percent_basis",   CGSize(width: 800, height: 600)),
    ("flex_row_shrink_to_zero",  CGSize(width: 800, height: 600)),
    ("flex_row_justify_between", CGSize(width: 800, height: 600)),
    ("flex_row_justify_around",  CGSize(width: 800, height: 600)),
    ("flex_row_justify_evenly",  CGSize(width: 800, height: 600)),
    ("flex_column_justify_center", CGSize(width: 800, height: 600)),
    ("flex_row_justify_between_gap", CGSize(width: 800, height: 600)),
    ("flex_row_align_center",        CGSize(width: 800, height: 600)),
    ("flex_row_align_end_with_self", CGSize(width: 800, height: 600)),
    ("flex_row_stretch_mixed",       CGSize(width: 800, height: 600)),
    ("flex_row_reverse",             CGSize(width: 800, height: 600)),
    ("flex_column_reverse_justify_end", CGSize(width: 800, height: 600)),
    ("flex_row_padding_border",         CGSize(width: 800, height: 600)),
    ("flex_column_padding_asymmetric",  CGSize(width: 800, height: 600)),
    ("flex_row_margins",                CGSize(width: 800, height: 600)),
    ("flex_row_margin_with_grow",       CGSize(width: 800, height: 600)),
    ("flex_row_reverse_margins",        CGSize(width: 800, height: 600)),
    ("flex_column_reverse_margins",     CGSize(width: 800, height: 600)),
    ("flex_row_stretch_with_margins",   CGSize(width: 800, height: 600)),
    ("flex_row_grow_space_between_margins", CGSize(width: 800, height: 600)),
    ("flex_percent_padding_nonsquare",   CGSize(width: 800, height: 600)),
    ("flex_nested_padding",              CGSize(width: 800, height: 600)),
    ("flex_nested_percent_padding",      CGSize(width: 800, height: 600)),
    ("flex_percent_child_in_padded",     CGSize(width: 800, height: 600)),
    ("flex_row_stretch_min_height_margins", CGSize(width: 800, height: 600)),
    ("flex_row_reverse_stretch",         CGSize(width: 800, height: 600)),
    ("flex_wrap_uneven",                 CGSize(width: 800, height: 600)),
    ("flex_wrap_stretch_auto_cross",     CGSize(width: 800, height: 600)),
    ("flex_wrap_with_margins_and_padding", CGSize(width: 800, height: 600)),
    ("flex_wrap_align_content_between",   CGSize(width: 800, height: 600)),
    ("flex_wrap_align_content_center",    CGSize(width: 800, height: 600)),
    ("flex_wrap_align_content_stretch",   CGSize(width: 800, height: 600)),
    // The wrapping milestone's third task: `wrap-reverse`, plus the
    // (wrapping x already-shipped feature) pairs the first two tasks measured
    // against WebKit and did not commit. See
    // `docs/superpowers/2026-08-25-wrapping-decisions.md` for the list each
    // one closes.
    ("flex_wrap_grow_and_shrink",          CGSize(width: 800, height: 600)),
    ("flex_wrap_justify_between",          CGSize(width: 800, height: 600)),
    ("flex_wrap_align_items_self",         CGSize(width: 800, height: 600)),
    ("flex_wrap_row_reverse_gap_margin",   CGSize(width: 800, height: 600)),
    ("flex_wrap_main_sizing",              CGSize(width: 800, height: 600)),
    ("flex_wrap_nested_percent_padding",   CGSize(width: 800, height: 600)),
    ("flex_wrap_column_reverse",           CGSize(width: 800, height: 600)),
    ("flex_wrap_align_content_around_evenly", CGSize(width: 800, height: 600)),
    ("flex_wrap_reverse",                  CGSize(width: 800, height: 600)),
    ("flex_wrap_reverse_align_content_end", CGSize(width: 800, height: 600)),
    ("flex_wrap_reverse_row_reverse",      CGSize(width: 800, height: 600)),
    // The content-sizing milestone's Task 6. The 57 fixtures above are
    // structurally blind to it: every child is an empty div whose content size
    // is 0, and 0 is exactly the constant all four wired sites used to
    // substitute — so all four are reached and return the same number. See
    // `docs/superpowers/2026-08-26-content-sizing-decisions.md`, "the
    // re-baseline", for the mechanism per group. These four are the complement.
    ("flex_nested_auto_cross",             CGSize(width: 800, height: 600)),
    ("flex_auto_height_two_levels",        CGSize(width: 800, height: 600)),
    ("flex_wrap_min_vs_max_content",       CGSize(width: 800, height: 600)),
    ("flex_item_floored_by_content",       CGSize(width: 800, height: 600)),
    // Divergence 6's fix (ruling TX-H) — a COLUMN's `auto` cross size is
    // shrink-to-fit, because a column's cross axis is the inline axis. Every
    // one of the 61 fixtures above is blind to it by construction: their boxes
    // are empty divs whose min-content and max-content widths are the SAME
    // number, so fit-content and max-content cannot be told apart in any of
    // them — which is why "no golden moved" was weak evidence for this change
    // and why these five exist, with `flex_row_block_axis_max_content` below
    // as the row that guards the `!isRow` confining them. Each child that
    // matters here is a WRAPPING flex
    // container, the only content in this framework other than text whose two
    // intrinsic widths differ.
    ("flex_column_fit_content",             CGSize(width: 800, height: 600)),
    ("flex_column_fit_content_floor",       CGSize(width: 800, height: 600)),
    ("flex_column_fit_content_margins",     CGSize(width: 800, height: 600)),
    ("flex_column_fit_content_nested",      CGSize(width: 800, height: 600)),
    ("flex_column_fit_content_nested_auto", CGSize(width: 800, height: 600)),
    // The other half of the axis rule, and the guard on the `!isRow` that
    // confines the four above: a ROW's cross axis is the BLOCK axis, which
    // content-sizes. Added because extending the fit-content branch to rows
    // reddened **nothing** out of 395.
    ("flex_row_block_axis_max_content",      CGSize(width: 800, height: 600)),
    // The stack-container milestone's Task 4 — the first browser evidence for
    // `Display.stack`. CSS has no stack, so the oracle is a one-cell grid
    // (`display: grid` + `grid-area: 1/1` on every child); see
    // `StackFixtureTests.swift`'s header comment for the full mapping. The
    // three alignment fixtures share geometry deliberately (same root, same
    // child, three alignments) so they read as a differential rather than
    // three unrelated numbers. `stack_sizes_to_largest` makes the stack a
    // MEASURED child of a fixed-size flex root rather than the declared-size
    // document root the milestone's own brief first proposed — a declared
    // size asserts nothing about max-over-children, and an `auto`-sized root
    // would hit this engine's own divergence 4 (an `auto` root axis takes the
    // offered space rather than shrink-wrapping), unrelated to stacking.
    ("stack_alignment_center",         CGSize(width: 800, height: 600)),
    ("stack_alignment_topleading",     CGSize(width: 800, height: 600)),
    ("stack_alignment_bottomtrailing", CGSize(width: 800, height: 600)),
    ("stack_stretch",                  CGSize(width: 800, height: 600)),
    // Fix round 1's finding: `stretch` fills an axis only when the child's own
    // size on it is `auto` (CSS Box Alignment's rule). `stack_stretch` above
    // covers the auto branch; this covers the declared-size branch that
    // motivated the fix -- a 20x10 child stays 20x10 at the start edge rather
    // than being stretched to the cell.
    ("stack_stretch_declared_size",    CGSize(width: 800, height: 600)),
    ("stack_sizes_to_largest",         CGSize(width: 800, height: 600)),
    // Task 6 -- the seam between the two paths. `layOutChildren` branches on
    // `display` and a dispatch bug hides exactly where a stack and a flex
    // container meet: neither direction is exercised by a fixture where the
    // stack is the document root, which is FIVE of the six above --
    // `stack_sizes_to_largest` is already a child of a flex root, deliberately,
    // for the reason its own comment gives. See `StackFixtureTests.swift`'s
    // nesting-fixture comments for what each one distinguishes and why its
    // geometry is not simplifiable.
    ("stack_in_flex",                  CGSize(width: 800, height: 600)),
    ("flex_in_stack",                  CGSize(width: 800, height: 600)),
    // The milestone's final review: an auto-sized stack holding a PERCENTAGE
    // child that has content. Ruling ST-E claimed this engine already matched
    // WebKit here, generalising from a Task 1 probe whose percentage child was
    // EMPTY -- a shape for which "contributes zero" and "contributes its
    // content size" are the same number. They are not the same number here,
    // and the engine answered `40x30 / 20x30` against WebKit's `80x30 / 40x30`
    // until `layOutStack`'s `resolvedAxis` stopped folding an unresolvable
    // percentage to 0.
    ("stack_percent_child_with_content", CGSize(width: 800, height: 600)),
    // The absolute-positioning milestone's Task 5 — the first browser evidence
    // for `position: absolute`, which is directly expressible in CSS and needs
    // no oracle translation the way `Display.stack` did. Each fixture's
    // geometry IS its assertion; see `AbsoluteFixtureTests.swift`'s per-test
    // doc comments for what wrong implementation each one catches.
    ("abs_containing_block_skips_static", CGSize(width: 800, height: 600)),
    ("abs_percent_insets_nonsquare",       CGSize(width: 800, height: 600)),
    ("abs_removed_from_flow",              CGSize(width: 800, height: 600)),
    ("abs_over_constrained",               CGSize(width: 800, height: 600)),
    // A fifth fixture, alongside the four above: an insufficiently-specified
    // sizing case Task 4 left unverified. `placeAbsolute`'s fallback to
    // content measurement for "one inset only, with an auto size" was a
    // plausible generalisation of its documented cases, but no oracle had
    // checked it — exactly the shape that hid the Stack milestone's stretch
    // bug.
    ("abs_single_inset_auto_size",         CGSize(width: 800, height: 600)),
    ("sizing_root_percent",                CGSize(width: 800, height: 600)),
    ("sizing_over_constrained_grows",      CGSize(width: 800, height: 600)),
    ("sizing_specified_suggestion",        CGSize(width: 800, height: 600)),
    ("sizing_specified_suggestion_is_used_value", CGSize(width: 800, height: 600)),
]

/// The committed goldens must still be what the browser says.
///
/// This is the ONLY test that drives WebKit to check the corpus, and it is the
/// counterweight to the engine comparisons reading `Golden/*.json` instead of
/// regenerating. It fails when a fixture's HTML or CSS is edited without
/// `METALUI_REGENERATE_GOLDENS=1` being re-run, which would otherwise leave the
/// engine cheerfully agreeing with a golden that no longer describes its fixture.
///
/// Exact equality, not a tolerance: WebKit is deterministic for a given fixture
/// and viewport, and the JSON round-trip is lossless. A mismatch here means the
/// fixture changed, the browser changed, or the golden was hand-edited — all of
/// which want a human to look, not a tolerance to paper over.
@MainActor
@Test func committedGoldensMatchTheBrowser() async throws {
    for (fixture, viewport) in allFixtures {
        let fresh = try await generateGolden(fixture: fixture, viewport: viewport)
        let committed = try loadGolden(fixture)
        guard fresh != committed else { continue }

        // Report only the boxes that actually differ. Expanding two whole
        // GoldenFiles buries the one changed number in a wall of struct dump.
        let committedByID = Dictionary(uniqueKeysWithValues: committed.rounded.map { ($0.id, $0) })
        let diffs = fresh.rounded.compactMap { box -> String? in
            guard let old = committedByID[box.id] else { return "\(box.id): absent from golden" }
            guard old != box else { return nil }
            return "\(box.id): browser \(box.x),\(box.y) \(box.width)x\(box.height) "
                 + "vs golden \(old.x),\(old.y) \(old.width)x\(old.height)"
        }
        Issue.record("""
            Golden '\(fixture)' no longer matches the browser.
            \(diffs.isEmpty ? "differs outside `rounded` (raw or viewport)" : diffs.joined(separator: "\n"))
            Regenerate with:
              METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
            """)
    }
}

/// A fixture missing from `allFixtures` never generates a golden and is never
/// compared against anything — it just sits in the directory looking checked.
/// Nothing else in the suite notices, so this counts the files and makes the
/// omission a failure.
@MainActor
@Test func everyFixtureFileIsListedInTheCorpus() throws {
    let onDisk = Bundle.module.urls(forResourcesWithExtension: "html",
                                    subdirectory: "Fixtures") ?? []
    let names = Set(onDisk.map { $0.deletingPathExtension().lastPathComponent })
    let listed = Set(allFixtures.map(\.0))

    #expect(allFixtures.count == onDisk.count,
            "allFixtures lists \(allFixtures.count) fixtures but Fixtures/ holds \(onDisk.count) .html files")
    #expect(names.subtracting(listed).isEmpty,
            "fixtures on disk but absent from allFixtures: \(names.subtracting(listed).sorted())")
    #expect(listed.subtracting(names).isEmpty,
            "fixtures listed in allFixtures but absent from disk: \(listed.subtracting(names).sorted())")
}

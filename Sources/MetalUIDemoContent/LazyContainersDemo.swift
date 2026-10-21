import MetalUI

/// The lazy containers demo (item L1, `LZ-Q`; spec section 6), reached with
/// `METALUI_LAZY_DEMO=1 swift run MetalUIDemo`: four sections, each a lazy container of 10 000
/// children in a scroller, each showing how many of its children are on screen right now (counted by
/// `onAppear`/`onDisappear`, so it includes the two lines of overscan, divergence 637).
///
/// 1. a `LazyVStack` of 10 000 rows of three heights, sized from their content;
/// 2. a `LazyVGrid` with `GridItem(.adaptive(minimum: 60))`, which re-flows as the window resizes (the
///    column count follows the width of the last frame, `LZ-L`);
/// 3. a `LazyHStack` carousel scrolling sideways;
/// 4. a `LazyHGrid` of two fixed rows.
///
/// **The human looks** (`docs/verification/human-checks.md` group LZ, LZ1-LZ5): the counters never exceed the
/// viewport plus overscan while the scrollers move, a fast scroll of the variable rows does not jump or
/// flash, the grid's first frame is not visibly a single column, and resizing re-flows it with no blank
/// band. Nothing here is in the default demo, so the fourteen offscreen images and `Expected.swift` do not
/// move. **Each section is its own function** and the four are composed by a generic composer (the Windows
/// 1 MB stack rule, `demoContent()`'s note); built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func lazyContainersDemoContent() -> some Element {
    lazyDemoComposer(LazyDemoStackSection(), LazyDemoGridSection(), LazyDemoCarouselSection(),
                     LazyDemoHGridSection())
}

/// Two rows of two sections under a title.
@MainActor
func lazyDemoComposer<A: ElementGroup, B: ElementGroup, C: ElementGroup, D: ElementGroup>(
    _ a: A, _ b: B, _ c: C, _ d: D) -> some Element {
    VStack(alignment: .leading, spacing: Pixels(12)) {
        ProposalText("Lazy containers: 10 000 children each, realised near the viewport")
            .font(size: 20)
        HStack(spacing: Pixels(12)) { a; b }
        HStack(spacing: Pixels(12)) { c; d }
    }
    .padding(Edges(all: Pixels(16)))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.surface)
}

/// A section's title and live count over its scroller.
@MainActor
func lazyDemoFrame<Body: ProposalElementGroup>(_ title: String, live: Int, @ProposalContentBuilder _ body: () -> Body)
    -> some ProposalElementGroup {
    VStack(alignment: .leading, spacing: Pixels(6)) {
        ProposalText("\(title) - on screen now: \(live)")
        body()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
}

/// How many children a section has on screen, counted by their lifecycle callbacks.
struct LazyDemoCount {
    var live: Int
    var change: @MainActor (Int) -> Void
}

/// Section 1: variable-height rows in a `LazyVStack`.
struct LazyDemoStackSection: Component {
    @State private var live = 0
    var content: some ProposalElementGroup {
        lazyDemoFrame("LazyVStack, rows of 24, 40, 64", live: live) {
            ProposalScrollView {
                LazyVStack(alignment: .leading, spacing: Pixels(2)) {
                    ForEach(0..<10_000) { index in
                        ProposalText("Row \(index)")
                            .frame(maxWidth: .infinity, minHeight: Pixels([24, 40, 64][index % 3]), alignment: .leading)
                            .background(.surfaceSecondary)
                            .onAppear { live += 1 }
                            .onDisappear { live -= 1 }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.surface)
        }
    }
}

/// Section 2: an adaptive grid.
struct LazyDemoGridSection: Component {
    @State private var live = 0
    var content: some ProposalElementGroup {
        lazyDemoFrame("LazyVGrid, adaptive(minimum: 60)", live: live) {
            ProposalScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: Pixels(8)) {
                    ForEach(0..<10_000) { index in
                        ProposalText("\(index)")
                            .frame(maxWidth: .infinity, minHeight: Pixels(40))
                            .background(.surfaceSecondary)
                            .onAppear { live += 1 }
                            .onDisappear { live -= 1 }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Section 3: a horizontal carousel.
struct LazyDemoCarouselSection: Component {
    @State private var live = 0
    var content: some ProposalElementGroup {
        lazyDemoFrame("LazyHStack carousel", live: live) {
            ProposalScrollView(.horizontal) {
                LazyHStack(spacing: Pixels(8)) {
                    ForEach(0..<10_000) { index in
                        ProposalText("Card \(index)")
                            .frame(width: Pixels(96), height: Pixels(96))
                            .background(.surfaceSecondary)
                            .onAppear { live += 1 }
                            .onDisappear { live -= 1 }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: Pixels(110), maxHeight: .infinity)
        }
    }
}

/// Section 4: a horizontal grid of two fixed rows.
struct LazyDemoHGridSection: Component {
    @State private var live = 0
    var content: some ProposalElementGroup {
        lazyDemoFrame("LazyHGrid, two fixed rows", live: live) {
            ProposalScrollView(.horizontal) {
                LazyHGrid(rows: [GridItem(.fixed(48)), GridItem(.fixed(48))], spacing: Pixels(8)) {
                    ForEach(0..<10_000) { index in
                        ProposalText("\(index)")
                            .frame(width: Pixels(64), height: Pixels(48))
                            .background(.surfaceSecondary)
                            .onAppear { live += 1 }
                            .onDisappear { live -= 1 }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: Pixels(110), maxHeight: .infinity)
        }
    }
}

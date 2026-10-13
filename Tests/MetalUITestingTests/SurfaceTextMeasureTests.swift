import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C23 lane 1 (`GT-B`...`GT-D`): `EnvironmentValues.textMeasurer`, SwiftUI's
// `resolve(_:)` + `ResolvedText.measure(in:)`. Noto Sans through
// `harnessWindow`, so a literal agrees on every platform; every expectation is
// the frame a `Text` is laid out at, or a text system's own answer.

@MainActor final class MeasureBox {
    var sizes: [Size<Pixels>] = []
}

private let unbounded = Size(width: Pixels.infinity, height: Pixels.infinity)

/// Measures `text` at `proposal` while its body builds, `count` times.
private struct Measuring: Component {
    let box: MeasureBox
    let text: Text
    let proposal: Size<Pixels>
    var count = 1
    @Environment(\.textMeasurer) var measurer
    var content: some ElementGroup {
        let _ = record()
        Box().frame(width: 1, height: 1)
    }
    private func record() {
        box.sizes = []
        let resolved = measurer.resolve(text)
        for _ in 0..<count { box.sizes.append(resolved.measure(in: proposal)) }
    }
}

private struct MeasuringProposal: Component {
    let box: MeasureBox
    let text: ProposalText
    @Environment(\.textMeasurer) var measurer
    var content: some ElementGroup {
        let _ = box.sizes = [measurer.resolve(text).measure(in: unbounded)]
        Box().frame(width: 1, height: 1)
    }
}

private func same(_ a: Size<Pixels>, _ b: Bounds<Pixels>) -> Bool {
    a.width == b.size.width && a.height == b.size.height
}

/// 1.1 — a measured text is the frame a laid-out text gets (probe A0), by default
/// and under a 26 pt font. Mutation: `measure(in:)` resolves `.unstyled`.
@Test @MainActor func aMeasuredTextIsTheFrameALaidOutTextGets() throws {
    let plain = MeasureBox(), big = MeasureBox()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Measuring(box: plain, text: Text("12.5 mm"), proposal: unbounded)
            Text("12.5 mm").id("t")
            VStack(spacing: 0) {
                Measuring(box: big, text: Text("12.5 mm"), proposal: unbounded)
                Text("12.5 mm").id("t26")
            }.font(.system(size: 26))
        }
    }
    window.tick()
    let laid = try window.frame(ofID: "t"), laid26 = try window.frame(ofID: "t26")
    try #require(plain.sizes.count == 1 && big.sizes.count == 1)
    #expect(laid.size.width > 0 && laid26.size.width > laid.size.width)
    #expect(same(plain.sizes[0], laid), "\(plain.sizes[0]) vs \(laid)")
    #expect(same(big.sizes[0], laid26), "\(big.sizes[0]) vs \(laid26)")
}

/// 1.2 — the environment at the reading point. Mutation: the measurer
/// snapshots the root environment.
@Test @MainActor func theMeasureReadsTheEnvironmentAtTheReadingPoint() throws {
    let outside = MeasureBox(), inside = MeasureBox()
    _ = try harnessWindow {
        VStack(spacing: 0) {
            Measuring(box: outside, text: Text("Width"), proposal: unbounded)
            VStack(spacing: 0) {
                Measuring(box: inside, text: Text("Width"), proposal: unbounded)
            }.font(.system(size: 26))
        }
    }
    try #require(outside.sizes.count == 1 && inside.sizes.count == 1)
    #expect(inside.sizes[0].width > outside.sizes[0].width)
    #expect(inside.sizes[0].height > outside.sizes[0].height)
}

/// 1.3 — a width proposal wraps and a short height caps the lines (probes B,
/// C), equal to the laid-out frame. Mutation: `nil` height passed on.
@Test @MainActor func aNarrowProposalWrapsAndAShortHeightCapsTheLines() throws {
    let long = "alpha beta gamma delta epsilon zeta eta theta"
    let line = MeasureBox(), narrow = MeasureBox(), capped = MeasureBox()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Measuring(box: line, text: Text("x"), proposal: unbounded)
            Measuring(box: narrow, text: Text(long), proposal: Size(width: Pixels(60), height: .infinity))
            Measuring(box: capped, text: Text(long), proposal: Size(width: Pixels(60), height: Pixels(5)))
            Text(long).frame(width: 60).id("wrapped")
        }
    }
    let lineHeight = try #require(line.sizes.first).height
    let n = try #require(narrow.sizes.first), c = try #require(capped.sizes.first)
    #expect(n.width <= Pixels(60))
    #expect(n.height >= lineHeight * Pixels(2), "wrapped to several lines")
    #expect(c.height == lineHeight, "a height below one line keeps one line")
    #expect(c.height < n.height)
    #expect(same(n, try window.frame(ofID: "wrapped")))
}

/// 1.4 — measuring lays nothing out and builds nothing: 50 measures add no
/// layout measure call, no build and no placement. Mutation: `resolve`
/// registers a native leaf.
@Test @MainActor func measuringLaysNothingOutAndBuildsNothing() throws {
    func run(count: Int, measuring: Bool) throws -> (FrameWork, CountingTextSystem) {
        let box = MeasureBox()
        let counting = CountingTextSystem(harnessTextSystem())
        let window = try TestWindow(size: sz(400, 300), textSystem: { counting }) {
            VStack(spacing: 0) {
                Text("fixed")
                if measuring { Measuring(box: box, text: Text("12.5 mm"), proposal: unbounded, count: count) }
            }
        }
        window.tick()
        counting.reset(); window.resetFrameWork()
        window.window.setNeedsRedraw(); window.tick()
        let w = window.frameWork
        return (w.dropFirst().reduce(w[0], +), counting)
    }
    let (base, baseCounting) = try run(count: 0, measuring: false)
    let (one, oneCounting) = try run(count: 1, measuring: true)
    let (fifty, fiftyCounting) = try run(count: 50, measuring: true)
    #expect(one.builds == base.builds && fifty.builds == base.builds)
    #expect(fifty.layoutMeasureCalls == one.layoutMeasureCalls)
    #expect(fifty.layoutMeasureCalls == base.layoutMeasureCalls)
    #expect(fiftyCounting.places == baseCounting.places && oneCounting.places == baseCounting.places)
    let perMeasure = oneCounting.measures - baseCounting.measures
    try #require(perMeasure > 0)
    #expect(fiftyCounting.measures - baseCounting.measures == 50 * perMeasure)
    #expect(fiftyCounting.layouts == 0)
}

/// 1.5 — a rich text and a Markdown literal measure as they lay out (`RT-F`).
/// Mutation: the styled path takes the plain one.
@Test @MainActor func aRichTextMeasuresAsItLaysOut() throws {
    let rich = MeasureBox(), markdown = MeasureBox(), plain = MeasureBox()
    var attributed = AttributedString("small ")
    var big = AttributedString("BIG")
    big.font = .system(size: 30)
    attributed.append(big)
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Measuring(box: rich, text: Text(attributed), proposal: unbounded)
            Text(attributed).id("rich")
            Measuring(box: markdown, text: Text("a **bold** word"), proposal: unbounded)
            Text("a **bold** word").id("md")
            Measuring(box: plain, text: Text(verbatim: "a **bold** word"), proposal: unbounded)
        }
    }
    try #require(rich.sizes.count == 1 && markdown.sizes.count == 1 && plain.sizes.count == 1)
    #expect(same(rich.sizes[0], try window.frame(ofID: "rich")))
    #expect(same(markdown.sizes[0], try window.frame(ofID: "md")))
    #expect(markdown.sizes[0].width != plain.sizes[0].width, "the literal is parsed, the verbatim one is not")
}

/// 1.6 — the `ProposalText` overload. Mutation: it measures a `Text`'s default.
@Test @MainActor func aProposalTextMeasuresAsItLaysOut() throws {
    let box = MeasureBox()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            MeasuringProposal(box: box, text: ProposalText("12.5 mm").font(size: 20))
            ProposalText("12.5 mm").font(size: 20).id("p")
        }
    }
    let size = try #require(box.sizes.first)
    #expect(same(size, try window.frame(ofID: "p")))
    #expect(size.height > 16)
}

/// 1.7 — the empty string is (0, 0), the layout's answer (divergence 295).
/// Mutation: a lower bound applied.
@Test @MainActor func anEmptyStringMeasuresZeroByZero() throws {
    let box = MeasureBox()
    _ = try harnessWindow {
        VStack(spacing: 0) { Measuring(box: box, text: Text(""), proposal: unbounded) }
    }
    let size = try #require(box.sizes.first)
    #expect(size.width == 0 && size.height == 0)
}

/// 1.8 — a `\.self` reset keeps the measurer. Mutation: `scopedValues` stops
/// restoring the system box.
@Test @MainActor func anEnvironmentResetKeepsTheMeasurer() throws {
    let box = MeasureBox(), outside = MeasureBox()
    _ = try harnessWindow {
        VStack(spacing: 0) {
            Measuring(box: outside, text: Text("12.5 mm"), proposal: unbounded)
            VStack(spacing: 0) {
                Measuring(box: box, text: Text("12.5 mm"), proposal: unbounded)
            }.environment(\.self, EnvironmentValues())
        }
    }
    let size = try #require(box.sizes.first)
    #expect(size.width > 0)
    #expect(size.width == outside.sizes.first?.width)
}

/// 1.9 — a measurer no frame stamped traps naming itself. Mutation: return zero.
@Test @MainActor func aMeasurerWithNoFrameTrapsNamingItself() async {
    await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        _ = await MainActor.run { EnvironmentValues().textMeasurer.resolve(Text("x")) }
    }
}

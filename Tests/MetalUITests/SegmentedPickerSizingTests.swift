import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// A segmented `Picker` no longer starves its title (round 4 item R4-3a, ruling `SR-G`, record 210,
// probe `docs/probes/swiftui-segmented-sizing.swift`, recorded in `swiftui-segmented-sizing-run.txt`).
//
// The literals are MetalUI's CoreText readings at scale 1 (the probe's SwiftUI readings are named in each
// comment, MetalUI's ahead by the divergence-81 +1 in SwiftUI's rows). "Vanilla", "Chocolate" and
// "Strawberry mint" are 39, 62 and 97 wide before the 24 of chrome: natural widths 64, 86 and 121 once
// the pill rounds each, ideal 3 × 121 = 363 (SwiftUI 363), floor 64 + 86 + 121 = 271 (SwiftUI 271).

@MainActor @ElementBuilder private func threeFlavors() -> some ElementGroup {
    Text("Vanilla").tag(0)
    Text("Chocolate").tag(1)
    Text("Strawberry mint").tag(2)
}

private func px(_ value: Float) -> Pixels { Pixels(value) }

/// One frame of `root` in a `width` × `height` window, bounds recorded, nothing unlowerable.
@MainActor
private func read<E: Element>(_ root: E, width: Float = 420, height: Float = 420) throws -> Frame {
    try controlRender(root, width: width, height: height)
}

/// The segment widths: the option click targets, left to right.
@MainActor private func segments(_ frame: Frame) -> [Float] {
    options(frame.hitboxes).map { $0.bounds.size.width.value }
}

@MainActor private func options(_ hitboxes: [Hitbox]) -> [Hitbox] {
    hitboxes.filter { $0.handlers.onClick != nil }.sorted { $0.bounds.origin.x.value < $1.bounds.origin.x.value }
}

@MainActor private func size(_ frame: Frame, _ path: [Int]) throws -> (width: Float, height: Float) {
    let bounds = try #require(frame.elementBounds[controlID(path)], "\(path) recorded no bounds")
    return (bounds.size.width.value, bounds.size.height.value)
}

/// Segment widths against `expected` to a hundredth, named by `what`.
@MainActor private func expectSegments(_ frame: Frame, _ expected: [Float], _ what: String,
                            sourceLocation: SourceLocation = #_sourceLocation) {
    let read = segments(frame)
    #expect(read.count == expected.count && zip(read, expected).allSatisfy { abs($0 - $1) < 0.01 },
            "\(what): segments \(expected), read \(read)", sourceLocation: sourceLocation)
}

@MainActor private func picker(_ title: String = "Flavor") -> Picker<Int, some ElementGroup> {
    Picker(title, selection: .constant(1)) { threeFlavors() }.pickerStyle(.segmented)
}

@MainActor private func alphaBeta(_ title: String) -> Picker<Int, some ElementGroup> {
    Picker(title, selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }.pickerStyle(.segmented)
}

// MARK: - the distribution

/// `EqualWidthRow.widths`: all the widest while the width is nil, infinite or at least `n × widest`; below
/// that an equal share, never under a segment's own width, the rest shared (probe SG2: 335 reads 108, 108,
/// 121 through AX, MetalUI's 107, 107, 121; 280 reads 75, 86, 121; 271 and below 66, 86, 121). Reddened by MA1 (the
/// proposal ignored: every row below 363) and MA2 (no floor: 280, 271 and 200).
@Test func theSegmentWidthsAreAnEqualShareNeverUnderTheNaturalWidth() {
    let natural: [Double] = [64, 86, 121]
    #expect(EqualWidthRow.widths(natural: natural, available: nil) == [121, 121, 121], "no proposal")
    #expect(EqualWidthRow.widths(natural: natural, available: .infinity) == [121, 121, 121], "an infinite one")
    #expect(EqualWidthRow.widths(natural: natural, available: 500) == [121, 121, 121], "more than n × widest")
    #expect(EqualWidthRow.widths(natural: natural, available: 363) == [121, 121, 121], "exactly n × widest")
    #expect(EqualWidthRow.widths(natural: natural, available: 335) == [107, 107, 121])
    #expect(EqualWidthRow.widths(natural: natural, available: 300) == [89.5, 89.5, 121])
    #expect(EqualWidthRow.widths(natural: natural, available: 280) == [73, 86, 121], "the second is held at 86")
    #expect(EqualWidthRow.widths(natural: natural, available: 271) == [64, 86, 121], "the floor")
    #expect(EqualWidthRow.widths(natural: natural, available: 200) == [64, 86, 121], "below the floor: the floor")
    #expect(EqualWidthRow.widths(natural: [], available: 100) == [], "no segments")
    #expect(EqualWidthRow.widths(natural: [50], available: 20) == [50], "one segment below its width")
}

// MARK: - the labelled picker (probe SG3)

/// SG3a, SG3b: a labelled segmented picker in the 420 window of human check SR1 keeps its title on one
/// line. SwiftUI: title 37×16, control 335 (segments 108, 108, 121); MetalUI's 107, 107, 121. Before, the
/// capsule was rigid at 362 and the title read 8 wide and 96 tall. Reddened by MA1 (rigid again), MA3 and MA6
/// (gap 0); **not** by MA4 (a legacy row also answers 335 here: `aShortLabelledPickerKeepsItsIdealInAWiderFrame`
/// and `aLabelledPickerSqueezes…` are the ones that see `isSegmented`).
@Test @MainActor func aSegmentedPickerKeepsItsTitleOnOneLine() throws {
    let padded = try read(VStack(alignment: .leading) { picker() }.padding(Edges(all: px(20))))
    #expect(try size(padded, [0, 0, 0, 0, 0]) == (37, 16), "the title in a padded VStack")
    expectSegments(padded, [107, 107, 121], "in a padded VStack")
    let control = try #require(padded.elementBounds[controlID([0, 0, 0, 1])])
    #expect(control.origin.x.value - 20 == 37 + 8, "the control starts the title and 8 later")
    #expect(control.size.width.value == 335, "the control is what the title leaves of 380")

    let framed = try read(picker().frame(width: px(380)))
    #expect(try size(framed, [0, 0, 0, 0]) == (37, 16), "the title in a 380 frame")
    expectSegments(framed, [107, 107, 121], "in a 380 frame")
}

/// SG3c: `HStack { Text("Flavor"); Picker("") }` at 380. SwiftUI's stack gives the text its ideal and the
/// picker the rest: text 37×16, segments 104, 104, 121; MetalUI's 103, 103, 121 (the empty title keeps its
/// 8, SG1c, so the control is 8 narrower than the hidden-title case). Reddened by MA1, MA3 and MA6; not by MA4.
@Test @MainActor func aStackBesideASegmentedPickerSharesWhatTheTextLeaves() throws {
    let frame = try read(HStack { Text("Flavor"); picker("") }.frame(width: px(380)))
    #expect(try size(frame, [0, 0, 0]) == (37, 16), "the text keeps one line")
    expectSegments(frame, [103, 103, 121], "beside the text")
}

/// SG3e at 300: SwiftUI proposes the control `300 - 8 - 37`, which is 255 (floor 271), so the title is
/// proposed the remainder 21 and answers 20×32 (SwiftUI) and the control is proposed 300 - 8 - 20 = 272
/// (segments 67, 86, 121 by AX). MetalUI: title 19×32, control 273, segments 67, 85, 121. Reddened by MA5 (no
/// control re-proposal: the control keeps its first answer), MA4, MA6, MA1, MA2 and MA3.
@Test @MainActor func aLabelledPickerSqueezesTheTitleBeforeTheSegmentsReachTheirFloor() throws {
    let frame = try read(picker().frame(width: px(300)))
    #expect(try size(frame, [0, 0, 0, 0]) == (19, 32), "the title wraps to two lines (SwiftUI 20×32)")
    expectSegments(frame, [67, 85, 121], "at 300")
    #expect(try size(frame, [0, 0, 1]).width == 273, "the control is re-proposed what the title's answer leaves")
}

/// SG3e at 280: the title is down to two points, one letter a line (SwiftUI 1×96), the control at its
/// floor. MetalUI: title 2×96, segments 64, 85, 121.
@Test @MainActor func aNarrowerLabelledPickerLeavesTheTitleOneLetterWideAtTheFloor() throws {
    let frame = try read(picker().frame(width: px(280)))
    #expect(try size(frame, [0, 0, 0, 0]) == (2, 96), "SwiftUI 1×96")
    expectSegments(frame, [64, 85, 121], "at 280")
}

/// SG3e at 260 and below: the floor 271 plus the gap fills the frame, so the title is 0 wide and 96 tall
/// and the picker answers 279 in a 260 frame (SwiftUI 279×96, MetalUI 278×96: 8 + the 270 floor).
@Test @MainActor func aLabelledPickerBelowItsFloorAnswersTheFloorAndOverflows() throws {
    let frame = try read(picker().frame(width: px(260)))
    #expect(try size(frame, [0, 0]) == (278, 96), "the picker answers its floor and the gap")
    #expect(try size(frame, [0, 0, 0, 0]) == (0, 96), "the title has nothing")
    expectSegments(frame, [64, 85, 121], "at 260")
}

/// SG4h: a long title is squeezed by the control first. SwiftUI: title 83×48, control 289; MetalUI: title
/// 82×48, segments 84, 85, 121 (the title wraps to the 82 points of 380 - 8 - 290).
@Test @MainActor func aLongTitleWrapsAndTheControlKeepsWhatItsIdealLeaves() throws {
    let frame = try read(picker("A rather long title for one picker").frame(width: px(380)),
                         width: 420, height: 100)
    #expect(try size(frame, [0, 0, 0, 0]) == (82, 48), "the title wraps to two lines")
    expectSegments(frame, [84, 85, 121], "beside a long title")
}

/// SG4c: Alpha, Beta titled "Mode" in a 200 frame. SwiftUI answers 161 (title 35, 8, control 118); MetalUI
/// 158 (34, 8, 116: the control keeps its ideal, the segments 58 and 58). MA4 (a legacy row) answers the
/// floor instead of the ideal (`linearStack` lowering) and reddens it, as MA3 and MA6 do.
@Test @MainActor func aShortLabelledPickerKeepsItsIdealInAWiderFrame() throws {
    let frame = try read(alphaBeta("Mode").frame(width: px(200)), width: 420, height: 100)
    #expect(try size(frame, [0, 0]).width == 158, "title, 8, the ideal control")
    expectSegments(frame, [58, 58], "at 200")
}

// MARK: - the hidden title and the stack (probe SG2, SG4)

/// SG2 at 300 and 200 with the title hidden: the control is the proposal down to the floor. SwiftUI at 300
/// reads 91, 90, 121 (AX), MetalUI 90, 89, 121; at 200 the floor 271 overflows the frame (MetalUI 270).
/// Reddened by MA1, MA2 and MA3.
@Test @MainActor func aHiddenTitlePickerTakesTheProposalDownToItsFloor() throws {
    let at300 = try read(picker().labelsHidden().frame(width: px(300)))
    expectSegments(at300, [90, 89, 121], "hidden, 300")
    #expect(try size(at300, [0, 0, 1]).width == 300)

    let at200 = try read(picker().labelsHidden().frame(width: px(200)))
    expectSegments(at200, [64, 85, 121], "hidden, 200")
    #expect(try size(at200, [0, 0, 1]).width == 270, "the control overflows the 200 frame")
}

/// SG4a: `HStack { Text("Mode"); hidden Alpha/Beta }` at 200. The stack's flexibility order puts the
/// narrow-flex picker first and it lands on its floor: SwiftUI picker 111, text 35; MetalUI picker 110,
/// text 34, segments 59, 51. (The old rigid row answered 152 here.)
@Test @MainActor func aStackPutsAHiddenSegmentedPickerOnItsFloor() throws {
    let frame = try read(HStack { Text("Mode"); alphaBeta("").labelsHidden() }.frame(width: px(200)),
                         width: 420, height: 100)
    #expect(try size(frame, [0, 0, 0]).width == 34, "the text")
    #expect(try size(frame, [0, 0, 1]).width == 110, "the picker is on its floor, not the ideal 152")
    expectSegments(frame, [59, 51], "in the stack")
}

/// A press on the third segment of the 380 picker writes its tag: the hitboxes follow the distributed
/// widths, not the natural ones. MA3 (placement at the natural widths) moves the third segment's centre.
@Test @MainActor func pressingTheThirdSegmentOfASqueezedPickerWritesItsTag() throws {
    var writes: [Int] = []
    let binding = Binding<Int>(get: { 1 }, set: { writes.append($0) })
    let (window, platform) = try controlWindow(size: 420) {
        controlRoot(width: 420, height: 420) {
            Picker("Flavor", selection: binding) { threeFlavors() }.pickerStyle(.segmented).frame(width: px(380))
        }
    }
    let hits = options(window.lastHitboxes)
    try #require(hits.count == 3)
    #expect(hits.map { $0.bounds.size.width.value } == [107, 107, 121])
    controlClick(platform, at: controlCentre(hits[2].bounds))
    #expect(writes == [2], "the third segment's tag")
}

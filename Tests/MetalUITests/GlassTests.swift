import Foundation
import Testing
import MetalUICore
import MetalUIDemoContent
import MetalUILayout
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUI

// Liquid Glass, lane C (rulings `LG-A`, `LG-C`, `LG-E`, `LG-F`, `LG-G`, `LG-H`, `LG-I`, `LG-L`, `LG-M`, `LG-U`;
// spec `docs/superpowers/specs/2026-10-23-liquid-glass-design.md` §5, tests 17-36). Headless: the finalized `Scene` of
// one `Frame`; the records' fields are read, never pixels. Each test names its mutation.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func rgba(_ c: MUIHsla) -> Rgba { Hsla(h: c.h, s: c.s, l: c.l, a: c.a).toRgba() }

/// `element` as one frame under `scheme` and Reduce Transparency `reduce`, finalized.
@MainActor private func glassFrame<E: Element>(_ element: E, scheme: ColorScheme = .light, reduce: Bool = false,
                                               side: Float = 400) -> Frame {
    effectFrame(Column {
        Column { element }
            .environment(\.accessibilityReduceTransparency, reduce)
            .environment(\.colorScheme, scheme)
    }, side: side)
}

@MainActor private func glassScene<E: Element>(_ element: E, scheme: ColorScheme = .light, reduce: Bool = false,
                                               side: Float = 400) -> Scene {
    glassFrame(element, scheme: scheme, reduce: reduce, side: side).finalizedScene()
}

/// A 60 x 60 glass circle (a clear leaf, `Circle` glass).
@MainActor private func circle() -> some ProposalElementGroup {
    Color.clear.frame(width: px(60), height: px(60)).glassEffect(in: Circle())
}

/// Three circles `gap` apart in a container of `spacing`.
@MainActor private func three(gap: Float, spacing: Pixels?) -> some Element {
    VStack(spacing: 0) {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: px(gap)) { circle(); circle(); circle() }
        }
    }
}

// MARK: - 17

/// **17** (`LG-I`). A standalone `glassEffect` emits one backdrop record, flagged glass, covering its node's rect and
/// drawn **behind** its content: the scene's draw list runs the backdrop before the content's rect.
/// **Red before:** `glassEffect` does not exist (compile failure). **Mutation:** emit after the content (the draw
/// list reads rect, backdrop).
@Test @MainActor func aGlassEffectEmitsOneBackdropRecordBehindItsContent() throws {
    let scene = glassScene(Color(.accent).frame(width: px(80), height: px(40)).glassEffect())
    try #require(scene.backdrops.count == 1, "one record: \(scene.backdrops.count)")
    let record = scene.backdrops[0]
    #expect(record.isGlass, "flags \(record.glassFlags)")
    #expect(record.bounds.size.width == 80 && record.bounds.size.height == 40, "\(record.bounds)")
    let kinds = scene.drawList.map(\.kind)
    let at = try #require(kinds.firstIndex(of: .backdrop))
    let content = try #require(kinds.firstIndex(of: .rect))
    #expect(at < content, "the glass is behind its content: \(kinds)")
}

// MARK: - 17b

/// **17b** (branch checker, record 153). The lens-and-rim bit and the scheme bit of the record's flags word reach
/// the scene from `fillGlass`: a glass asks for the lens and rim, and the dark bit follows the scheme. Nothing else
/// read the frame-to-record flags: the checker's mutation `lensRim: false` in `fillGlass` passed the 4442-test suite.
/// **Mutation:** `lensRim: false`, or `dark` inverted, in `fillGlass`'s tail.
@Test @MainActor func aGlassRecordCarriesTheLensRimAndSchemeBits() throws {
    func flags(_ scheme: ColorScheme) throws -> UInt32 {
        let scene = glassScene(Color.clear.frame(width: px(80), height: px(40)).glassEffect(), scheme: scheme)
        return try #require(scene.backdrops.first).glassFlags
    }
    // Bits: 2 lens and rim, 4 dark (`GlassReference.lensRimBit`, `darkBit`).
    let light = try flags(.light), dark = try flags(.dark)
    #expect(light & 2 != 0 && dark & 2 != 0, "lens/rim \(light) \(dark)")
    #expect(light & 4 == 0, "light is not dark: \(light)")
    #expect(dark & 4 != 0, "dark is dark: \(dark)")
}

// MARK: - 18

/// **18** (`LG-A`). The default shape is a capsule (radii half the shorter side); `Rectangle()` is square and
/// `Ellipse()` is the ellipse kind (separating arms). **Mutation:** the default radius 0.
@Test @MainActor func theDefaultShapeIsACapsule() throws {
    func record<E: ProposalElementGroup>(_ view: E) throws -> MUIBackdrop {
        let scene = glassScene(VStack(spacing: 0) { view })
        return try #require(scene.backdrops.first)
    }
    let capsule = try record(Color.clear.frame(width: px(80), height: px(40)).glassEffect())
    #expect(capsule.cornerRadii.topLeft == 20 && capsule.cornerRadii.bottomRight == 20, "\(capsule.cornerRadii)")
    #expect(capsule.shape & 0xFF == 0, "a rounded rectangle")
    let square = try record(Color.clear.frame(width: px(80), height: px(40)).glassEffect(in: Rectangle()))
    #expect(square.cornerRadii.topLeft == 0, "\(square.cornerRadii)")
    let round = try record(Color.clear.frame(width: px(60), height: px(40)).glassEffect(in: Ellipse()))
    #expect(round.shape & 0xFF == 1, "the ellipse kind: \(round.shape)")
}

// MARK: - 19

/// **19** (`LG-C`). `.identity` emits nothing: the scene equals the bare tree's. **Mutation:** identity emits a
/// clear glass.
@Test @MainActor func identityEmitsNothingAndEqualsNoModifier() throws {
    func tree(_ glass: Glass?) -> some Element {
        VStack(spacing: 0) {
            if let glass {
                Color(.accent).frame(width: px(80), height: px(40)).glassEffect(glass)
            } else {
                Color(.accent).frame(width: px(80), height: px(40))
            }
        }
    }
    let identity = glassScene(tree(.identity)), bare = glassScene(tree(nil)), regular = glassScene(tree(.regular))
    #expect(identity.backdrops.isEmpty, "\(identity.backdrops.count) records")
    #expect(String(describing: identity.rects) == String(describing: bare.rects))
    #expect(identity.drawList.count == bare.drawList.count)
    #expect(regular.backdrops.count == 1, "the separating arm: regular does emit")
}

// MARK: - 20

/// **20** (`LG-C`, `LG-E`). The record's tint is the fitted table for the four (variant, scheme) pairs, as
/// literals (not through `GlassLook`), and `tint(_:)` composites source-over on the base. **Mutation:** swap the dark
/// clear row with the dark regular one.
@Test @MainActor func regularAndClearAndTintMapToTheFittedTable() throws {
    let table: [(Glass, ColorScheme, Float, Float)] = [
        (.regular, .light, 0.908, 0.60), (.clear, .light, 0.870, 0.32),
        (.clear, .dark, 0.338, 0.29), (.regular, .dark, 0.321, 0.412),
    ]
    for (glass, scheme, grey, alpha) in table {
        let scene = glassScene(VStack(spacing: 0) {
            Color.clear.frame(width: px(60), height: px(30)).glassEffect(glass)
        }, scheme: scheme)
        let tint = rgba(try #require(scene.backdrops.first).tint)
        #expect(abs(tint.r - grey) < 0.003 && abs(tint.g - grey) < 0.003 && abs(tint.b - grey) < 0.003
                && abs(tint.a - alpha) < 0.003, "\(scheme): \(tint) vs grey \(grey) alpha \(alpha)")
        let base = GlassLook.base(glass.variant, scheme: scheme)
        #expect(abs(base.toRgba().a - alpha) < 0.003, "the table agrees with the literal")
    }
    // Source-over: red at 0.3 over regular-light (grey 0.908 at 0.60).
    let tinted = glassScene(VStack(spacing: 0) {
        Color.clear.frame(width: px(60), height: px(30)).glassEffect(.regular.tint(Color(red: 1, green: 0, blue: 0).opacity(0.3)))
    })
    let t = rgba(try #require(tinted.backdrops.first).tint)
    let alpha: Float = 0.3 + 0.60 * 0.7
    let red = (1 * 0.3 + 0.908 * 0.60 * 0.7) / alpha, green = (0 * 0.3 + 0.908 * 0.60 * 0.7) / alpha
    #expect(abs(t.a - alpha) < 0.004 && abs(t.r - red) < 0.006 && abs(t.g - green) < 0.006,
            "source-over: \(t) vs (\(red), \(green), \(green), \(alpha))")
}

// MARK: - 21, 22

private func records(_ scene: Scene) -> [Int] { scene.backdrops.map(\.glassMemberCount) }

/// **21** (`LG-G`). In a container three circles 10 apart merge when `spacing > 2 × gap` (spacing 40: one record of
/// three members) and stay three records at spacing 4. **Mutation:** compare the gap against `spacing / 2` (spacing
/// 40 then merges only below a gap of 20, but the 4 arm and the gap 30 arm below separate it).
@Test @MainActor func aContainerMergesShapesCloserThanItsSpacing() throws {
    let merged = records(glassScene(three(gap: 10, spacing: px(40))))
    #expect(merged == [3], "spacing 40, gap 10: \(merged)")
    let apart = records(glassScene(three(gap: 10, spacing: px(4))))
    #expect(apart == [1, 1, 1], "spacing 4, gap 10: \(apart)")
    // The threshold is `spacing > 2 × gap` (W9, W10): gap 20 merges at 41 and not at 39.
    #expect(records(glassScene(three(gap: 20, spacing: px(41)))) == [3])
    #expect(records(glassScene(three(gap: 20, spacing: px(39)))) == [1, 1, 1])
}

/// **22** (`LG-G`). An unset spacing is 8: a gap of 2 merges, a gap of 6 does not (W15). **Mutation:** `nil` → 0.
@Test @MainActor func anUnsetSpacingIsEight() throws {
    #expect(records(glassScene(three(gap: 2, spacing: nil))) == [3])
    #expect(records(glassScene(three(gap: 6, spacing: nil))) == [1, 1, 1])
}

/// **21b** (`LG-G`). More than four members blob in greedy chunks of four in tree order, never across: five touching
/// circles are records of four and one. **Mutation:** cap 5.
@Test @MainActor func aBlobHoldsFourMembersAndTheFifthStartsAnother() throws {
    let scene = glassScene(VStack(spacing: 0) {
        GlassEffectContainer(spacing: px(40)) {
            HStack(spacing: 4) { circle(); circle(); circle(); circle(); circle() }
        }
    }, side: 600)
    #expect(records(scene) == [4, 1], "\(records(scene))")
}

// MARK: - 23

private struct UnionTree: Component {
    @Namespace var ns
    let gap: Float
    let sameID: Bool
    var content: some ProposalElementGroup {
        GlassEffectContainer {
            HStack(spacing: px(gap)) {
                Color.clear.frame(width: px(60), height: px(60)).glassEffect(in: Circle())
                    .glassEffectUnion(id: "u", namespace: ns)
                Color.clear.frame(width: px(60), height: px(60)).glassEffect(in: Circle())
                    .glassEffectUnion(id: sameID ? "u" : "v", namespace: ns)
            }
        }
    }
}

/// **23** (`LG-H`). A shared union id merges regardless of distance (gap 120, default spacing): one record of two
/// members; different ids at the same gap stay two. **Mutation:** ignore the id.
@Test @MainActor func aUnionIdMergesRegardlessOfDistance() throws {
    let joined = records(glassScene(VStack(spacing: 0) { UnionTree(gap: 120, sameID: true) }, side: 600))
    #expect(joined == [2], "\(joined)")
    let split = records(glassScene(VStack(spacing: 0) { UnionTree(gap: 120, sameID: false) }, side: 600))
    #expect(split == [1, 1], "\(split)")
}

// MARK: - 24

/// **24** (`LG-I`, divergence 826). A container emits its blobs before its content and its members emit nothing:
/// two members around a plain sibling make ONE record (the sibling is under the blob) and the draw list runs the
/// backdrop before the sibling's rect. **Mutation:** members also emit (three records).
@Test @MainActor func aContainerEmitsBeforeItsContentAndItsMembersEmitNothing() throws {
    let scene = glassScene(VStack(spacing: 0) {
        GlassEffectContainer(spacing: px(60)) {
            HStack(spacing: 4) {
                circle()
                Color(.accent).frame(width: px(20), height: px(20))
                circle()
            }
        }
    })
    #expect(scene.backdrops.count == 1, "one blob: \(records(scene))")
    let kinds = scene.drawList.map(\.kind)
    let backdrop = try #require(kinds.firstIndex(of: .backdrop))
    let rect = try #require(kinds.firstIndex(of: .rect))
    #expect(backdrop < rect, "the sibling is above the blob: \(kinds)")
}

// MARK: - 27, 29, 28

private struct Wedge: Shape, Equatable {
    func path(in rect: Bounds<Pixels>) -> Path {
        var p = Path()
        p.move(to: Point(x: Pixels(0), y: Pixels(0)))
        p.addLine(to: Point(x: rect.size.width, y: Pixels(0)))
        p.addLine(to: Point(x: Pixels(0), y: rect.size.height))
        p.closeSubpath()
        return p
    }
}

/// **27** (`LG-L`, divergence 829). A `Path` shape draws the variant's flat tint as that path's own fill: no backdrop
/// record, no rect, one image (the path's raster). **Mutation:** a rect fill.
@Test @MainActor func aPathShapeDrawsItsFlatTintAsAPathFill() throws {
    let scene = glassScene(VStack(spacing: 0) {
        Color.clear.frame(width: px(60), height: px(40)).glassEffect(in: Wedge())
    })
    #expect(scene.backdrops.isEmpty, "no backdrop for a path")
    #expect(scene.rects.filter { $0.background.a > 0 }.isEmpty, "not a rect fill: \(scene.rects.count)")
    #expect(scene.images.count == 1, "one path raster: \(scene.images.count)")
}

/// **29** (`LG-L`, `BB-H`'s arm). A glass inside a CPU-rasterized shadow degrades to its flat tint: no backdrop
/// record, a rect of the tint at its alpha; a blob degrades to one rect per member. **Mutation:** skip the arm (the
/// record reaches the scene).
@Test @MainActor func aGlassInsideACPURasterisedShadowDegradesToItsFlatTint() throws {
    let single = glassScene(VStack(spacing: 0) {
        Color.clear.frame(width: px(60), height: px(30)).glassEffect().shadow(radius: px(4))
    })
    #expect(single.backdrops.isEmpty, "no record inside a shadow")
    #expect(single.rects.contains { abs($0.background.a - 0.60) < 0.01 && $0.bounds.size.width == 60 },
            "the flat tint rect: \(single.rects.map { $0.background.a })")
    let blob = glassScene(VStack(spacing: 0) {
        GlassEffectContainer(spacing: px(40)) {
            HStack(spacing: 10) { circle(); circle(); circle() }
        }.shadow(radius: px(4))
    })
    #expect(blob.backdrops.isEmpty, "no blob record inside a shadow")
    let flat = blob.rects.filter { abs($0.background.a - 0.60) < 0.01 && abs($0.bounds.size.width - 60) < 0.01 }
    #expect(flat.count == 3, "one flat rect per member: \(flat.count)")
}

/// **28** (`LG-F`). Reduce Transparency draws the opaque grey as a rect with no backdrop record, standalone and as a
/// container member (one rect per member, no merge); off, the record returns. **Mutation:** ignore the environment.
@Test @MainActor func reduceTransparencyDrawsTheOpaqueGreyWithNoBackdropRecord() throws {
    let tree = VStack(spacing: 0) {
        Color.clear.frame(width: px(60), height: px(30)).glassEffect()
        GlassEffectContainer(spacing: px(40)) {
            HStack(spacing: 10) { circle(); circle() }
        }
    }
    let on = glassScene(tree, reduce: true), off = glassScene(tree)
    #expect(on.backdrops.isEmpty, "opaque under Reduce Transparency: \(on.backdrops.count)")
    #expect(off.backdrops.count == 2, "the separating arm: \(off.backdrops.count)")
    let grey = on.rects.filter { $0.background.a > 0.999 && $0.bounds.size.width == 60 }
    #expect(grey.count == 3, "three opaque panels: \(grey.count)")
    for rect in grey {
        let c = rgba(rect.background)
        #expect(abs(c.r - 0.908) < 0.01, "regular-light grey: \(c)")
    }
}

// MARK: - 31

/// **31** (`LG-J`, `OM-AK`). A bare `.glassEffect(.regular.interactive())` registers no hitbox: the hitbox count equals
/// the bare tree's. **Mutation:** register one.
@Test @MainActor func aBareInteractiveGlassRegistersNoHitbox() throws {
    func count<E: ProposalElementGroup>(_ view: E) -> Int {
        glassFrame(VStack(spacing: 0) { view }).hitboxes.count
    }
    let bare = count(Color.clear.frame(width: px(60), height: px(30)))
    let glass = count(Color.clear.frame(width: px(60), height: px(30)).glassEffect(.regular.interactive()))
    #expect(glass == bare, "\(glass) vs \(bare)")
    let button = glassFrame(VStack(spacing: 0) { Button("Go") {}.buttonStyle(.glass) }).hitboxes.count
    #expect(button >= 1, "the separating arm: a button registers its own")
}

// MARK: - 32

/// **32** (`LG-M`). The glass styles are not bordered; a glass button is a capsule glass, one backdrop record, and a
/// prominent one is tinted. **Mutation:** `isBordered` true for `.glass`.
@Test @MainActor func glassButtonStylesAreNotBordered() throws {
    #expect(!ButtonStyle.glass.isBordered && !ButtonStyle.glassProminent.isBordered)
    #expect(ButtonStyle.bordered.isBordered, "the separating arm")
    let scene = glassScene(VStack(spacing: 0) {
        Button("Go") {}.buttonStyle(.glass)
        Button("Done") {}.buttonStyle(.glassProminent)
    })
    try #require(scene.backdrops.count == 2, "one record each: \(scene.backdrops.count)")
    let plain = rgba(scene.backdrops[0].tint), prominent = rgba(scene.backdrops[1].tint)
    #expect(abs(plain.r - plain.b) < 0.003, "the plain glass is a grey: \(plain)")
    #expect(prominent.b - prominent.r > 0.05 || abs(prominent.r - prominent.b) > 0.05, "the prominent tint is the accent: \(prominent)")
    let radius = scene.backdrops[0].cornerRadii.topLeft
    #expect(radius > 0 && abs(scene.backdrops[0].bounds.size.height - 2 * radius) < 0.5, "a capsule: radius \(radius) of \(scene.backdrops[0].bounds)")
    #expect(scene.rects.filter { $0.borderWidths.top > 0 }.isEmpty, "no border")
}

// MARK: - 34

/// **34** (`LG-K`). `glassEffectTransition(.materialize)` is the opacity transition: half way in, the record's opacity
/// is about half; `.identity` snaps (full at once). **Mutation:** `.identity` fades.
@Test @MainActor func glassEffectTransitionMaterializeFadesInAndOut() throws {
    func stage(_ shown: Bool, _ transition: GlassEffectTransition) -> some Element {
        Column {
            Stack {
                Box().frame(width: px(200), height: px(100))
                if shown {
                    Color.clear.frame(width: px(60), height: px(30)).glassEffect().glassEffectTransition(transition)
                }
            }
        }
    }
    func opacities(_ transition: GlassEffectTransition) -> [Float] {
        let h = TransitionHarness()
        let animation = Animation.linear(duration: 1)
        h.frame(0, nil, stage(false, transition))
        return [0.0, 0.5, 1.0].map { t in
            let scene = h.frame(t, animation, stage(true, transition)).finalizedScene()
            return scene.backdrops.first?.opacity ?? -1
        }
    }
    let fade = opacities(.materialize)
    #expect(fade[0] < 0.2 && abs(fade[1] - 0.5) < 0.15 && fade[2] > 0.95, "materialize fades in: \(fade)")
    let snap = opacities(.identity)
    #expect(snap.allSatisfy { $0 > 0.99 }, "identity snaps: \(snap)")
}

// MARK: - 36

/// **36** (`MT-I`'s scan, for glass). No source file passes a glass tail to `fillBackdrop(` outside
/// `MaterialTransparency.swift`: every glass site goes through `fillGlass`, which reads Reduce Transparency.
/// **Mutation:** a second glass-tailed `fillBackdrop(` call in another file.
@Test func everyGlassEmissionSiteGoesThroughFillGlass() throws {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/MetalUI")
    let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
    try #require(files.count > 100 && files.contains("MaterialTransparency.swift"),
                 "the scan reads the real source directory: \(files.count) files")
    var offenders: [String] = []
    var homeCalls = 0
    for file in files {
        let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
        for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let code = line.drop { $0 == " " }
            if code.hasPrefix("//") { continue }
            guard code.contains("fillBackdrop(") && code.contains("glassTail:") else { continue }
            if file == "MaterialTransparency.swift" { homeCalls += 1 } else { offenders.append("\(file):\(number + 1) \(code)") }
        }
    }
    #expect(offenders.isEmpty, "glass tails outside fillGlass's home: \(offenders)")
    #expect(homeCalls >= 1, "the scan sees the real call (an unreadable scan passes nothing)")
}

// MARK: - 37

/// **37** (`LG-P`, `LG-V`; human checks LG1-LG6). The Liquid Glass demo draws what those checks name: four standalone
/// capsules, the two glass buttons (each one record) and the container's three circles as ONE blob of three members
/// (spacing 40 over a gap of 14); and it holds exactly the four buttons it declares, which is why it is a root of its
/// own and not a section of the looks demo (whose pins count its clickable hitboxes). **Mutation:** the container
/// spacing 4 (the blob falls apart into three records).
@Test @MainActor func theLiquidGlassDemoDrawsEveryLookItsHumanChecksName() throws {
    let frame = effectFrame(liquidGlassDemoContent(), side: 720)
    let scene = frame.finalizedScene()
    let members = scene.backdrops.map(\.glassMemberCount).sorted()
    #expect(members == [1, 1, 1, 1, 1, 1, 3], "four capsules, two buttons, one blob of three: \(members)")
    #expect(scene.backdrops.allSatisfy { $0.isGlass }, "every record is a glass")
    #expect(frame.hitboxes.filter { $0.handlers.onClick != nil }.count == 4, "the two glass buttons and the spacing pair")
}

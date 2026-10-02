import MetalUI

/// The looks demo (plan task 15, the closeout; `CX-M` item 1), reached with
/// `METALUI_LOOKS_DEMO=1 swift run MetalUIDemo`. It is the runnable surface for
/// the human checks no other demo tree builds — `docs/verification/human-checks.md`
/// items **H1** (`controlSize`'s drawn font), **I1** (shapes, strokes, a rounded
/// clip, images and their interpolation), **J1** (gestures on a trackpad),
/// **K1–K3** (transitions, Reduce Motion's cross-fade, `.scale`'s mid-flight
/// glyphs) and, since paths, shadows and transforms, **Q1–Q6** (paths, strokes
/// and dashes, shadows, rotated and scaled content). It asserts nothing; a
/// human looks.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Every section is its own function, passed as
/// an argument to the generic `looksRoot`, as `demoContent()` is spelt (the 1 MB
/// Windows stack budget, record §50 §14); built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func looksDemoContent() -> some Element {
    looksRoot(text: looksTextSection(),
              shapes: looksShapesSection(),
              gestures: looksGesturesSection(),
              transitions: looksTransitionsSection(),
              pathsShadowsTransforms: looksPathsShadowsTransformsSection())
}

@MainActor
private func looksRoot(text: some Element, shapes: some Element,
                       gestures: some Element, transitions: some Element,
                       pathsShadowsTransforms: some Element) -> some Element {
    Column(gap: Pixels(18)) {
        Text("Looks — human checks H1, I1, J1, K1–K3, Q1–Q6").font(size: 20)
        Row(gap: Pixels(32)) {
            Column(gap: Pixels(18)) {
                text
                shapes
                pathsShadowsTransforms
            }
            .alignItems(.flexStart)
            Column(gap: Pixels(18)) {
                gestures
                transitions
            }
            .alignItems(.flexStart)
        }
        .alignItems(.flexStart)
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .background(.surface)
}

// MARK: - H1: controlSize's drawn font

/// **H1.** Three texts with no font of their own, under `.controlSize(.mini)`,
/// `.small` and `.regular`: drawn at 9, 11 and 13 pt (`TE-F`).
@MainActor
private func looksTextSection() -> some Element {
    Column(gap: Pixels(6)) {
        Text("H1 · controlSize").font(size: 15)
        Text("mini — 9 pt").controlSize(.mini)
        Text("small — 11 pt").controlSize(.small)
        Text("regular — 13 pt").controlSize(.regular)
    }
    .alignItems(.flexStart)
}

// MARK: - I1: shapes, strokes, a rounded clip, images

/// A 4 × 4 checkerboard of the accent-ish blue and white: magnified, nearest
/// sampling shows hard squares and bilinear sampling a blur between them.
private let looksChecker: ImageBitmap = {
    var rgba: [UInt8] = []
    for y in 0..<4 {
        for x in 0..<4 {
            rgba += (x + y) % 2 == 0 ? [40, 110, 230, 255] : [255, 255, 255, 255]
        }
    }
    return ImageBitmap(width: 4, height: 4, rgba: rgba)
}()

/// A 2 : 1 bitmap (16 × 8, a horizontal gradient) for `.fit` and `.fill` in a
/// square frame.
private let looksWide: ImageBitmap = {
    var rgba: [UInt8] = []
    for _ in 0..<8 {
        for x in 0..<16 {
            let v = UInt8(40 + x * 13)
            rgba += [v, 80, 255 - v, 255]
        }
    }
    return ImageBitmap(width: 16, height: 8, rgba: rgba)
}()

/// **I1.** An ellipse fill, an ellipse stroke band, a capsule, a rounded clip
/// over a larger rectangle, a resizable image in `.fit` and `.fill`, and the
/// checkerboard at `.interpolation(.none)` beside the default (bilinear).
@MainActor
private func looksShapesSection() -> some Element {
    Column(gap: Pixels(8)) {
        Text("I1 · shapes, clip, images").font(size: 15)
        Row(gap: Pixels(12)) {
            Ellipse().fill(.accent).frame(width: Pixels(80), height: Pixels(48))
            Ellipse().stroke(.accent, lineWidth: Pixels(6)).frame(width: Pixels(80), height: Pixels(48))
            Capsule().fill(.separator).frame(width: Pixels(90), height: Pixels(32))
            Rectangle().fill(.accent).frame(width: Pixels(120), height: Pixels(120))
                .frame(width: Pixels(64), height: Pixels(64))
                .clipShape(RoundedRectangle(cornerRadius: Pixels(16)))
        }
        Text("image .fit, .fill (64 × 64); checker .none, default (64 × 64)")
        Row(gap: Pixels(12)) {
            Image(decorative: looksWide, scale: 1).resizable().scaledToFit()
                .frame(width: Pixels(64), height: Pixels(64))
            Image(decorative: looksWide, scale: 1).resizable().scaledToFill()
                .frame(width: Pixels(64), height: Pixels(64))
            Image(decorative: looksChecker, scale: 1).resizable().interpolation(.none)
                .frame(width: Pixels(64), height: Pixels(64))
            Image(decorative: looksChecker, scale: 1).resizable()
                .frame(width: Pixels(64), height: Pixels(64))
        }
    }
    .alignItems(.flexStart)
}

// MARK: - J1: gestures

/// **J1.** Three pads: a double tap, a long press (0.5 s) and a drag, each
/// counting what it recognised.
@MainActor
private func looksGesturesSection() -> some Element {
    Column(gap: Pixels(8)) {
        Text("J1 · gestures (trackpad)").font(size: 15)
        LooksGestures()
    }
    .alignItems(.flexStart)
}

struct LooksGestures: Component {
    @State var doubleTaps = 0
    @State var longPresses = 0
    @State var drags = 0
    @State var lastDrag = "none"

    var content: some ElementGroup {
        Row(gap: Pixels(12)) {
            Box().frame(width: Pixels(110), height: Pixels(60)).background(.surfaceSecondary)
                .onTapGesture(count: 2) { doubleTaps += 1 }
            Box().frame(width: Pixels(110), height: Pixels(60)).background(.surfaceSecondary)
                .onLongPressGesture { longPresses += 1 }
            Box().frame(width: Pixels(110), height: Pixels(60)).background(.surfaceSecondary)
                .gesture(DragGesture().onEnded { value in
                    drags += 1
                    lastDrag = "\(Int(value.translation.width.value)), \(Int(value.translation.height.value))"
                })
        }
        Text("double taps \(doubleTaps) · long presses \(longPresses) · drags \(drags) (last \(lastDrag))")
    }
}

// MARK: - K1–K3: transitions

/// **K1–K3.** One button per transition toggles a tile in and out under
/// `withAnimation(.easeInOut(duration: 0.8))`; the `.scale` tile carries text,
/// for K3's soft mid-flight glyphs. Turn System Settings → Accessibility →
/// Display → Reduce motion on for K2: every one but `.identity` cross-fades.
@MainActor
private func looksTransitionsSection() -> some Element {
    Column(gap: Pixels(8)) {
        Text("K1–K3 · transitions (Reduce motion: K2)").font(size: 15)
        LooksTransitions()
    }
    .alignItems(.flexStart)
}

/// The transitions K1 lists, in its order, each with its button's title.
private let looksTransitionKinds: [(String, AnyTransition)] = [
    ("opacity", .opacity),
    ("move(edge: .top)", .move(edge: .top)),
    ("scale", .scale),
    ("slide", .slide),
    ("offset(x: 60)", .offset(x: Pixels(60))),
    ("push(from: .leading)", .push(from: .leading)),
    ("asymmetric(scale, opacity)", .asymmetric(insertion: .scale, removal: .opacity)),
    ("opacity.combined(with: .move(edge: .bottom))", .opacity.combined(with: .move(edge: .bottom))),
    ("identity", .identity),
]

struct LooksTransitions: Component {
    /// Which transitions' tiles are shown, by index into `looksTransitionKinds`.
    @State var shown: Set<Int> = []

    var content: some ElementGroup {
        ForEach(Array(looksTransitionKinds.indices), id: \.self) { index in
            LooksTransitionRow(index: index, shown: $shown)
        }
    }
}

/// One transition's button and its stage: a 160 × 36 well holding the tile
/// while it is shown.
struct LooksTransitionRow: Component {
    let index: Int
    @Binding var shown: Set<Int>

    var content: some ElementGroup {
        Row(gap: Pixels(10)) {
            Button(looksTransitionKinds[index].0) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    if shown.contains(index) { shown.remove(index) } else { shown.insert(index) }
                }
            }
            Stack {
                Box().frame(width: Pixels(160), height: Pixels(36)).background(.surfaceSecondary)
                if shown.contains(index) {
                    Box {
                        Text("Aa scale me").font(size: 14)
                    }
                    .frame(width: Pixels(120), height: Pixels(28))
                    .background(.accent)
                    .transition(looksTransitionKinds[index].1)
                }
            }
        }
    }
}

// MARK: - Q1–Q6: paths, shadows and transforms

/// A five-point star through the points of a pentagram — every edge crosses
/// two others, so nonzero fills the centre and even-odd leaves it empty (Q1).
private func looksStar(side: Double) -> Path {
    Path { path in
        let c = side / 2, r = side / 2
        // The five outer points, every second one, as a pentagram is drawn.
        let unit: [(Double, Double)] = [(0, -1), (0.5878, 0.809), (-0.9511, -0.309), (0.9511, -0.309),
                                        (-0.5878, 0.809)]
        path.move(to: Point(x: Pixels(Float(c + r * unit[0].0)), y: Pixels(Float(c + r * unit[0].1))))
        for p in unit.dropFirst() {
            path.addLine(to: Point(x: Pixels(Float(c + r * p.0)), y: Pixels(Float(c + r * p.1))))
        }
        path.closeSubpath()
    }
}

/// A zig-zag polyline, 120 wide (Q2).
private let looksZigZag = Path { path in
    path.move(to: Point(x: Pixels(6), y: Pixels(34)))
    for i in 1...6 {
        path.addLine(to: Point(x: Pixels(Float(6 + 18 * i)), y: Pixels(i % 2 == 0 ? 34 : 8)))
    }
}

/// **Q1–Q6.** The star filled nonzero and even-odd (Q1); the zig-zag stroked
/// width 6 with round caps and joins, and dashed `[12, 6]` (Q2); a card and a
/// text with shadows (Q3); a text turned 30° and an image turned −15° (Q4); a
/// path star and a text each under `scaleEffect(3)` — the star crisp, the text
/// soft (divergence 106, Q5); and a square that turns 45° more on each tap,
/// animated, its hover and tap region following the drawn diamond (Q6).
@MainActor
private func looksPathsShadowsTransformsSection() -> some Element {
    Column(gap: Pixels(10)) {
        Text("Q1–Q6 · paths, shadows, transforms").font(size: 15)
        Row(gap: Pixels(16)) {
            looksStar(side: 64).fill(.accent).frame(width: Pixels(64), height: Pixels(64))
            looksStar(side: 64).fill(.accent, style: FillStyle(eoFill: true))
                .frame(width: Pixels(64), height: Pixels(64))
            looksZigZag.stroke(.accent, style: StrokeStyle(lineWidth: Pixels(6), lineCap: .round, lineJoin: .round))
                .frame(width: Pixels(120), height: Pixels(42))
            looksZigZag.stroke(.accent, style: StrokeStyle(lineWidth: Pixels(6), dash: [Pixels(12), Pixels(6)]))
                .frame(width: Pixels(120), height: Pixels(42))
        }
        Row(gap: Pixels(24)) {
            Box {
                Text("A card with a shadow")
            }
            .padding(Pixels(12))
            .background(.surface)
            .cornerRadius(Pixels(10))
            .shadow(radius: Pixels(8), y: Pixels(4))
            Text("A shadowed text").font(size: 18).shadow(radius: Pixels(2), x: Pixels(1), y: Pixels(2))
        }
        Row(gap: Pixels(32)) {
            Text("Rotated").font(size: 18).rotationEffect(.degrees(30))
            Image(decorative: looksChecker, scale: 1).resizable().interpolation(.none)
                .frame(width: Pixels(48), height: Pixels(48))
                .rotationEffect(.degrees(-15))
            looksStar(side: 16).fill(.accent).frame(width: Pixels(16), height: Pixels(16)).scaleEffect(3)
                .frame(width: Pixels(56), height: Pixels(56))
            Text("Aa").font(size: 12).scaleEffect(3).frame(width: Pixels(56), height: Pixels(56))
            LooksRotatingSquare()
        }
    }
    .alignItems(.flexStart)
}

/// **Q6.** A 60 × 60 square that turns 45° more on each tap, under
/// `withAnimation(.easeInOut(duration: 0.6))`; it brightens while hovered, and
/// both the hover and the tap region follow the drawn diamond.
struct LooksRotatingSquare: Component {
    @State var turns = 0

    var content: some ElementGroup {
        Box()
            .frame(width: Pixels(60), height: Pixels(60))
            .background(.accent)
            .hoverBackground(.separator)
            .rotationEffect(.degrees(Double(turns) * 45))
            .onTapGesture { withAnimation(.easeInOut(duration: 0.6)) { turns += 1 } }
    }
}

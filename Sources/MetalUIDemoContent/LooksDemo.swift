import MetalUI

/// The looks demo (plan task 15, the closeout; `CX-M` item 1), reached with
/// `METALUI_LOOKS_DEMO=1 swift run MetalUIDemo`. It is the runnable surface for
/// the human checks no other demo tree builds — `docs/verification/human-checks.md`
/// items **H1** (`controlSize`'s drawn font), **I1** (shapes, strokes, a rounded
/// clip, images and their interpolation), **J1** (gestures on a trackpad),
/// **K1–K3** (transitions, Reduce Motion's cross-fade, `.scale`'s mid-flight
/// glyphs) and, since paths, shadows and transforms, **Q1–Q6** (paths, strokes
/// and dashes, shadows, rotated and scaled content) and, since colour and colour
/// scheme, **S1–S3** (literal, dynamic and palette colours, live appearance
/// switching, the scheme toggle) and, since lifecycle modifiers, **T1–T2**
/// (`onAppear`/`onDisappear` counters, a disappearance that waits for its fade,
/// an `onChange` counter). It asserts nothing; a human looks.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Every section is its own function, passed as
/// an argument to the generic `looksRoot`, as `demoContent()` is spelt (the 1 MB
/// Windows stack budget, record §50 §14); built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`. **The composition is split
/// too** (ruling `RT-U`): `looksRoot`, `looksColumns`, `looksLeftColumn` and
/// `looksRightColumn` each hold only their own children. Composed in one
/// `looksRoot` (title, a row of two columns, colour), this tree alone needed
/// 848 KB of stack on Windows ARM64 at `5d6893a` and 912 KB once rich text made
/// every `Text` 16 bytes larger, which overflowed the 1 MB harness on Windows
/// (`0xC00000FD`/`0xC0000005`); split, 528 KB (macOS arm64: 864 → 880 → 560 KB).
@MainActor
public func looksDemoContent() -> some Element {
    looksRoot(columns: looksColumns(left: looksLeftColumn(text: looksBesideH1(text: looksTextSection(),
                                                                              lifecycle: looksLifecycleSection()),
                                                          shapes: looksShapesSection(),
                                                          pathsShadowsTransforms: looksPathsShadowsTransformsSection()),
                                    right: looksRightColumn(gestures: looksGesturesSection(),
                                                            transitions: looksTransitionsAndLooks())),
              colour: looksColourAndKeyframes())
}

/// H1's narrow column and, beside it where the left column has room, the
/// lifecycle section (T1–T2), so the window's height does not grow. Its own
/// function, as every composition here is (the 1 MB stack budget,
/// `everyProductionTreeBuildsOnAOneMegabyteThread`: composed inline in
/// `looksRoot` it overflowed a 1 MB thread in a debug build — `LC-T`).
@MainActor
private func looksBesideH1(text: some Element, lifecycle: some ElementGroup) -> some Element {
    Row(gap: Pixels(32)) {
        text
        lifecycle
    }
    .alignItems(.flexStart)
}

/// The title, the two columns and the colour section under them.
@MainActor
private func looksRoot(columns: some Element, colour: some Element) -> some Element {
    Column(gap: Pixels(18)) {
        Text("Looks — human checks H1, I1, J1, K1–K3, Q1–Q6, S1–S3, T1–T2").font(size: 20)
        columns
        colour
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .background(.surface)
}

/// The left and right columns side by side.
@MainActor
private func looksColumns(left: some Element, right: some Element) -> some Element {
    Row(gap: Pixels(32)) {
        left
        right
    }
    .alignItems(.flexStart)
}

/// H1 with the lifecycle section, I1 and Q1–Q6, top to bottom.
@MainActor
private func looksLeftColumn(text: some Element, shapes: some Element,
                             pathsShadowsTransforms: some Element) -> some Element {
    Column(gap: Pixels(18)) {
        text
        shapes
        pathsShadowsTransforms
    }
    .alignItems(.flexStart)
}

/// J1 over K1–K3.
@MainActor
private func looksRightColumn(gestures: some Element, transitions: some Element) -> some Element {
    Column(gap: Pixels(18)) {
        gestures
        transitions
    }
    .alignItems(.flexStart)
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

// MARK: - S1–S3: colour and colour scheme

/// The looks demo's app palette key (ruling `CR-N`): a purple that follows
/// light and dark through the window's theme. `MetalUIDemo` overrides its dark
/// value with ``looksBrandDarkOverride`` when `METALUI_LOOKS_DEMO=1`, so the
/// palette swatch shows a theme override, not the key's default (human check
/// S1).
public enum LooksBrand: ThemeColorKey {
    /// A purple: `(0.55, 0.25, 0.85)` light, `(0.70, 0.45, 0.95)` dark.
    public static var defaultValue: Color {
        Color(light: Color(red: 0.55, green: 0.25, blue: 0.85),
              dark: Color(red: 0.70, green: 0.45, blue: 0.95))
    }
}

/// The demo's override of ``LooksBrand`` in the dark theme variant — a green
/// unlike the key's dark default — set by `MetalUIDemo` with
/// `app.darkTheme[LooksBrand.self] = looksBrandDarkOverride`.
public let looksBrandDarkOverride = Color(red: 0.30, green: 0.85, blue: 0.70)

/// The 22 swatches in order (spec §7 item 1): SwiftUI's thirteen hues, the
/// three fixed colours, the three semantic statics, a fixed literal, a
/// `Color(light:dark:)` and the palette colour.
private let looksColourSwatches: [(String, Color)] = [
    ("gray", .gray), ("red", .red), ("orange", .orange), ("yellow", .yellow),
    ("green", .green), ("mint", .mint), ("teal", .teal), ("cyan", .cyan),
    ("blue", .blue), ("indigo", .indigo), ("purple", .purple),
    ("pink", .pink), ("brown", .brown), ("black", .black), ("white", .white),
    ("clear", .clear), ("primary", .primary), ("secondary", .secondary),
    ("accentColor", .accentColor),
    ("literal", Color(red: 0.2, green: 0.4, blue: 0.6)),
    ("light/dark", Color(light: Color(red: 0.95, green: 0.75, blue: 0.20),
                         dark: Color(red: 0.20, green: 0.30, blue: 0.75))),
    ("LooksBrand", Color(LooksBrand.self)),
]

/// **S1–S3.** Every swatch is a 28 × 28 `Color` view over a `.separator`
/// border (so `white` and `clear` show), labelled in `.secondary`; a label
/// that reads `@Environment(\.colorScheme)` while building; and a button
/// cycling System → Light → Dark through `.preferredColorScheme`, which is
/// window-wide (`CR-L`): the whole window, title bar included, follows it.
@MainActor
private func looksColourSection() -> some Element {
    Column(gap: Pixels(8)) {
        Text("S1–S3 · colour and colour scheme").font(size: 15)
        LooksColourSection()
    }
    .alignItems(.flexStart)
}

/// The colour section's state: the scheme the toggle prefers (`nil` =
/// System, the window's own appearance).
struct LooksColourSection: Component {
    @State var choice: ColorScheme? = nil

    private var choiceName: String {
        switch choice {
        case nil: "System"
        case .light?: "Light"
        case .dark?: "Dark"
        }
    }

    var content: some ElementGroup {
        Column(gap: Pixels(8)) {
            Row(gap: Pixels(4)) {
                ForEach(Array(0..<11), id: \.self) { index in LooksSwatch(index: index) }
            }
            Row(gap: Pixels(4)) {
                ForEach(Array(11..<looksColourSwatches.count), id: \.self) { index in LooksSwatch(index: index) }
            }
            Row(gap: Pixels(16)) {
                LooksSchemeLabel()
                Button("Appearance: \(choiceName)") {
                    switch choice {
                    case nil: choice = .light
                    case .light?: choice = .dark
                    case .dark?: choice = nil
                    }
                }
            }
        }
        .alignItems(.flexStart)
        .preferredColorScheme(choice)
    }
}

/// One swatch and its label, 92 wide so the two rows line up.
struct LooksSwatch: Component {
    let index: Int

    var content: some ElementGroup {
        Column(gap: Pixels(3)) {
            looksColourSwatches[index].1
                .frame(width: Pixels(28), height: Pixels(28))
                .border(.separator, width: Pixels(1))
            Text(looksColourSwatches[index].0).font(size: 11).foregroundColor(.secondary)
        }
        .frame(width: Pixels(92))
    }
}

/// Prints the scheme it read while building — `scheme: light` or
/// `scheme: dark` (human check S2).
struct LooksSchemeLabel: Component {
    @Environment(\.colorScheme) var scheme

    var content: some ElementGroup {
        Text(scheme == .dark ? "scheme: dark" : "scheme: light")
    }
}

// MARK: - T1–T2: lifecycle modifiers

/// **T1–T2** (ruling `LC-N`). Two buttons insert and remove a tile — the
/// plain one at once, the fading one under `withAnimation(.easeInOut(duration:
/// 0.8))` with `.transition(.opacity)` — and a stepper whose value an
/// `onChange` watches. Each counter is drawn as text and as a bar 8 points per
/// count, 6 tall, in its own colour, so a test reads it from the scene
/// (`theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges`). T1:
/// the "faded" counter moves when the fade ends, not on the click (`LC-H`).
///
/// The section is the component alone, its title inside its body: the looks
/// tree is built whole on a 1 MB thread, and a `Column` and `Text` here
/// overflowed it in a `swift:6.4-noble` debug build (`LC-T`).
@MainActor
private func looksLifecycleSection() -> some ElementGroup {
    LooksLifecycle()
}

/// The four counters' bar colours, in the section's order.
private let looksLifecycleBarColours: [Color] = [
    Color(red: 0.20, green: 0.65, blue: 0.35),  // appeared
    Color(red: 0.85, green: 0.30, blue: 0.25),  // disappeared
    Color(red: 0.90, green: 0.60, blue: 0.15),  // faded
    Color(red: 0.25, green: 0.45, blue: 0.85),  // changes
]

/// The section's state. The counters are written by the lifecycle actions,
/// which run after the frame under the element's dispatch (`LC-E`), so the
/// writes are legal and draw the next frame.
struct LooksLifecycle: Component {
    @State var appeared = 0
    @State var disappeared = 0
    @State var faded = 0
    @State var changes = 0
    @State var shown = false
    @State var fadingShown = false
    @State var value = 0

    var content: some ElementGroup {
        Column(gap: Pixels(6)) {
            Text("T1–T2 · onAppear, onDisappear, onChange").font(size: 15)
            Row(gap: Pixels(8)) {
                Button("Toggle tile") { shown.toggle() }
                Button("Toggle fading tile") {
                    withAnimation(.easeInOut(duration: 0.8)) { fadingShown.toggle() }
                }
                Stepper("Value \(value)", value: $value, in: 0...99)
                    .onChange(of: value) { changes += 1 }
            }
            Row(gap: Pixels(8)) {
                Stack {
                    Box().frame(width: Pixels(120), height: Pixels(28)).background(.surfaceSecondary)
                    if shown {
                        Box { Text("tile").font(size: 13) }
                            .frame(width: Pixels(120), height: Pixels(28))
                            .background(.accent)
                            .onAppear { appeared += 1 }
                            .onDisappear { disappeared += 1 }
                    }
                }
                Stack {
                    Box().frame(width: Pixels(120), height: Pixels(28)).background(.surfaceSecondary)
                    if fadingShown {
                        Box { Text("fading tile").font(size: 13) }
                            .frame(width: Pixels(120), height: Pixels(28))
                            .background(.accent)
                            .transition(.opacity)
                            .onDisappear { faded += 1 }
                    }
                }
            }
            Row(gap: Pixels(16)) {
                Column(gap: Pixels(3)) {
                    LooksLifecycleCounter(label: "appeared", count: appeared, colour: looksLifecycleBarColours[0])
                    LooksLifecycleCounter(label: "disappeared", count: disappeared,
                                          colour: looksLifecycleBarColours[1])
                }
                .alignItems(.flexStart)
                Column(gap: Pixels(3)) {
                    LooksLifecycleCounter(label: "faded", count: faded, colour: looksLifecycleBarColours[2])
                    LooksLifecycleCounter(label: "changes", count: changes, colour: looksLifecycleBarColours[3])
                }
                .alignItems(.flexStart)
            }
            .alignItems(.flexStart)
        }
        .alignItems(.flexStart)
    }
}

/// One counter: its label and count, then a bar `8 × count` points wide.
struct LooksLifecycleCounter: Component {
    let label: String
    let count: Int
    let colour: Color

    var content: some ElementGroup {
        Row(gap: Pixels(8)) {
            Text("\(label) \(count)").font(size: 12).frame(width: Pixels(84))
            colour.frame(width: Pixels(Float(8 * count)), height: Pixels(6))
        }
    }
}

/// The keyframes row, then the colour section (C10 lane 2): composed in **its
/// own frame**, so `looksDemoContent()`'s frame holds one temporary for both —
/// passed in as three it overflowed the 1 MB thread
/// (`everyProductionTreeBuildsOnAOneMegabyteThread`, `.signal(SIGBUS)`, `LK-V`).
@MainActor
private func looksColourAndKeyframes() -> some Element {
    Column(gap: Pixels(18)) {
        keyframesSection()
        looksColourSection()
    }
    .alignItems(.flexStart)
}

/// The keyframes row (C10 lane 2, rulings `LK-H`, `LK-I`, `LK-M`; spec §6): a
/// "Shake" tap target shaking a box with MetalCreator's refused-wire keyframes
/// (M5-i), and a box bobbing on a repeating cubic track. **Its own function**,
/// its state in its own `Component`. Human check: the shake at 60 and 120 Hz
/// (spec §7 item 9).
@MainActor
func keyframesSection() -> some Element {
    Column(gap: Pixels(12)) {
        Text("Keyframes").font(size: 20)
        KeyframesDemo()
    }
    .alignItems(.flexStart)
}

/// The keyframes row's state: how many times the box was refused.
struct KeyframesDemo: Component {
    @State var refusals = 0

    var content: some ElementGroup {
        Row(gap: Pixels(24)) {
            // A tap gesture, not a `Button`: the looks demo's tests count its
            // click targets and press the bottom-most as the scheme toggle.
            Text("Shake").padding(Pixels(6)).background(.surfaceSecondary).cornerRadius(Pixels(5))
                .onTapGesture { refusals += 1 }
            Box().frame(width: Pixels(60), height: Pixels(24)).background(.accent).cornerRadius(Pixels(4))
                .keyframeAnimator(initialValue: 0.0, trigger: refusals) { content, x in
                    content.offset(x: Pixels(Float(x)))
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(6, duration: 0.05)
                        LinearKeyframe(-6, duration: 0.1)
                        LinearKeyframe(0, duration: 0.05)
                    }
                }
            Box().frame(width: Pixels(24), height: Pixels(24)).background(.separator).cornerRadius(Pixels(12))
                .keyframeAnimator(initialValue: 0.0, repeating: true) { content, y in
                    content.offset(y: Pixels(Float(y)))
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(-8, duration: 0.4)
                        CubicKeyframe(0, duration: 0.4)
                    }
                }
        }
        .alignItems(.center)
    }
}

/// The transitions section, then the gradients, blur and materials section
/// (C10 lane 3), the latter as a `Component` so the composer's frame holds an
/// empty struct and the section is built in the component's own frame
/// (`PE-K`): built inline here, the looks tree overflowed the 1 MB thread
/// (`everyProductionTreeBuildsOnAOneMegabyteThread`, `.signal(SIGBUS)`,
/// measured, `LK-W` item 10).
@MainActor
private func looksTransitionsAndLooks() -> some Element {
    Column(gap: Pixels(18)) {
        looksTransitionsSection()
        LooksGradientsBlurMaterials()
    }
    .alignItems(.flexStart)
}

/// The gradients, blur and materials section as a `Component` (`LK-W` item 10).
struct LooksGradientsBlurMaterials: Component {
    var content: some ElementGroup { gradientsBlurMaterialsSection() }
}

/// An 8 × 8 two-tone checker, the blurred image's source.
@MainActor private let looksCheckerBitmap: ImageBitmap = {
    var rgba: [UInt8] = []
    for y in 0..<8 { for x in 0..<8 { rgba += (x + y) % 2 == 0 ? [230, 80, 40, 255] : [40, 90, 220, 255] } }
    return ImageBitmap(width: 8, height: 8, rgba: rgba)
}()

/// The looks row (C10 lane 3, rulings `LK-J`, `LK-K`, `LK-L`, `LK-M`, `LK-W`;
/// spec §6): a window-style vertical gradient panel (the strip, M5-d), a
/// diagonal and a radial gradient, a text and an image blurred at radii 0, 2
/// and 6 (M5-c), a pair of squares shadowed per leaf and through
/// `compositingGroup()` (C13, `PF-E`), and the six materials over a striped backdrop in both schemes
/// (divergence 166: a flat tint, no blur, MG-9). **Its own function**, each row
/// in its own frame — the gradients row a `Component` (`PE-K`), the blur and
/// materials rows functions (`LK-X`) — no click target (the demo's tests count
/// them). Human checks: spec §7 items 5–8.
@MainActor
func gradientsBlurMaterialsSection() -> some Element {
    Column(gap: Pixels(10)) {
        Text("Gradients, blur, materials").font(size: 20)
        LooksGradientsRow()
        looksBlurRow()
        looksCompositingGroupRow()
        looksMaterialsRow(scheme: .light)
        looksMaterialsRow(scheme: .dark)
    }
    .alignItems(.flexStart)
}

/// A vertical (strip), a diagonal and a radial gradient.
struct LooksGradientsRow: Component {
    var content: some ElementGroup {
        HStack(spacing: Pixels(12)) {
            RoundedRectangle(cornerRadius: Pixels(8))
                .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.82)], startPoint: .top,
                                     endPoint: .bottom))
                .frame(width: Pixels(90), height: Pixels(60))
            Rectangle()
                .fill(LinearGradient(colors: [.orange, .pink, .indigo], startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: Pixels(90), height: Pixels(60))
            Circle()
                .fill(RadialGradient(colors: [.yellow, .red.opacity(0)], center: .center, startRadius: Pixels(0),
                                     endRadius: Pixels(30)))
                .frame(width: Pixels(60), height: Pixels(60))
        }
    }
}

/// A text and an image blurred at radii 0, 2 and 6. A function, not a
/// `Component`: a `Component` whose content is a loop, inside another
/// `Component`'s container, crashes Swift 6.4's asserts compiler (`LK-X`).
@MainActor
private func looksBlurRow() -> some Element {
    HStack(spacing: Pixels(12)) {
        ForEach([0, 2, 6], id: \.self) { radius in
            VStack(spacing: Pixels(4)) {
                Text("Blur \(radius)").font(size: 13).blur(radius: Pixels(Float(radius)))
                Image(looksCheckerBitmap, scale: 1, label: Text("Checker"))
                    .frame(width: Pixels(32), height: Pixels(32))
                    .blur(radius: Pixels(Float(radius)))
            }
        }
    }
}

/// Two overlapping squares, a red and a blue offset (16, 16) over it.
@MainActor
private func looksOverlappingSquares() -> some Element & ProposalElementGroup {
    ZStack {
        Color.red.frame(width: Pixels(36), height: Pixels(36))
        Color.blue.frame(width: Pixels(36), height: Pixels(36)).offset(x: Pixels(16), y: Pixels(16))
    }
}

/// `compositingGroup()` (C13, ruling `PF-E`; human check PF2): the same pair
/// of overlapping squares shadowed per leaf (two shadows — the red square's
/// falls on the blue, SwiftUI's P1) and through `.compositingGroup()` (one
/// shadow of the pair's union, drawn below both, P2). A function, no loop
/// (`LK-X`), in the gradients-blur-materials section's own frame.
@MainActor
private func looksCompositingGroupRow() -> some Element {
    HStack(spacing: Pixels(28)) {
        VStack(spacing: Pixels(6)) {
            looksOverlappingSquares().shadow(radius: Pixels(3), x: Pixels(6), y: Pixels(6))
            Text("per leaf").font(size: 11)
        }
        VStack(spacing: Pixels(6)) {
            looksOverlappingSquares().compositingGroup().shadow(radius: Pixels(3), x: Pixels(6), y: Pixels(6))
            Text("compositingGroup()").font(size: 11)
        }
    }
}

/// The six materials over red and blue stripes, in `scheme`. A function, not a
/// `Component`, for the reason `looksBlurRow()` gives (`LK-X`).
@MainActor
private func looksMaterialsRow(scheme: ColorScheme) -> some ElementGroup {
    HStack(spacing: Pixels(0)) {
        ForEach(0..<looksMaterials.count, id: \.self) { i in
            ZStack {
                HStack(spacing: Pixels(0)) {
                    ForEach(0..<6, id: \.self) { k in
                        (k % 2 == 0 ? Color.red : Color.blue).frame(width: Pixels(10), height: Pixels(30))
                    }
                }
                Text(looksMaterials[i].0).font(size: 10)
                    .frame(width: Pixels(60), height: Pixels(20))
                    .background(looksMaterials[i].1)
            }
        }
    }
    .environment(\.colorScheme, scheme)
}

/// The six materials, named.
@MainActor private let looksMaterials: [(String, Material)] = [
    ("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial),
    ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial), ("bar", .bar),
]

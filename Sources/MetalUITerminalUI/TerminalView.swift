import MetalUI
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import MetalUITerminal
import MetalUITextSystem


/// The terminal's content, internal so the public ``TerminalView`` can wrap it in `.equatable()` itself (`TRM-BD`):
/// `Equatable` over the source object, theme, exceptions and flags, closures not compared. It holds the `@State`,
/// the environment reads and the whole modifier chain.
struct TerminalViewField: Component, @MainActor Equatable {
    let snapshotSource: TerminalSnapshotSource
    let theme: TerminalPalette
    let keyCaptureExceptions: [KeyboardShortcut]
    let optionAsMeta: Bool
    let cursorBlink: Bool
    let blinkStopsAfterIdle: Bool
    let boldIsBright: Bool
    let cursorStyle: TerminalCursorStyle
    let accessibilityLabel: String
    let onInput: ([UInt8]) -> Void
    let onResize: (TerminalSize) -> Void
    let onLink: (TerminalLinkQuery) -> TerminalLinkTarget?
    let onPaste: (@MainActor (String, TerminalModes) -> Bool)?

    @State private var model = TerminalViewModel()
    /// Read by the public `TerminalView` (an `OpenURLAction` and a `Clipboard` hold functions, so an `@Environment`
    /// reading of either is uncomparable and would refuse the memo: `EE-B`); not compared.
    let openURL: OpenURLAction
    let clipboard: Clipboard
    @FocusState private var isFocused: Bool
    @Environment(\.textMeasurer) private var measurer
    @Environment(\.displayScale) private var displayScale
    @Environment(\.font) private var environmentFont
    @Environment(\.controlActiveState) private var activeState

    init(snapshotSource: TerminalSnapshotSource, theme: TerminalPalette, keyCaptureExceptions: [KeyboardShortcut],
         optionAsMeta: Bool, cursorBlink: Bool, blinkStopsAfterIdle: Bool, boldIsBright: Bool,
         cursorStyle: TerminalCursorStyle, accessibilityLabel: String,
         onInput: @escaping ([UInt8]) -> Void, onResize: @escaping (TerminalSize) -> Void,
         onLink: @escaping (TerminalLinkQuery) -> TerminalLinkTarget?,
         onPaste: (@MainActor (String, TerminalModes) -> Bool)?, openURL: OpenURLAction, clipboard: Clipboard) {
        self.snapshotSource = snapshotSource
        self.theme = theme
        self.keyCaptureExceptions = keyCaptureExceptions
        self.optionAsMeta = optionAsMeta
        self.cursorBlink = cursorBlink
        self.blinkStopsAfterIdle = blinkStopsAfterIdle
        self.boldIsBright = boldIsBright
        self.cursorStyle = cursorStyle
        self.accessibilityLabel = accessibilityLabel
        self.onInput = onInput
        self.onResize = onResize
        self.onLink = onLink
        self.onPaste = onPaste
        self.openURL = openURL
        self.clipboard = clipboard
    }

    private static func buttonGesture(_ button: MouseButton, _ terminal: TerminalMouseEvent.Button,
                                      _ model: TerminalViewModel) -> DragGesture {
        DragGesture(minimumDistance: Pixels(0), button: button)
            .onChanged { value in model.pointerChanged(value, button: terminal) }
            .onEnded { value in model.pointerEnded(value, button: terminal) }
    }

    /// Whether two views draw and behave alike (`TRM-BD`): the same snapshot source object, theme, key-capture
    /// exceptions and flags. The closures (`onInput`, `onResize`, `onLink`, `onPaste`) are not compared, as `TabStrip`'s are not:
    /// a replay keeps the closures of the build that last ran. With surface replay (#362) a retained field replays
    /// its surface, so an idle terminal costs no element request.
    static func == (l: TerminalViewField, r: TerminalViewField) -> Bool {
        same(l.snapshotSource, l.theme, l.keyCaptureExceptions, l.optionAsMeta, l.cursorBlink, l.blinkStopsAfterIdle, l.boldIsBright, l.cursorStyle, l.accessibilityLabel,
             r.snapshotSource, r.theme, r.keyCaptureExceptions, r.optionAsMeta, r.cursorBlink, r.blinkStopsAfterIdle, r.boldIsBright, r.cursorStyle, r.accessibilityLabel)
    }

    static func same(_ ls: TerminalSnapshotSource, _ lt: TerminalPalette, _ le: [KeyboardShortcut], _ lo: Bool, _ lc: Bool, _ lb: Bool, _ lbb: Bool, _ lcs: TerminalCursorStyle, _ lal: String,
                     _ rs: TerminalSnapshotSource, _ rt: TerminalPalette, _ re: [KeyboardShortcut], _ ro: Bool, _ rc: Bool, _ rb: Bool, _ rbb: Bool, _ rcs: TerminalCursorStyle, _ ral: String) -> Bool {
        ls === rs && lt == rt && le == re && lo == ro && lc == rc && lb == rb && lbb == rbb && lcs == rcs && lal == ral
    }

    /// The view's content: the surface leaf under a focus layer and a geometry scope. Not for callers.
    var content: some ElementGroup {
        let model = self.model
        model.source = snapshotSource
        model.onResize = onResize
        model.cursorBlink = cursorBlink
        model.blinkStopsAfterIdle = blinkStopsAfterIdle
        model.focused = isFocused
        model.setDefaultCursorStyle(cursorStyle)
        let focusBinding = $isFocused
        model.requestFocus = { if !focusBinding.wrappedValue { focusBinding.wrappedValue = true } }
        model.onInput = onInput
        model.optionAsMeta = optionAsMeta
        model.exceptions = keyCaptureExceptions
        model.onLink = onLink
        model.onPaste = onPaste
        model.openURL = { url in openURL(url) }
        if let system = measurer.terminalTextSystem {
            model.prepare(system: system, font: environmentFont.terminalDescriptor, scale: Float(displayScale))
        }
        return TerminalSurfaceElement(model: model, palette: theme, boldIsBright: boldIsBright || theme.boldIsBright,
                               accessibilityLabel: accessibilityLabel)
            .focusable()
            .focused($isFocused)
            .keyCapture(except: keyCaptureExceptions, optionAsMeta: optionAsMeta)
            .onKeyPress { press in model.handle(press, clipboard: clipboard) }
            .pasteDestination(for: String.self, action: { items in model.paste(items.joined(separator: "\n")) })
            .copyable(model.copyItems())
            .externalTextInput(model.input)
            .pointerInput(hover: { phase in
                switch phase {
                case .active(let point): model.hoverMoved(to: point)
                case .ended: model.hoverEnded()
                }
            }, gesture: Self.buttonGesture(.primary, .left, model)
                .simultaneously(with: Self.buttonGesture(.middle, .middle, model))
                .simultaneously(with: Self.buttonGesture(.secondary, .right, model)),
            wheel: { event in model.wheel(event) },
            style: { _ in model.pointer.link == nil ? nil : .link })
            .onGeometryChange(for: TerminalSize.self, of: { proxy in
                model.grid(forPoints: Double(proxy.size.width.value), Double(proxy.size.height.value))
            }, action: { size in model.gridChanged(to: size) })
            .onChange(of: isFocused && activeState != .inactive) { _, now in model.focusChanged(to: now) }
            .onModifierKeysChanged(initial: false) { _, now in model.modifiersChanged(to: now) }
    }
}

/// A terminal: the cell grid of a ``TerminalSnapshotSource`` drawn on a GPU surface (Alloy gap 2, `TRM-BA`,
/// frozen by Phase 5.3).
///
/// ```swift
/// let source = TerminalSnapshotSource(emulator: emulator, queue: queue)
/// TerminalView(snapshotSource: source, theme: .xterm,
///              onInput: { bytes in pty.write(bytes) },
///              onResize: { size in pty.resize(size) },
///              onLink: { _ in nil })
///     .font(.system(size: 13, design: .monospaced))
/// ```
///
/// **Size.** The grid is as many whole cells as the view's laid-out size holds in the environment's font (default:
/// the system face's monospaced design, 13 points), measured in whole device pixels (`TRM-AZ`). When the cell
/// count changes (and once at first layout) the view calls `snapshotSource.resize(_:)` and then `onResize`, so the
/// host resizes its pty; the size is clamped to 2 columns by 1 row and never reported twice. With no proposal the
/// view asks for 80 x 24 cells.
///
/// **Output** does not rebuild the window. The view binds the source's wake to its surface's redraw trigger, so
/// a feed costs a surface-only frame (no build, no element request) however many feeds arrived, and that frame
/// redraws only the damaged rows over the retained target; the cursor, the selection and a blink toggle redraw
/// only the rows they change. A new or resized target, a palette, font or scale change and a reflow redraw every
/// row. A view that is not painted starts no frame and no timer.
///
/// **The cursor** takes the program's shape (block, bar, underline), or `cursorStyle`'s until the program sets one (`TRM-BE`). Unfocused, or in an inactive window, it is a
/// hollow block, as in Terminal.app. It blinks when the view's `cursorBlink` is on and the program asked for a
/// blinking style (`CSI 0-5 SP q` or mode 12): it toggles every 500 ms (two surface frames a second) and, when
/// `blinkStopsAfterIdle`, stops 30 s after the last output or input with the cursor drawn solid. An unfocused
/// view schedules nothing.
///
/// **Colours and text.** The palette's background is opaque. Bold is the bold face (bright colours only with
/// `boldIsBright`); underline in five styles, strikethrough, dim, inverse and hidden follow the cell's rendition;
/// box drawing, blocks, braille and Powerline are drawn to the cell; wide characters take two cells; colour emoji
/// draw monochrome; ligatures are off. A scrolled-back viewport draws the rows the snapshot lists.
///
/// **Keyboard input** (`TRM-BC`, Phase 5.4). While focused the view is a key capture layer
/// (`keyCapture(except: keyCaptureExceptions, optionAsMeta: optionAsMeta)`): every key reaches it before the
/// keymap, menus and commands; it encodes the key with the newest modes (application cursor keys and keypad) and
/// sends the bytes to `onInput`. A key that encodes to nothing (every command-modified key) is left to the app, so
/// ⌘Q, ⌘W and a `CommandMenu`'s ⌘K still run. Typed text, a dead key's result, the emoji picker and an input
/// method's commit arrive as text and are sent UTF-8 encoded; an input method's marked text is drawn at the
/// cursor, underlined, and sent only when committed (the candidate window sits at the cursor cell). **Paste** is ⌘V
/// (and Edit ▸ Paste) on Apple platforms and Ctrl+Shift+V elsewhere, where Ctrl+V is the child's own: the text is
/// sent through `TerminalEncoder.encodePaste` (bracketed when the program asked, ESC stripped). **Focus** in and out
/// is reported with `ESC [ I` and `ESC [ O` while the program set mode 1004. Every byte sent restarts the blink's idle clock.
///
/// **The pointer** (`TRM-BD`, Phase 5.5). With the program's mouse reporting on, presses, moves and releases (and the
/// wheel) are encoded through `TerminalEncoder.encodeMouse` and sent to `onInput`; ⇧ held at the press selects locally
/// instead. Otherwise a drag selects (⌥-drag a block, double-click a word, triple-click a line, ⇧-click extends, past the
/// edge scrolls), ⌘C copies, and the wheel scrolls scrollback (on the alternate screen it sends arrow keys). With ⌘ held
/// (Ctrl on Linux and Windows) the hovered cell is offered to `onLink` once per cell change; a target is underlined with
/// the pointing hand, ⌘-click activates it, and OSC 8 hyperlinks the host did not claim are offered by the view itself.
/// **Accessibility** (`TRM-BH`): while a client is present the view publishes one read-only multi-line text area, labelled
/// `accessibilityLabel` (default "Terminal"; a host passes the terminal's title from `TerminalEvent.title`), whose value is
/// the viewport's rows, trailing blanks trimmed, joined by newlines. The value is
/// re-read after every surface-only frame, so output reaches a screen reader without a build or an element request; with
/// no client nothing is read. The alternate screen and a scrolled-back viewport expose the rows they show; the cursor
/// position is not published (the node model has no selection).
///
/// **Idle, it costs nothing extra on a rebuilt frame without the caller adding `.equatable()`** (`TRM-BD`): the public
/// type is a thin component whose content is the internal field under `.equatable()`, so the field's content is
/// skipped and its surface replayed while the inputs (not the closures) are equal. A host that swaps `onInput`,
/// `onResize`, `onLink` or `onPaste` for closures with different captures keeps the first build's closures until an input
/// changes; give the view a new `.id(_:)` to force them.
public struct TerminalView: Component, @MainActor Equatable {
    let snapshotSource: TerminalSnapshotSource
    let theme: TerminalPalette
    let keyCaptureExceptions: [KeyboardShortcut]
    let optionAsMeta: Bool
    let cursorBlink: Bool
    let blinkStopsAfterIdle: Bool
    let boldIsBright: Bool
    let cursorStyle: TerminalCursorStyle
    let accessibilityLabel: String
    let onInput: ([UInt8]) -> Void
    let onResize: (TerminalSize) -> Void
    let onLink: (TerminalLinkQuery) -> TerminalLinkTarget?
    let onPaste: (@MainActor (String, TerminalModes) -> Bool)?

    @Environment(\.openURL) private var openURL
    @Environment(\.clipboard) private var clipboard

    /// A terminal over `snapshotSource` drawn in `theme`.
    ///
    /// - Parameters:
    ///   - snapshotSource: The emulator's hand-off. The view binds its wake and takes its snapshots; nothing else
    ///     may (one view per source).
    ///   - theme: The palette.
    ///   - keyCaptureExceptions: Shortcuts that skip key capture and reach the app (`keyCapture(except:)`).
    ///   - optionAsMeta: Both Option keys send ESC-prefixed keys and skip dead keys (`keyCapture(optionAsMeta:)`).
    ///   - cursorBlink: Whether a blinking cursor style blinks (default true).
    ///   - blinkStopsAfterIdle: Stop blinking 30 s after the last input or output (default true).
    ///   - boldIsBright: Bold ANSI 0-7 draws bright, as the palette's own flag does (default false).
    ///   - cursorStyle: The cursor's default style (`TRM-BE`): the shape, and whether it asks to blink, until the program sets
    ///     one with DECSCUSR 1-6; `CSI 0 SP q`, DECSTR and RIS return to it. Default a steady block. A blinking style blinks
    ///     only while `cursorBlink` is on. Changing it redraws the cursor.
    ///   - accessibilityLabel: The name a screen reader gives the terminal's text area (`TRM-BH`); a host passes the program's
    ///     title (`TerminalEvent.title`) here. Default "Terminal".
    ///   - onInput: The bytes a key, committed text, paste or focus report encodes to; the host writes them to the pty.
    ///   - onResize: The grid size, when the cell count changes, after the source was resized.
    ///   - onLink: The link under a ⌘-hovered cell: asked `.hover` once per cell change, `.exit` on leaving, `.activate` on ⌘-click.
    ///   - onPaste: A hook called with the text about to be pasted and the terminal's current modes (`TRM-BG`), before the
    ///     default paste, for every paste route (⌘V and Edit ▸ Paste on Apple platforms, Ctrl+Shift+V elsewhere). Return
    ///     true when the host handled the paste (nothing is sent; the host may send `TerminalEncoder.encodePaste(text, modes:)`
    ///     through its own `onInput` path, for instance after a confirmation), false for the default paste. Empty text never
    ///     reaches it. `modes` are the newest the source has (the snapshot waiting to be drawn, else the last drawn one), so
    ///     a mode the program set before the paste (bracketed paste, 2004) already shows. Default nil: the default paste.
    public init(snapshotSource: TerminalSnapshotSource,
                theme: TerminalPalette,
                keyCaptureExceptions: [KeyboardShortcut] = [],
                optionAsMeta: Bool = false,
                cursorBlink: Bool = true,
                blinkStopsAfterIdle: Bool = true,
                boldIsBright: Bool = false,
                cursorStyle: TerminalCursorStyle = TerminalCursorStyle(shape: .block, blinking: false),
                accessibilityLabel: String = "Terminal",
                onInput: @escaping ([UInt8]) -> Void,
                onResize: @escaping (TerminalSize) -> Void,
                onLink: @escaping (TerminalLinkQuery) -> TerminalLinkTarget?,
                onPaste: (@MainActor (String, TerminalModes) -> Bool)? = nil) {
        self.snapshotSource = snapshotSource
        self.theme = theme
        self.keyCaptureExceptions = keyCaptureExceptions
        self.optionAsMeta = optionAsMeta
        self.cursorBlink = cursorBlink
        self.blinkStopsAfterIdle = blinkStopsAfterIdle
        self.boldIsBright = boldIsBright
        self.cursorStyle = cursorStyle
        self.accessibilityLabel = accessibilityLabel
        self.onInput = onInput
        self.onResize = onResize
        self.onLink = onLink
        self.onPaste = onPaste
    }

    /// Whether two views draw and behave alike: the same source object, theme, exceptions and flags; closures are not compared.
    public static func == (l: TerminalView, r: TerminalView) -> Bool { 
        TerminalViewField.same(l.snapshotSource, l.theme, l.keyCaptureExceptions, l.optionAsMeta, l.cursorBlink, l.blinkStopsAfterIdle, l.boldIsBright, l.cursorStyle, l.accessibilityLabel,
                               r.snapshotSource, r.theme, r.keyCaptureExceptions, r.optionAsMeta, r.cursorBlink, r.blinkStopsAfterIdle, r.boldIsBright, r.cursorStyle, r.accessibilityLabel)
    }

    /// The field under `.equatable()`. Not for callers.
    public var content: some ElementGroup {
        TerminalViewField(snapshotSource: snapshotSource, theme: theme, keyCaptureExceptions: keyCaptureExceptions,
                          optionAsMeta: optionAsMeta, cursorBlink: cursorBlink, blinkStopsAfterIdle: blinkStopsAfterIdle,
                          boldIsBright: boldIsBright, cursorStyle: cursorStyle, accessibilityLabel: accessibilityLabel,
                          onInput: onInput, onResize: onResize, onLink: onLink,
                          onPaste: onPaste, openURL: openURL, clipboard: clipboard)
            .equatable()
    }
}

/// The surface leaf: one native node answering the proposal, and a `GPUSurface` painted under its own id.
struct TerminalSurfaceElement: ProposalElement {
    let model: TerminalViewModel
    let palette: TerminalPalette
    let boldIsBright: Bool
    let accessibilityLabel: String

    /// The stamp that makes the surface redraw on a full frame when what a draw depends on changed.
    struct Stamp: Hashable {
        var palette: [UInt32]
        var focused: Bool
        var active: Bool
        var boldIsBright: Bool
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let model = self.model
        let node = pass.requestNativeLeaf { proposal in
            let cell = MainActor.assumeIsolated { model.cellSize } ?? (width: 8, height: 16)
            return LayoutMeasurement(size: SizeD(width: proposal.width ?? cell.width * 80,
                                                 height: proposal.height ?? cell.height * 24))
        }
        return (node, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        // One read-only text area node, only while an accessibility client is present; its value is re-read after
        // every surface-only frame, so output never rebuilds the tree (`TRM-BH`).
        let model = self.model
        pass.terminalDeclareAccessibility(id, bounds: bounds, label: accessibilityLabel, value: { model.accessibilityText() })
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
                        pass: inout PaintPass) {
        func rgb(_ color: Color, opaque: Bool = true) -> (TerminalRGB, Float) {
            let c = pass.terminalRGBA(color)
            return (TerminalRGB(c.r, c.g, c.b), opaque ? 1 : c.a)
        }
        var packed: [UInt32] = []
        var ansi: [TerminalRGB] = []
        for color in palette.ansi {
            let (value, _) = rgb(color)
            ansi.append(value)
            packed.append(UInt32(value.r) << 16 | UInt32(value.g) << 8 | UInt32(value.b))
        }
        let foreground = rgb(palette.foreground).0, background = rgb(palette.background).0
        let cursor = rgb(palette.cursor).0, cursorText = rgb(palette.cursorText).0
        let (selection, alpha) = rgb(palette.selection, opaque: false)
        for value in [foreground, background, cursor, cursorText, selection] {
            packed.append(UInt32(value.r) << 16 | UInt32(value.g) << 8 | UInt32(value.b))
        }
        packed.append(UInt32((alpha * 255).rounded()))
        model.colors = ResolvedTerminalColors(
            scheme: TerminalColorScheme(ansi: ansi, foreground: foreground, background: background,
                                        boldIsBright: boldIsBright),
            cursor: cursor, cursorText: cursorText, selection: selection, selectionAlpha: alpha)
        model.windowActive = pass.terminalWindowIsActive
        model.bounds = bounds
        let stamp = Stamp(palette: packed, focused: model.focused, active: model.windowActive, boldIsBright: boldIsBright)
        let model = self.model
        var surface = GPUSurface(redraw: .onDemand, value: stamp, trigger: model.trigger) { context in
            let sink = (context as? any SurfaceTextSinkProviding)?.textSink
            model.draw(into: sink, time: context.time, isNewTarget: context.isNewTarget) { r, g, b, a in
                context.clear(red: r * a, green: g * a, blue: b * a, alpha: a)
            }
        }
        var l: Void = (), p: Void = ()
        surface.paint(id, bounds: bounds, layout: &l, prepaint: &p, pass: &pass)
    }
}

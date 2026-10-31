import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform

/// SwiftUI's `PasteButton` (ruling `CP-B`; probe `docs/probes/swiftui-clipboard-extras.swift`): a button
/// that pastes the clipboard's items, **dimmed and inert while the clipboard holds nothing it can
/// import**.
///
/// **A control composed over `Button`** (one hitbox, focusable, Space/Return through `ControlKeys`, the
/// `.disabled` gate, `.buttonStyle`, role `button`: no new accessibility role and no bridge row). It takes
/// no label (SwiftUI's takes none): the chrome is a bordered button reading "Paste" (divergence 717 —
/// SwiftUI's icon and system look are unprobed, and MetalUI shows no paste-permission prompt).
///
/// **Enablement** is *by presence*, never the validator (`CB-G`): enabled while some clipboard item
/// offers a type that satisfies the payload's `importedContentTypes()` (or `supportedContentTypes`). The
/// window learns of a clipboard change through the platform (`setClipboardChangeHandler`, `CP-G`) and
/// redraws for it **only while a `PasteButton` is on screen**; AppKit compares `changeCount` on becoming
/// key and at each press, so a manager rewriting the clipboard while the window is key and idle shows at
/// the next press. A click reads **every** clipboard item (`CP-D`) and runs the action once with the
/// values it could import; a clipboard with nothing importable runs nothing. It does not go through
/// `dispatchClipboardKey`: ⌘V is `pasteDestination`'s.
///
/// **A `PasteButton` inside an `.equatable()` component is never replayed** — retention refuses by the
/// name `pasteButton` in all three channels (`CP-H`, `CP-L`), counted in `FrameWork`.
public struct PasteButton: Element, StyledElement {
    /// What the button imports and what it delivers.
    enum Spec {
        /// `[T]` of one `Transferable` type.
        case payload(wanted: () -> [ContentType], paste: @MainActor (ClipboardAccess) -> Void)
        /// `[DropItem]` for the given content types.
        case items(wanted: [ContentType], action: @MainActor ([DropItem]) -> Void)

        var wantedTypes: [ContentType] {
            switch self {
            case .payload(let wanted, _): wanted()
            case .items(let wanted, _): wanted
            }
        }
    }

    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    let spec: Spec
    private var ownStyle: ResolvedButtonStyle?
    private var inner: Button<Text>

    /// A button that pastes the clipboard's items as `T`s (SwiftUI's `PasteButton(payloadType:onPaste:)`):
    /// `onPaste` runs from input, once per click, with every item `T` imports, in clipboard order; an
    /// item it cannot import is skipped, and with none importable it does not run.
    public init<T: Transferable>(payloadType: T.Type, onPaste: @escaping @MainActor ([T]) -> Void) {
        self.init(spec: .payload(wanted: { T.importedContentTypes() }, paste: { access in
            let values = access.items().compactMap { importClipboardItem($0, as: T.self) }
            if !values.isEmpty { onPaste(values) }
        }))
    }

    /// A button that pastes the clipboard's items as lazily read `DropItem`s (SwiftUI's
    /// `PasteButton(supportedContentTypes:payloadAction:)`, whose `NSItemProvider` is MetalUI's
    /// `DropItem`): enabled while some item offers a type that is, or conforms to, one of
    /// `supportedContentTypes`; `payloadAction` receives every clipboard item that does, once per click.
    public init(supportedContentTypes: [ContentType],
                payloadAction: @escaping @MainActor ([DropItem]) -> Void) {
        self.init(spec: .items(wanted: supportedContentTypes, action: payloadAction))
    }

    private init(spec: Spec) {
        let seed = Button("Paste") {}
        self.style = seed.style
        self.decoration = seed.decoration
        self.spec = spec
        self.inner = seed
    }

    /// Sets the button's look, as `Button.buttonStyle(_:)` does (`.plain` and `.borderless` drop the
    /// chrome).
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> Self {
        var copy = self
        copy.ownStyle = ResolvedButtonStyle(style)
        return copy
    }

    /// `buttonStyle(_:)` for a custom ``ButtonStyle``.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> Self {
        var copy = self
        copy.ownStyle = ResolvedButtonStyle(style)
        return copy
    }

    /// Whether `snapshot` (each item's identifiers) holds a type `wanted` accepts (`CP-B`).
    static func offers(_ snapshot: [[String]], satisfying wanted: [ContentType]) -> Bool {
        snapshot.contains { identifiers in
            identifiers.contains { identifier in
                let type = ContentType.builtIn(identifier)?.pasteboardType ?? PasteboardType(identifier: identifier)
                return wanted.contains { type.satisfies($0.identifier) }
            }
        }
    }

    /// Runs `body` with `isEnabled` forced off when the clipboard offers nothing: the one gate
    /// (`registerHandlers`) and the disabled look read it (`CP-B`).
    private static func gated<R>(_ frame: Frame, _ spec: Spec, _ body: () -> R) -> R {
        guard !offers(frame.clipboardAccess?.snapshot() ?? [], satisfying: spec.wantedTypes),
              frame.environmentTop.isEnabled else { return body() }
        var values = frame.environmentSnapshot()
        values.isEnabled = false
        return frame.withEnvironment(values, body)
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Button<Text>.Layout) {
        let frame = pass.frame
        frame.taintRetention("pasteButton")   // the build channel's journal (`CP-H`)
        let spec = self.spec
        let access = frame.clipboardAccess
        var button = Button("Paste") { [spec, access] in
            guard let access else { return }
            switch spec {
            case .payload(_, let paste): paste(access)
            case .items(_, let action):
                let items = access.items().filter { item in
                    Self.offers([item.types.map(\.identifier)], satisfying: spec.wantedTypes)
                }
                if !items.isEmpty { action(items) }
            }
        }
        button.ownStyle = ownStyle
        button.style = style
        button.decoration = decoration
        button.elementID = elementID
        button.handlers = handlers
        inner = button
        return Self.gated(frame, spec) { inner.requestLayout(id, pass: &pass) }
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Button<Text>.Layout,
                                  pass: inout PrepaintPass) -> Button<Text>.PrepaintState {
        let frame = pass.frame, spec = self.spec
        frame.notePasteButton()
        return Self.gated(frame, spec) { inner.prepaint(id, bounds: bounds, layout: &layout, pass: &pass) }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Button<Text>.Layout,
                               prepaint: inout Button<Text>.PrepaintState,
                               pass: inout PaintPass) {
        let frame = pass.frame, spec = self.spec
        frame.taintRetention("pasteButton")
        Self.gated(frame, spec) { inner.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass) }
    }
}

/// How a `PasteButton` reaches the platform's clipboard (`CP-D`, `CP-M`): a class holding the window's
/// platform **weakly**, stamped on every frame by `Window`, so an action closure that outlives the
/// window reads nothing. It also holds the snapshot of each item's type identifiers: read from the
/// platform **only when a `PasteButton` asks and the snapshot is stale** (at the first one, and after
/// the platform reported a change), so a window with no button never reads the clipboard.
@MainActor
final class ClipboardAccess {
    weak var platform: (any PlatformWindow)?
    private var cached: [[String]] = []
    private var stale = true
    /// How many times the snapshot was read from the platform (a pin counts work).
    private(set) var reads = 0

    init(platform: any PlatformWindow) { self.platform = platform }

    /// Each clipboard item's identifiers, read afresh only when stale.
    func snapshot() -> [[String]] {
        if stale {
            cached = platform?.clipboardItems() ?? []
            stale = false
            reads += 1
        }
        return cached
    }

    /// The platform reported a change: the next `snapshot()` reads again.
    func invalidate() { stale = true }

    /// Every clipboard item as a lazily read `DropItem` (`CB-F`), in clipboard order.
    func items() -> [DropItem] {
        guard let platform else { return [] }
        return platform.clipboardItems().enumerated().map { index, identifiers in
            DropItem(types: identifiers.map { ContentType.builtIn($0)?.pasteboardType ?? PasteboardType(identifier: $0) },
                     load: { [weak platform] identifier in platform?.readClipboard(item: index, identifier: identifier) })
        }
    }
}

import Foundation
import MetalUICore

/// A key for a custom environment value — SwiftUI's `EnvironmentKey`
/// (ruling EV-C).
///
/// `static let defaultValue = 0` satisfies the requirement. The value is read
/// wherever no writer above the reader set one.
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// The values an element's position in the tree hands it: SwiftUI's
/// `EnvironmentValues`, scoped by nearest writer (ruling EV-A).
///
/// **Not a cascade.** A value is produced only at a writer —
/// `.environment(_:_:)`, `.transformEnvironment(_:transform:)`,
/// `.dynamicTypeSize(_:)`, `.theme(_:)` or `Window.environment` — and handed
/// out only to a reader: `pass.environment`, or an element whose type
/// declares an `@Environment`. Nothing is written into every node.
///
/// **Not `@MainActor`**: a plain value with nothing isolated in it. **Not
/// `Sendable`**: custom keys are stored as `[ObjectIdentifier: Any]`, and
/// SwiftUI's `EnvironmentKey.Value` is unconstrained, so this cannot promise
/// what its contents are. That same storage is why `Window.environment`
/// cannot compare an old and a new value, and every write to it dirties the
/// window (ruling EV-H).
///
/// **One field is not the caller's to write, and access control alone does
/// not stop it** (rulings EV-U, EV-AA). `theme` is `internal`, so it has no
/// writable key path outside the module — but `\.self` does, and
/// `.environment(\.self, EnvironmentValues())` would reset it.
/// `Frame.scopedValues(applying:)` and `Frame.rootEnvironment` re-stamp it
/// after every write instead: **`theme` is MetalUI's own key.** SwiftUI has
/// none; `.theme(_:)` is its only writer by design (ruling EV-G), and the
/// re-stamp is what makes that true.
///
/// **`displayScale` is the caller's to write, as in SwiftUI** (ruling EV-AA,
/// which withdrew `EV-U`'s `pixelLength` half and retired divergence 24). A
/// `\.self` reset in a 2x window reads `displayScale` 1 and `pixelLength` 1,
/// SwiftUI's answer (probe `swiftui-environment-pixel-length.swift` X2).
///
/// **Three fields of `Window.environment` are not the root's source**: the
/// frame stamps `theme` (from `Window.theme`) and `displayScale` (from its
/// `scaleFactor`), and the window stamps `controlActiveState` (from its
/// platform window) over whatever `Window.environment` holds. A scope below
/// the root may still write `displayScale` and `controlActiveState`.
public struct EnvironmentValues {
    /// Every field at SwiftUI's **bare** default (ruling EV-Y): enabled,
    /// left-to-right, the root locale `Locale(identifier: "")`, `.large`, a
    /// `displayScale` of 1 (so a `pixelLength` of 1), `.key`, `.regular`, the
    /// light theme, and every custom key at its `defaultValue` — what a bare
    /// SwiftUI `EnvironmentValues()` holds (probe
    /// `swiftui-environment-pixel-length.swift` V0, V2; probe
    /// `swiftui-environment-control-state.swift` V0).
    ///
    /// **Not a window's defaults.** A hosted SwiftUI view reads the user's
    /// locale, the display's scale and the window's key state (scoping probe C,
    /// pixel-length probe X0, control-state probe S0 and C0) because its host
    /// stamps them over the bare value. Here too: a `Window` stamps
    /// `Locale.current` into its `environment` and its platform's
    /// `controlActiveState` into the root, and a `Frame` stamps `displayScale`
    /// and the theme. A `Frame` built without a window keeps the root locale
    /// and `.key`.
    public init() {
        locale = Locale(identifier: "")
    }

    /// The root value `Window.environment` starts from: `EnvironmentValues()`
    /// with `Locale.current` stamped over the bare locale, as a SwiftUI host
    /// does (ruling EV-Y, pixel-length probe X0).
    static func windowDefault() -> EnvironmentValues {
        var values = EnvironmentValues()
        values.locale = Locale.current
        return values
    }

    /// Whether controls below accept interaction. `true` by default.
    ///
    /// **The gate reads this value, not the modifier that wrote it** (ruling
    /// EV-D, probe P8/P9): `.disabled(_:)` ANDs it with what it inherits, and a
    /// raw `.environment(\.isEnabled, true)` below a disabled scope
    /// re-enables. `Frame.registerHandlers` reads it at registration, and when
    /// it is `false` the element registers no hitbox (a click reaches what is
    /// under it; it is neither hovered nor pressed), no focus, action handlers,
    /// raw `onKey` or `keyContext`, writes no `$focus` slot, and its declared
    /// AX node carries `.disabled` (rulings EV-E, EV-F, EV-T). A raw
    /// `PrepaintPass.insertHitbox` is not gated; an element using it reads this
    /// itself.
    public var isEnabled: Bool = true

    /// The direction horizontal layout reads in. `.rightToLeft` mirrors layout as
    /// SwiftUI's does (ruling `LD-A`, divergence 25 retired); a shape's own path,
    /// gradient unit points, `trim` and `UnevenRoundedRectangle`'s corners are
    /// not mirrored (divergence 1045).
    public var layoutDirection: LayoutDirection = .leftToRight

    /// `Locale(identifier: "")` in a bare value, as in SwiftUI (V0, V2);
    /// `Locale.current` under a window, which stamps it into
    /// `Window.environment` (ruling EV-Y). **No built-in consumer**: `Text`'s
    /// tokenizer and typesetter never receive it (ruling EV-H, pinned by
    /// `aLocaleChangesNoTextMeasurementUnderTheProposalAuthority`).
    public var locale: Locale

    /// Carried; changes no built-in text size — no text style, the default
    /// font or a `relativeTo:` font — which is SwiftUI's macOS answer (rulings
    /// EV-I, TE-E; probes G and F7, pinned by
    /// `dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority` and
    /// `noFontRespondsToDynamicTypeSize`).
    public var dynamicTypeSize: DynamicTypeSize = .large

    /// Points to device pixels for the display this content is drawn on —
    /// SwiftUI's `displayScale` (ruling EV-AA). **Public and writable**, as in
    /// SwiftUI; 1 in a bare value (probe `swiftui-environment-control-state.swift`
    /// V0).
    ///
    /// **At the root it is the frame's `scaleFactor`** — the drawable's, from
    /// `WindowRenderer.beginFrame()`, or `renderFrame(scaleFactor:)`'s — so it
    /// follows a window onto a display with another backing scale on the next
    /// frame (probe S0: a hosted view reads `backingScaleFactor`; S1: an
    /// `ImageRenderer`'s content reads the renderer's scale). A scale that is not
    /// finite and positive stamps 1. `Window.environment.displayScale` is not
    /// the root's source: the frame re-stamps it.
    ///
    /// **A scope can write it** (S2), and `pixelLength` follows; a `\.self`
    /// reset reads 1 (X2). **A write changes the number, not the scale drawing
    /// uses** — SwiftUI's behaviour too (S3): `PaintPass.fill` takes points and
    /// scales by the frame's factor, never by this value, so pre-scaling a rect
    /// by it double-scales on a Retina display, exactly as in SwiftUI.
    ///
    /// **Layout does not snap to it — divergence 77** (ruling EV-AD): layout
    /// rounds to whole points at every scale, where SwiftUI rounds to this
    /// value's pixel grid (S4). **No built-in reader**; it exists for element
    /// authors.
    public var displayScale: Double = 1

    /// One device pixel, in points: SwiftUI's function of `displayScale`,
    /// verbatim — `1 / displayScale`, **except 0 → 1** (probe
    /// `swiftui-environment-control-state.swift` V1: −1 → −1, NaN → NaN,
    /// ∞ → 0; SwiftUI rejects no write, and nothing internal reads this, so no
    /// stored rect can go non-finite through it).
    ///
    /// **Get-only, derived** (ruling EV-AA): write `displayScale` to change it.
    /// A value in this unit draws a hairline correctly through `PaintPass.fill`,
    /// which takes points. **No internal reader**; it exists for element
    /// authors.
    public var pixelLength: Double {
        displayScale == 0 ? 1 : 1 / displayScale
    }

    /// Whether the window is key, active or inactive — SwiftUI's
    /// `controlActiveState` (ruling EV-AB). `.key` in a bare value (probe
    /// `swiftui-environment-control-state.swift` V0), so a windowless `Frame` and
    /// `renderFrame` read `.key`; a `Window` stamps its platform window's state
    /// into the root at draw, and `Window.environment.controlActiveState` is not
    /// the root's source. A scope can write it (C4). **The built-in controls
    /// read it** (plan task 12 part 1, ruling `IX-H`): `Toggle`, `Slider`, a
    /// radio `Picker` and every control's focus ring paint `.accent` only when
    /// it is `.key`, and `.separator` otherwise (`controlAccent(_:)`; probe
    /// `swiftui-interaction` PX17–PX20 measure `.key` against `.inactive`;
    /// `.active` is MetalUI's, never measured).
    public var controlActiveState: ControlActiveState = .key

    /// Whether the user asked the system to reduce motion — SwiftUI's
    /// `accessibilityReduceMotion` (plan task 13, ruling `AN-AD`). `false` in a
    /// bare value, so a windowless `Frame` and `renderFrame` read `false`; a
    /// `Window` stamps its platform window's value into the root at draw (the
    /// AppKit window reads `NSWorkspace.accessibilityDisplayShouldReduceMotion`
    /// and re-reads it on its display-options notification; an SDL window
    /// answers `false`), and `Window.environment`'s own value is not the
    /// root's source.
    ///
    /// **Get-only outside the module**, as SwiftUI's key path is: a scope
    /// cannot write it (`aScopeCannotWriteReduceMotion`). **What it changes,
    /// measured** (probe `swiftui-transactions-animation.swift` R3–R10):
    /// property animations — `withAnimation`, `.animation(_:value:)`,
    /// `.transaction` — are unchanged, and every transition except `.identity`
    /// becomes an opacity cross-fade on the same animation.
    public internal(set) var accessibilityReduceMotion: Bool = false

    /// Whether the user asked the system to reduce transparency (SwiftUI's
    /// `accessibilityReduceTransparency`, `MT-D`). `false` in a bare value and in
    /// `renderFrame`; the window stamps its platform window's value over its root
    /// environment at every draw, beside `accessibilityReduceMotion`. When `true`
    /// every `Material` draws an opaque grey instead of a blur (`MT-F`, divergence
    /// 315).
    ///
    /// **Get-only outside the module**, as SwiftUI's key path is: a scope cannot
    /// write it (`aScopeCannotWriteReduceTransparency`).
    public internal(set) var accessibilityReduceTransparency: Bool = false

    /// The platform's display-accessibility settings, as one value (`AD-D`): the storage behind
    /// the six keys below. Internal -- a `Window` stamps it over its root environment at every
    /// draw (`AD-E`); `renderFrame` stamps the bare value. A bare value is a bare SwiftUI
    /// `EnvironmentValues()`'s reading (probe `swiftui-accessibility-display.swift` V0).
    var accessibilityDisplay = AccessibilityDisplaySettings()

    /// Whether the user asked for more contrast (SwiftUI's `colorSchemeContrast`, `AD-D`).
    /// `.standard` in a bare value and in `renderFrame`; the window stamps its platform
    /// window's value. **No built-in view reacts to it**, though SwiftUI's colours and several
    /// controls do (probe C0, C1; divergence 1076) -- it is for authors to read. **Get-only
    /// outside the module**, as SwiftUI's key path is: a scope cannot write it
    /// (`theAccessibilityDisplayKeysAreReadOnlyOutsideMetalUI`).
    public internal(set) var colorSchemeContrast: ColorSchemeContrast {
        get { accessibilityDisplay.colorSchemeContrast }
        set { accessibilityDisplay.colorSchemeContrast = newValue }
    }

    /// Whether the user asked to differentiate without colour (SwiftUI's
    /// `accessibilityDifferentiateWithoutColor`, `AD-D`). `false` in a bare value. No built-in
    /// view reads it, and none of SwiftUI's built-in controls changed with it either (probe
    /// D1: no pixel moved). Get-only outside the module.
    public internal(set) var accessibilityDifferentiateWithoutColor: Bool {
        get { accessibilityDisplay.differentiateWithoutColor }
        set { accessibilityDisplay.differentiateWithoutColor = newValue }
    }

    /// Whether the user asked to invert colours (SwiftUI's `accessibilityInvertColors`,
    /// `AD-D`). `false` in a bare value. No built-in view reads it (probe I1: no SwiftUI
    /// control changed). Get-only outside the module.
    public internal(set) var accessibilityInvertColors: Bool {
        get { accessibilityDisplay.invertColors }
        set { accessibilityDisplay.invertColors = newValue }
    }

    /// Whether the user asked to show borders / button shapes (SwiftUI's
    /// `accessibilityShowBorders`, `AD-D`). `false` in a bare value; AppKit reads it on macOS
    /// 26.1 and later and `false` before. **No built-in view reacts to it**, though SwiftUI's
    /// bordered `Button` and checkbox `Toggle` do (probe B1; divergence 1078). Get-only
    /// outside the module.
    public internal(set) var accessibilityShowBorders: Bool {
        get { accessibilityDisplay.showBorders }
        set { accessibilityDisplay.showBorders = newValue }
    }

    /// SwiftUI's earlier spelling of ``accessibilityShowBorders`` (`AD-D`). **Not deprecated
    /// here**: SwiftUI marks it deprecated, renamed, but warns nowhere today (probe A).
    /// Get-only.
    public var accessibilityShowButtonShapes: Bool { accessibilityShowBorders }

    /// Whether the user asked to dim flashing lights (SwiftUI's `accessibilityDimFlashingLights`,
    /// `AD-D`). `false` in a bare value. Nothing built in reads it (MetalUI plays no video).
    /// Get-only outside the module.
    public internal(set) var accessibilityDimFlashingLights: Bool {
        get { accessibilityDisplay.dimFlashingLights }
        set { accessibilityDisplay.dimFlashingLights = newValue }
    }

    /// Whether animated images may play (SwiftUI's `accessibilityPlayAnimatedImages`, `AD-D`).
    /// **`false` in a bare value** (probe V0) -- a window stamps its platform's value, `true`
    /// unless the user turned Auto-Play Animated Images off. Nothing built in reads it (MetalUI
    /// decodes no animated image, `PX-C`). Get-only outside the module.
    public internal(set) var accessibilityPlayAnimatedImages: Bool {
        get { accessibilityDisplay.playAnimatedImages }
        set { accessibilityDisplay.playAnimatedImages = newValue }
    }

    /// The text weight the user asked for (SwiftUI's `legibilityWeight`, `AD-J`): `nil` in a
    /// bare value and in a hosted SwiftUI view (probe H0), and the window stamps nothing.
    /// **Writable**, as SwiftUI's is: `.environment(\.legibilityWeight, .bold)` scopes it.
    /// **`Text` does not read it**, though SwiftUI's widens (probe L1; divergence 1079) --
    /// for authors to read.
    public var legibilityWeight: LegibilityWeight? = nil

    /// How far a hidden title bar overlaps the content (ruling `AS-E` item 4,
    /// MetalUI-only — SwiftUI keeps the content in a safe area instead,
    /// divergence 175): `top` is the bar's height (32 points on macOS, more
    /// with a toolbar), `left` the window buttons' right edge (69 points), in
    /// the window's coordinates; `right` and `bottom` are 0. **Zero** under the
    /// standard title bar, in full screen and on SDL. Pad a top bar by them to
    /// keep clear of the traffic lights. Zero in a bare value; a `Window`
    /// stamps its own into the root at draw, as it does
    /// `accessibilityReduceMotion`; get-only outside the module.
    public internal(set) var titleBarInsets: Edges<Pixels> = Edges(all: Pixels(0))

    /// The window's content size in points (ruling `OV-G`, MetalUI-only —
    /// SwiftUI has no such key, probe arms W0/W1 and T5–T8; its idiom is a
    /// `GeometryReader` on a greedy root). **Everything drawn inside the
    /// content is included** (`OV-O`): the `.hiddenTitleBar` band
    /// (divergence 175) and SDL's drawn toolbar strip; subtract
    /// `titleBarInsets` for the area below a hidden bar. Zero in a bare value;
    /// a `Window` stamps the size each build is laid out at into the root
    /// (never through `Window.environment`), so a live resize is in the frame
    /// presenting it; the headless `renderFrame` stamps its `size` (`OV-R`).
    /// Get-only outside the module.
    public internal(set) var windowSize: Size<Pixels> = Size(width: Pixels(0), height: Pixels(0))

    /// The window's open and save dialogs as async calls (ruling `SV-D`) —
    /// MetalUI-only. A bare value's has no window, so a call throws
    /// `FileDialogError.noWindow`; a `Window` stamps its own into the root at
    /// draw (`Window.environment`'s value is never the source). **Get-only
    /// outside the module** (guard `fileDialogsIsReadOnlyOutsideMetalUI`).
    /// Read it while building and call it from a `Task` in an action.
    public internal(set) var fileDialogs = FileDialogs(window: nil)

    /// The colour scheme content below is drawn in — SwiftUI's `colorScheme`
    /// (ruling `CR-J` item 2). `.light` in a bare value (probe
    /// `swiftui-colour.swift` E0), so a windowless `Frame` and `renderFrame`
    /// read `.light`; a `Window` stamps its effective scheme into the root at
    /// draw. **Readable while building** (`@Environment(\.colorScheme)`) and
    /// in every phase, and writable by a scope (probe V1), whose subtree then
    /// resolves dynamic colours — and tokens, through the window's variant
    /// for that scheme (`CR-K`, `CR-S`) — in it. Reading it never writes.
    public var colorScheme: ColorScheme = .light

    /// SwiftUI's `imageScale` (`SYM-B`): the scale an `Image(systemName:)` below draws at. `.medium`.
    public var imageScale: Image.Scale = .medium

    /// SwiftUI's `symbolVariants` (`SYM-B`): the variants an `Image(systemName:)` below appends to its name.
    /// `.none` by default.
    public var symbolVariants: SymbolVariants = .none

    /// What `symbolRenderingMode(_:)` wrote (`nil`: monochrome). Internal: SwiftUI has no public key.
    var symbolRenderingMode: SymbolRenderingMode?

    /// The size controls below should take — SwiftUI's `controlSize` (ruling
    /// EV-AC). `.regular` in a bare value (V0); written by `.controlSize(_:)` or
    /// `.environment(\.controlSize, _)`, nearest writer winning (Z1).
    ///
    /// **Two built-in readers** (ruling TE-F): `Button`'s chrome (`DD-R` item
    /// 4 — its padding and height follow the size), and the **default font**
    /// every `Text`, `ProposalText`, `TextField` and `TextEditor` resolves when
    /// neither it nor the environment names a font — 9 pt at `.mini`, 11 at
    /// `.small`, 13 otherwise (probe F8, Z2, R2), so a `Button`'s label and a
    /// field's height follow it too. An explicit or environment font ignores it
    /// (F8h). **Divergence 76, amended again and kept, owner none**: no other
    /// control's chrome reads it — `TextField`'s padding (SwiftUI's shrinks),
    /// `Toggle`, `Picker`, `Slider`, `Stepper` — pinned by
    /// `controlSizeReachesTheDefaultFontButNoControlsChrome`.
    public var controlSize: ControlSize = .regular

    /// The font a `Text`, `ProposalText`, `TextField` or `TextEditor` below
    /// resolves when it names none — SwiftUI's `font` (ruling TE-B item 2).
    /// `nil` in a bare value: the **default font**, `.system(size: 13)`, or 11
    /// and 9 under `controlSize` `.small` and `.mini` (TE-F). Written by
    /// `.font(_:)`; the nearest writer wins (probe F6e), and a text's own
    /// font wins over it (F6b).
    public var font: Font?

    /// The largest number of lines a `Text` below draws — SwiftUI's
    /// `lineLimit` (ruling TE-H): the upper bound of the pair `.lineLimit(_:)`
    /// writes. `nil`: no limit. Writing it keeps the lower bound.
    public var lineLimit: Int? {
        get { textLineLimit.max }
        set { textLineLimit.max = newValue }
    }

    /// Which end of a truncated line keeps its text (ruling TE-I). `.tail`.
    public var truncationMode: Text.TruncationMode = .tail

    /// How a multi-line text's lines sit in its box (ruling TE-J). `.leading`.
    public var multilineTextAlignment: TextAlignment = .leading

    /// The style of a `Text` or `ProposalText` below that names none and of the default fill of a shape below
    /// (rulings TE-D, `TG-A`): a colour, a gradient or a material. **Internal**: SwiftUI has no public key;
    /// written by `.foregroundStyle(_:)`/`.foregroundColor(_:)`. ``foregroundStyle`` is its colour.
    var foregroundStorage: ShapeStyleStorage?

    /// The glyph colour of a `Text` or `ProposalText` below that names none (ruling TE-D): ``foregroundStorage``'s
    /// representative colour (a gradient's first stop, a material's flat tint). **Writing a colour replaces a
    /// gradient or material written above it** (`TG-A`: one storage, so a colour below a gradient clears it).
    /// **Internal**: SwiftUI has no public key.
    var foregroundStyle: Color? {
        get { foregroundStorage?.representativeColor }
        set {
            // Not `newValue.map { .color($0) }`: that closure carries a main-actor check, and a text's colour is set while a
            // production tree is built (the one-megabyte-thread harness builds off the main thread).
            if let newValue { foregroundStorage = .color(newValue) } else { foregroundStorage = nil }
        }
    }

    /// The tint `.tint(_:)` wrote (`SS-D`): what `Color.accentColor` resolves to and what the
    /// built-in controls paint their accent in. `nil`: the theme's accent. Internal, as SwiftUI's has no
    /// public key; read it through ``Color/accentColor``.
    var tint: Color?

    /// `.fontWeight(_:)` over whichever font a text below resolves (TE-B
    /// item 3). Internal, as SwiftUI's is.
    var fontWeight: Font.Weight?

    /// `.italic(_:)` over whichever font a text below resolves (TE-B item 3).
    var italic: Bool = false

    /// `.bold(_:)` over whichever font a text below resolves (`TM-F`): bold where the text names no
    /// weight of its own and the font names none — a `.light` font stays light (probe `W`).
    var isBold: Bool = false

    /// The view-level text modifiers written above (`TM-A`): underline, strikethrough, kerning, tracking,
    /// baseline offset, monospaced — the layer under a `Text`'s own and a run's own fields. One reference,
    /// `nil` while none is written (`RT-R` item 4's reason: the value is copied through every scope).
    var textRichBox: TextRichBox?

    /// ``textRichBox``'s fields; writing an empty set stores `nil`.
    var textRich: TextRichFields {
        get { textRichBox?.fields ?? TextRichFields() }
        set { textRichBox = TextRichBox.boxing(newValue) }
    }
    var textUnderline: Text.LineStyle? {
        get { textRich.underline }
        set { textRich.underline = newValue }
    }
    var textStrikethrough: Text.LineStyle? {
        get { textRich.strikethrough }
        set { textRich.strikethrough = newValue }
    }
    var textKerning: Double? {
        get { textRich.kerning }
        set { textRich.kerning = newValue }
    }
    var textTracking: Double? {
        get { textRich.tracking }
        set { textRich.tracking = newValue }
    }
    var textBaselineOffset: Double? {
        get { textRich.baselineOffset }
        set { textRich.baselineOffset = newValue }
    }
    var textMonospaced: Bool? {
        get { textRich.monospaced }
        set { textRich.monospaced = newValue }
    }

    /// The line-limit pair (ruling TE-H): `lineLimit(n)` writes `(nil, n)`,
    /// `lineLimit(n, reservesSpace: true)` `(n, n)`, a range its bounds.
    var textLineLimit = TextLineLimit()

    /// The content margins `contentMargins(_:_:for:)` wrote (`CMG-A`): read by the scrollers below, internal.
    var contentMargins = ContentMargins()

    /// The theme tokens resolve against. **Internal, and paint-only**: the only
    /// public reader is `PaintPass.theme`, and the only public writer is
    /// `.theme(_:)` (ruling EV-G).
    var theme: Theme = .light

    /// The frame's text system, for ``textMeasurer`` (ruling GT-D). Internal;
    /// stamped by the root and restored after a `\.self` reset like `theme`.
    var textSystemBox: TextSystemBox?

    /// The field styles a `TextField`/`TextEditor` below draws in when it names
    /// none (rulings `MD-B` item 2, `MD-F`; `TextFieldStyle.swift`). Internal.
    var fieldStyles = FieldStyles()

    /// The `@Observable` objects `.environment(_ object:)` provided, keyed by the
    /// **static** type each was written as (port gaps, medium, ruling `MD-H`
    /// item 2; probe `swiftui-environment-object.swift` `K1`–`K2b`). Internal:
    /// read through `@Environment(Type.self)`.
    private var objects: [ObjectIdentifier: AnyObject] = [:]

    /// The object provided as `type`, or `nil` (`MD-H` item 2).
    func object<T: AnyObject>(_ type: T.Type) -> T? {
        // Only `setObject(_:as:)` writes the slot, under the same static type.
        objects[ObjectIdentifier(type)].map { $0 as! T }
    }

    /// Provides `object` as `type` below — `nil` removes it (probe `W1`).
    mutating func setObject<T: AnyObject>(_ object: T?, as type: T.Type) {
        objects[ObjectIdentifier(type)] = object
    }

    /// A custom key's stored value with the reading made of it once, at the write (`EE-C`): a fingerprint or a
    /// probe never casts.
    struct CustomValue {
        var value: Any
        var reading: EnvironmentReading
    }

    private var custom: [ObjectIdentifier: CustomValue] = [:]

    /// Writes a custom key with the reading the caller made of it (`BY-A`): a value whose comparability is not its own
    /// (a style holding a closure) names the reading of what it wraps.
    mutating func setCustom<K: EnvironmentKey>(_ key: K.Type, _ value: K.Value, reading: EnvironmentReading) {
        custom[ObjectIdentifier(key)] = CustomValue(value: value, reading: reading)
    }

    /// A custom key's value, or its `defaultValue` when no writer set it.
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            guard let stored = custom[ObjectIdentifier(key)] else { return K.defaultValue }
            // Only this setter writes the slot, typed by the same key.
            return stored.value as! K.Value
        }
        set { custom[ObjectIdentifier(key)] = CustomValue(value: newValue, reading: .of(newValue)) }
    }
}

/// The lower and upper line bounds `.lineLimit(_:)` writes (ruling TE-H).
struct TextLineLimit: Hashable, Sendable {
    var min: Int?
    var max: Int?
}

/// SwiftUI's twelve dynamic type sizes (ruling EV-I).
///
/// `Comparable` in declaration order, so `size >= .accessibility1` reads as it
/// does in SwiftUI.
public enum DynamicTypeSize: Sendable, Hashable, CaseIterable, Comparable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5

    /// Whether this is one of the five accessibility sizes.
    public var isAccessibilitySize: Bool { self >= .accessibility1 }
}

/// SwiftUI's five control sizes (ruling EV-AC).
///
/// Carried in `EnvironmentValues.controlSize`; `Button`'s chrome and the
/// default font are its built-in readers (`DD-R` item 4, TE-F; divergence 76,
/// amended).
public enum ControlSize: Sendable, Hashable, CaseIterable {
    case mini, small, regular, large, extraLarge
}

// MARK: - The retained-subtree fingerprint (`SB-G`)

/// Every built-in field of ``EnvironmentValues`` that prepaint or paint can read, as one
/// `Equatable` value, for a retained subtree's replay key (`SB-G`). The objects provided by
/// `.environment(_:)` compare by instance identity (`EE-K`). **A stored property added to `EnvironmentValues` owes a field here or a row in
/// `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant`** (a `Mirror` guard).
struct EnvironmentFingerprint: Equatable {
    var isEnabled: Bool
    var layoutDirection: LayoutDirection
    var locale: Locale
    var dynamicTypeSize: DynamicTypeSize
    var displayScale: Double
    var controlActiveState: ControlActiveState
    var accessibilityReduceMotion: Bool
    var accessibilityReduceTransparency: Bool
    var accessibilityDisplay: AccessibilityDisplaySettings
    var legibilityWeight: LegibilityWeight?
    var titleBarInsets: Edges<Pixels>
    var windowSize: Size<Pixels>
    var colorScheme: ColorScheme
    var imageScale: Image.Scale
    var symbolVariants: SymbolVariants
    var symbolRenderingMode: SymbolRenderingMode?
    var controlSize: ControlSize
    var font: Font?
    var lineLimit: Int?
    var truncationMode: Text.TruncationMode
    var multilineTextAlignment: TextAlignment
    var foregroundStyle: ShapeStyleStorage?
    var tint: Color?
    var fontWeight: Font.Weight?
    var italic: Bool
    var isBold: Bool
    var textRich: TextRichFields
    var textLineLimit: TextLineLimit
    var contentMargins: ContentMargins
    var fieldStyle: TextFieldStyle
    var editorStyle: TextEditorStyle
    var theme: Theme
    /// Whether a text system is stamped: the box is new each frame and the system behind it is
    /// the window's, constant for its life.
    var hasTextSystem: Bool
    /// The provided objects: type to **instance** (`EE-K`), so a swapped instance is a change.
    var objects: [ObjectIdentifier: ObjectIdentifier]
    /// The custom keys' readings (`EE-F`): an equal value is an equal fingerprint, an uncomparable one equals nothing.
    var custom: [ObjectIdentifier: EnvironmentReading]
}

extension EnvironmentFingerprint {
    /// Every field of this fingerprint that differs from `other`, by name (trace only, `AM-E`: the retained trace prints
    /// `key.ambient.environment.<field>`). A `Mirror` guard (`everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone`) makes a new
    /// field owe a row here.
    func differences(from other: EnvironmentFingerprint) -> [String] {
        var out: [String] = []
        if isEnabled != other.isEnabled { out.append("isEnabled") }
        if layoutDirection != other.layoutDirection { out.append("layoutDirection") }
        if locale != other.locale { out.append("locale") }
        if dynamicTypeSize != other.dynamicTypeSize { out.append("dynamicTypeSize") }
        if displayScale != other.displayScale { out.append("displayScale") }
        if controlActiveState != other.controlActiveState { out.append("controlActiveState") }
        if accessibilityReduceMotion != other.accessibilityReduceMotion { out.append("accessibilityReduceMotion") }
        if accessibilityReduceTransparency != other.accessibilityReduceTransparency { out.append("accessibilityReduceTransparency") }
        if accessibilityDisplay != other.accessibilityDisplay { out.append("accessibilityDisplay") }
        if legibilityWeight != other.legibilityWeight { out.append("legibilityWeight") }
        if titleBarInsets != other.titleBarInsets { out.append("titleBarInsets") }
        if windowSize != other.windowSize { out.append("windowSize") }
        if colorScheme != other.colorScheme { out.append("colorScheme") }
        if imageScale != other.imageScale { out.append("imageScale") }
        if symbolVariants != other.symbolVariants { out.append("symbolVariants") }
        if symbolRenderingMode != other.symbolRenderingMode { out.append("symbolRenderingMode") }
        if controlSize != other.controlSize { out.append("controlSize") }
        if font != other.font { out.append("font") }
        if lineLimit != other.lineLimit { out.append("lineLimit") }
        if truncationMode != other.truncationMode { out.append("truncationMode") }
        if multilineTextAlignment != other.multilineTextAlignment { out.append("multilineTextAlignment") }
        if foregroundStyle != other.foregroundStyle { out.append("foregroundStyle") }
        if tint != other.tint { out.append("tint") }
        if fontWeight != other.fontWeight { out.append("fontWeight") }
        if italic != other.italic { out.append("italic") }
        if isBold != other.isBold { out.append("isBold") }
        if textRich != other.textRich { out.append("textRich") }
        if textLineLimit != other.textLineLimit { out.append("textLineLimit") }
        if contentMargins != other.contentMargins { out.append("contentMargins") }
        if fieldStyle != other.fieldStyle { out.append("fieldStyle") }
        if editorStyle != other.editorStyle { out.append("editorStyle") }
        if theme != other.theme { out.append("theme") }
        if hasTextSystem != other.hasTextSystem { out.append("hasTextSystem") }
        if objects != other.objects { out.append("objects") }
        if custom != other.custom { out.append("custom") }
        return out
    }
}

extension EnvironmentValues {
    /// How many custom (app-defined) keys carry a value that cannot be compared (a function, a struct holding
    /// one): a non-zero count makes a retained subtree ineligible (`SB-G`, `EE-F`). Keys, not writes.
    var uncomparableCustomCount: Int { custom.values.reduce(0) { $0 + ($1.reading.isUncomparable ? 1 : 0) } }

    /// The fingerprint of the built-in fields.
    var retainedFingerprint: EnvironmentFingerprint {
        EnvironmentFingerprint(
            isEnabled: isEnabled, layoutDirection: layoutDirection, locale: locale,
            dynamicTypeSize: dynamicTypeSize, displayScale: displayScale,
            controlActiveState: controlActiveState,
            accessibilityReduceMotion: accessibilityReduceMotion,
            accessibilityReduceTransparency: accessibilityReduceTransparency,
            accessibilityDisplay: accessibilityDisplay, legibilityWeight: legibilityWeight,
            titleBarInsets: titleBarInsets, windowSize: windowSize, colorScheme: colorScheme,
            imageScale: imageScale, symbolVariants: symbolVariants, symbolRenderingMode: symbolRenderingMode,
            controlSize: controlSize, font: font, lineLimit: lineLimit, truncationMode: truncationMode,
            multilineTextAlignment: multilineTextAlignment, foregroundStyle: foregroundStorage, tint: tint,
            fontWeight: fontWeight, italic: italic, isBold: isBold, textRich: textRich,
            textLineLimit: textLineLimit, contentMargins: contentMargins,
            fieldStyle: fieldStyles.field, editorStyle: fieldStyles.editor, theme: theme,
            hasTextSystem: textSystemBox != nil,
            objects: objects.mapValues { ObjectIdentifier($0) },
            custom: custom.mapValues(\.reading))
    }
}

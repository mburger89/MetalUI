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

    /// Carried and readable; nothing mirrors under `.rightToLeft` yet (ruling
    /// EV-K).
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

    /// The colour scheme content below is drawn in — SwiftUI's `colorScheme`
    /// (ruling `CR-J` item 2). `.light` in a bare value (probe
    /// `swiftui-colour.swift` E0), so a windowless `Frame` and `renderFrame`
    /// read `.light`; a `Window` stamps its effective scheme into the root at
    /// draw. **Readable while building** (`@Environment(\.colorScheme)`) and
    /// in every phase, and writable by a scope (probe V1), whose subtree then
    /// resolves dynamic colours — and tokens, through the window's variant
    /// for that scheme (`CR-K`, `CR-S`) — in it. Reading it never writes.
    public var colorScheme: ColorScheme = .light

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

    /// The glyph colour of a `Text` or `ProposalText` below that names none
    /// (ruling TE-D). **Internal**: SwiftUI has no public key; written by
    /// `.foregroundStyle(_:)`/`.foregroundColor(_:)`.
    var foregroundStyle: Color?

    /// `.fontWeight(_:)` over whichever font a text below resolves (TE-B
    /// item 3). Internal, as SwiftUI's is.
    var fontWeight: Font.Weight?

    /// `.italic(_:)` over whichever font a text below resolves (TE-B item 3).
    var italic: Bool = false

    /// The line-limit pair (ruling TE-H): `lineLimit(n)` writes `(nil, n)`,
    /// `lineLimit(n, reservesSpace: true)` `(n, n)`, a range its bounds.
    var textLineLimit = TextLineLimit()

    /// The theme tokens resolve against. **Internal, and paint-only**: the only
    /// public reader is `PaintPass.theme`, and the only public writer is
    /// `.theme(_:)` (ruling EV-G).
    var theme: Theme = .light

    private var custom: [ObjectIdentifier: Any] = [:]

    /// A custom key's value, or its `defaultValue` when no writer set it.
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            guard let stored = custom[ObjectIdentifier(key)] else { return K.defaultValue }
            // Only this setter writes the slot, typed by the same key.
            return stored as! K.Value
        }
        set { custom[ObjectIdentifier(key)] = newValue }
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

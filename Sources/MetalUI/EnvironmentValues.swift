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

    /// Carried; changes no built-in text size, as in SwiftUI on macOS (ruling
    /// EV-I, probe G, pinned by
    /// `dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority`).
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
    /// the root's source. A scope can write it (C4). **No built-in consumer**:
    /// MetalUI's controls do not dim in an inactive window (owner plan task 12).
    public var controlActiveState: ControlActiveState = .key

    /// The size controls below should take — SwiftUI's `controlSize` (ruling
    /// EV-AC). `.regular` in a bare value (V0); written by `.controlSize(_:)` or
    /// `.environment(\.controlSize, _)`, nearest writer winning (Z1).
    ///
    /// **Carried, with no built-in reader — divergence 76, pinned wrong on
    /// purpose** by `controlSizeReachesNoBuiltInMeasurement`. SwiftUI's `Text`
    /// default font, `TextField` and `Button` follow it on macOS (Z2, Z3);
    /// MetalUI's measure nothing differently. Owners: plan task 11 (`Text`'s
    /// default font), plan task 10 (`TextField` and the common controls).
    public var controlSize: ControlSize = .regular

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
/// Carried in `EnvironmentValues.controlSize`; no built-in element reads it
/// (divergence 76).
public enum ControlSize: Sendable, Hashable, CaseIterable {
    case mini, small, regular, large, extraLarge
}

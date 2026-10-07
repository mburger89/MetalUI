import MetalUICore

// Port gaps, medium, lane 1 part 1 (MG-20; rulings `MD-B`…`MD-F` in
// `docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`, probe
// `docs/probes/swiftui-field-chrome.swift`): the two closed field styles and
// their container spellings.

/// How a `TextField` draws its field — SwiftUI's four macOS styles, as a
/// **closed** struct (ruling `MD-B` item 1; `ButtonStyle`'s shape, `IX-E`):
/// every call site spells as SwiftUI's does, and custom styles are not
/// offered.
///
/// `.automatic` — the default — `.roundedBorder` and `.squareBorder` draw the
/// same bordered field, as SwiftUI's do on macOS 27 (probe `PX`: byte-identical
/// pixels): 6 points of inset leading and trailing and 4 top and bottom
/// (3.5 at `.small`), a `.surface` fill, a 1-point `.separator` border, corner
/// radius 6, and the control focus ring while focused (`MD-D`, `MD-E`;
/// divergence 132). `.plain` is the bare field — no inset, no chrome, no ring.
///
/// Written on the field (`TextField.textFieldStyle(_:)`, so `.background` and
/// `.onSubmit` still chain) or on a container (`ElementGroup.textFieldStyle(_:)`,
/// reaching every field below); the innermost wins (probe `ENV1`–`ENV3`).
public struct TextFieldStyle: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case automatic, roundedBorder, squareBorder, plain
    }

    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    /// The platform's default: on macOS the bordered field (probe `SZ1`, `NS`).
    public static let automatic = TextFieldStyle(kind: .automatic)
    /// A rounded, bordered field — drawn as `.automatic` (probe `PX`).
    public static let roundedBorder = TextFieldStyle(kind: .roundedBorder)
    /// A square-bordered field — drawn as `.automatic`, rounded too, as
    /// SwiftUI draws it on macOS 27 (probe `PX`).
    public static let squareBorder = TextFieldStyle(kind: .squareBorder)
    /// No chrome: the text alone, at the field's bounds (probe `NS plain`).
    public static let plain = TextFieldStyle(kind: .plain)

    /// Whether this style draws the bordered chrome.
    var isBordered: Bool { kind != .plain }
}

/// How a `TextEditor` draws its background — SwiftUI's macOS pair, closed
/// (ruling `MD-F`). `.automatic`, the default, fills the editor's bounds with
/// `.surface` (SwiftUI's opaque text background, probe `ED`) and draws the
/// control focus ring while focused; `.plain` draws neither (probe `ED2`).
/// Neither changes the editor's size or its text's placement (divergence 133).
public struct TextEditorStyle: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case automatic, plain
    }

    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    /// The default: an opaque `.surface` background (probe `ED`).
    public static let automatic = TextEditorStyle(kind: .automatic)
    /// No background (probe `ED2`).
    public static let plain = TextEditorStyle(kind: .plain)
}

extension EnvironmentValues {
    /// The style a `TextField` below draws in when it names none (`MD-B` item
    /// 2). Internal: SwiftUI has no public key; written by
    /// `ElementGroup.textFieldStyle(_:)`.
    var textFieldStyle: TextFieldStyle {
        get { fieldStyles.field }
        set { fieldStyles.field = newValue }
    }

    /// The style a `TextEditor` below draws in when it names none (`MD-F`).
    var textEditorStyle: TextEditorStyle {
        get { fieldStyles.editor }
        set { fieldStyles.editor = newValue }
    }
}

/// The two environment field styles, stored together.
struct FieldStyles {
    var field: TextFieldStyle = .automatic
    var editor: TextEditorStyle = .automatic
}

extension ElementGroup {
    /// Draws every `TextField` below in `style`, unless it names its own —
    /// SwiftUI's `textFieldStyle(_:)` on a container (ruling `MD-B` item 2;
    /// probe `ENV1`). The nearest writer wins, and a field's own style wins
    /// over it (`ENV2`, `ENV3`).
    public func textFieldStyle(_ style: TextFieldStyle) -> EnvironmentScope<Self> {
        environment(\.textFieldStyle, style)
    }

    /// Draws every `TextEditor` below in `style`, unless it names its own —
    /// SwiftUI's `textEditorStyle(_:)` on a container (ruling `MD-F` item 1).
    public func textEditorStyle(_ style: TextEditorStyle) -> EnvironmentScope<Self> {
        environment(\.textEditorStyle, style)
    }
}

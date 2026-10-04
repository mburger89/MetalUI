import MetalUICore

// File dialogs and alerts at the platform seam (rulings `SV-B`, `SV-E`; spec
// `docs/superpowers/specs/2026-10-04-platform-services-design.md` §3). Values:
// `MetalUI` builds one of these from a `.fileImporter`/`.fileExporter`/
// `.alert` or a `FileDialogs` call and hands it to
// `PlatformWindow.presentFileDialog(_:)`/`presentAlert(_:)`; the platform shows
// it natively or declines, and answers later with a queued `InputEvent`
// (`.fileDialogResult`, `.alertResult`) naming the request's `token` — never
// inside the presenting call (`MN-C` item 4's reason). No closure and no
// Foundation type crosses the seam: a chosen file is a file-system path
// `String`, which `MetalUI` turns into a `URL`.

/// A file type at the seam (ruling `SV-E`): `ContentType` reduced to strings —
/// its uniform type identifier, every identifier it conforms to
/// (transitively), and the filename extensions that name it, preferred first.
/// AppKit maps it to a `UTType`; SDL filters by its extensions alone
/// (divergence 129).
public struct PlatformFileType: Sendable, Equatable {
    /// The uniform type identifier, e.g. `public.json`.
    public var identifier: String
    /// Every identifier this type conforms to, transitively; never contains
    /// `identifier` itself.
    public var conformsTo: [String]
    /// The filename extensions naming this type, without a dot, preferred
    /// first; empty when the type has none of its own (`public.data`).
    public var filenameExtensions: [String]

    /// A file type named `identifier`, conforming to `conformsTo`, named by
    /// `filenameExtensions`.
    public init(identifier: String, conformsTo: [String] = [], filenameExtensions: [String] = []) {
        self.identifier = identifier
        self.conformsTo = conformsTo
        self.filenameExtensions = filenameExtensions
    }
}

/// A request to show an open or save dialog (ruling `SV-B`), answered by
/// `InputEvent.fileDialogResult` carrying the same `token`.
public struct PlatformFileDialog: Sendable, Equatable {
    /// Which dialog.
    public enum Kind: Sendable, Equatable {
        /// Choose existing files — one, or several when
        /// `allowsMultipleSelection` (files only, never folders: `SV-F`).
        case open(allowsMultipleSelection: Bool)
        /// Choose where to save, the name field holding `defaultFilename`.
        case save(defaultFilename: String?)
    }

    /// Names this request in its answer; unique among a window's requests.
    public var token: Int
    /// Which dialog.
    public var kind: Kind
    /// The types the dialog offers; empty offers every file.
    public var allowedTypes: [PlatformFileType]
    /// The dialog's title, where the platform shows one; `nil` for its own.
    public var title: String?
    /// The confirming button's title, where the platform takes one; `nil` for
    /// its own ("Open", "Save").
    public var prompt: String?

    /// A request `token` for a dialog of `kind` offering `allowedTypes`.
    public init(token: Int, kind: Kind, allowedTypes: [PlatformFileType] = [],
                title: String? = nil, prompt: String? = nil) {
        self.token = token
        self.kind = kind
        self.allowedTypes = allowedTypes
        self.title = title
        self.prompt = prompt
    }
}

/// A file dialog's answer (ruling `SV-B` item 2), delivered as
/// `InputEvent.fileDialogResult` after `presentFileDialog(_:)` returned.
public struct FileDialogResultEvent: Sendable, Equatable {
    /// How the dialog ended.
    public enum Outcome: Sendable, Equatable {
        /// The user chose these files — file-system paths, never empty.
        case chosen([String])
        /// The user cancelled.
        case cancelled
        /// The platform could not show or complete the dialog; the message is
        /// the platform's (SDL's `SDL_GetError()`).
        case failed(String)
    }

    /// The answered request's `PlatformFileDialog.token`.
    public var token: Int
    /// How the dialog ended.
    public var outcome: Outcome

    /// The answer `outcome` to request `token`.
    public init(token: Int, outcome: Outcome) {
        self.token = token
        self.outcome = outcome
    }
}

/// One button of a `PlatformAlert` (rulings `SV-I` item 3, `SV-X`): its title
/// and the roles `AlertButtons.resolve` gave it. At most one button is the
/// default (Return) and at most one the cancel button (Escape).
public struct PlatformAlertButton: Sendable, Equatable {
    /// The button's title.
    public var title: String
    /// Whether the button's action is destructive (shown in red on AppKit).
    public var isDestructive: Bool
    /// Whether Return presses it.
    public var isDefault: Bool
    /// Whether Escape presses it.
    public var isCancel: Bool

    /// A button titled `title` with the given roles.
    public init(title: String, isDestructive: Bool = false, isDefault: Bool = false, isCancel: Bool = false) {
        self.title = title
        self.isDestructive = isDestructive
        self.isDefault = isDefault
        self.isCancel = isCancel
    }
}

/// A request to show an alert (rulings `SV-B`, `SV-J`), answered by
/// `InputEvent.alertResult` carrying the same `token`.
public struct PlatformAlert: Sendable, Equatable {
    /// Names this request in its answer; unique among a window's requests.
    public var token: Int
    /// The alert's title.
    public var title: String
    /// The text under the title, if any.
    public var message: String?
    /// The buttons in display order — the order AppKit adds them to an
    /// `NSAlert` (two side by side, the first on the trailing side; three or
    /// more stacked top-down).
    public var buttons: [PlatformAlertButton]

    /// A request `token` for an alert titled `title`.
    public init(token: Int, title: String, message: String?, buttons: [PlatformAlertButton]) {
        self.token = token
        self.title = title
        self.message = message
        self.buttons = buttons
    }
}

/// An alert's answer (ruling `SV-B` item 2), delivered as
/// `InputEvent.alertResult` after `presentAlert(_:)` returned.
public struct AlertResultEvent: Sendable, Equatable {
    /// The answered request's `PlatformAlert.token`.
    public var token: Int
    /// The pressed button's index in `PlatformAlert.buttons`; `nil` when the
    /// alert was dismissed without a button.
    public var button: Int?

    /// The answer `button` to request `token`.
    public init(token: Int, button: Int?) {
        self.token = token
        self.button = button
    }
}

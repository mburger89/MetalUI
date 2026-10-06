import MetalUICore
import MetalUIPlatform

// Alerts and confirmation dialogs: SwiftUI's spellings over a closed actions
// builder, and SwiftUI's buttons (rulings `SV-I`, `SV-X`, `SV-Y`; spec §2).
// SwiftUI's side: `docs/probes/swiftui-platform-services.swift` arms `A1`–`A9`,
// `C1`, and `docs/probes/swiftui-alert-presenting.swift` arms `R0`–`R4`,
// `K0`–`K3`. Natively an `NSAlert` sheet on AppKit; drawn by the window where
// the platform declines (SDL, `SV-J`).

/// The buttons an alert shows, resolved from its declared actions — the one
/// rule AppKit's `NSAlert` and the drawn alert share (rulings `SV-I` item 3,
/// `SV-X`). Pure.
enum AlertButtons {
    /// One declared action: a `Button`'s title, role and action.
    struct Declared {
        let title: String
        let role: ButtonRole?
        let action: (@MainActor () -> Void)?
    }

    /// One shown button: its seam value (title and roles), the declared action
    /// it runs (`nil` for a synthesized "OK" or "Cancel") and which declared
    /// button it is.
    struct Resolved {
        let platform: PlatformAlertButton
        let action: (@MainActor () -> Void)?
        let declaredIndex: Int?
    }

    /// SwiftUI's buttons for `declared` (`A1`–`A5`, `C1`, `K0`–`K3`):
    ///
    /// - no actions: one "OK", neither default nor cancel (`A3`, `K2`);
    /// - order: the non-cancel buttons in declaration order, then the cancel
    ///   buttons (declared anywhere, `A4`);
    /// - a destructive button with no cancel button gets a synthesized
    ///   "Cancel" (`A5`); plain buttons alone get none (`A2`);
    /// - Escape (`isCancel`): the first cancel button, declared or synthesized;
    /// - Return (`isDefault`): the first role-less declared button, **only when
    ///   no declared button is destructive** (`SV-X`: `A2`/`K0`, `K3`; never
    ///   `A1`, `A5`/`K1`).
    static func resolve(_ declared: [Declared]) -> [Resolved] {
        guard !declared.isEmpty else {
            return [Resolved(platform: PlatformAlertButton(title: "OK"), action: nil, declaredIndex: nil)]
        }
        let isCancel = { (role: ButtonRole?) in role == .cancel }
        let indexed = Array(declared.enumerated())
        let ordered = indexed.filter { !isCancel($0.element.role) } + indexed.filter { isCancel($0.element.role) }
        let hasDestructive = declared.contains { $0.role == .destructive }
        let defaultIndex = hasDestructive ? nil : declared.firstIndex { $0.role == nil }
        let cancelIndex = declared.firstIndex { isCancel($0.role) }
        var resolved = ordered.map { index, button in
            Resolved(platform: PlatformAlertButton(title: button.title, isDestructive: button.role == .destructive,
                                                   isDefault: index == defaultIndex, isCancel: index == cancelIndex),
                     action: button.action, declaredIndex: index)
        }
        if hasDestructive, cancelIndex == nil {
            resolved.append(Resolved(platform: PlatformAlertButton(title: "Cancel", isCancel: true),
                                     action: nil, declaredIndex: nil))
        }
        return resolved
    }
}

/// What an `AlertActions` evaluates to. SPI, with an internal initialiser, so
/// only this module can make one (`SV-I` item 2).
@_spi(AlertInternals) public struct _AlertButtons {
    let declared: [AlertButtons.Declared]
    init(_ declared: [AlertButtons.Declared]) { self.declared = declared }
}

/// The actions an alert or confirmation dialog shows: `Button`s whose label is
/// a `Text` — with `role: .cancel` or `.destructive` — and `if`, `if`/`else`
/// and `for` through `@AlertActionsBuilder` (ruling `SV-I` item 2).
///
/// **Closed**: its one requirement is SPI, so a type outside MetalUI cannot
/// conform (guard `anOutsideTypeCannotConformToAlertActions`). Not offered: a
/// `Button` whose label is not a `Text` (SwiftUI accepts any view; guard
/// `aNonTextButtonIsNotAnAlertAction`) and a `TextField`.
public protocol AlertActions {
    /// The buttons this content declares. SPI: see the protocol's doc.
    @_spi(AlertInternals) @MainActor func _alertButtons() -> _AlertButtons
}

/// What an `@AlertActionsBuilder` block builds: its buttons, in order.
public struct AlertActionItems: AlertActions {
    let children: [any AlertActions]

    init(_ children: [any AlertActions]) { self.children = children }

    /// This content's buttons. SPI: see `AlertActions`.
    @_spi(AlertInternals) public func _alertButtons() -> _AlertButtons {
        _AlertButtons(children.flatMap { $0._alertButtons().declared })
    }
}

/// The result builder for alert actions (ruling `SV-I` item 2): a block, `if`,
/// `if`/`else` and `for`, each element an `AlertActions`.
@resultBuilder
public enum AlertActionsBuilder {
    /// One action.
    public static func buildExpression<A: AlertActions>(_ action: A) -> AlertActionItems { AlertActionItems([action]) }
    /// A block of actions, in order; an empty block declares none (one "OK").
    public static func buildBlock(_ items: AlertActionItems...) -> AlertActionItems { AlertActionItems(items) }
    /// An `if` with no `else`: its actions, or none.
    public static func buildOptional(_ items: AlertActionItems?) -> AlertActionItems { items ?? AlertActionItems([]) }
    /// The first branch of an `if`/`else`.
    public static func buildEither(first items: AlertActionItems) -> AlertActionItems { items }
    /// The second branch of an `if`/`else`.
    public static func buildEither(second items: AlertActionItems) -> AlertActionItems { items }
    /// A `for` loop: every iteration's actions, in order.
    public static func buildArray(_ items: [AlertActionItems]) -> AlertActionItems { AlertActionItems(items) }
}

/// A button action: its label's string as the title, its role (now read:
/// `.cancel` and `.destructive` place and key it, `SV-I` item 3) and its action
/// (or a caller's `onClick`, which replaces it, as on the button itself).
extension Button: AlertActions where Label == Text {
    /// This content's buttons. SPI: see `AlertActions`.
    @_spi(AlertInternals) public func _alertButtons() -> _AlertButtons {
        _AlertButtons([AlertButtons.Declared(title: box.content.first.string, role: role,
                                             action: handlers.onClick ?? action)])
    }
}

// MARK: - The modifiers

extension ElementGroup {
    /// Presents an alert titled `title` while `isPresented` is `true` —
    /// SwiftUI's `alert(_:isPresented:actions:)` (rulings `SV-I`, `SV-K`).
    ///
    /// Shown after the frame in which `isPresented` turned `true`: an `NSAlert`
    /// sheet on AppKit, drawn in the window elsewhere (`SV-J`). Its buttons
    /// follow SwiftUI's rule (`SV-I` item 3, `SV-X`): the cancel button last
    /// and on Escape; a lone destructive button gains a "Cancel"; no actions
    /// show one "OK"; Return presses the first plain button only when no button
    /// is destructive. Any button writes `isPresented = false`, then runs its
    /// action — from input, on the main actor, dispatched to this group;
    /// setting `isPresented` to `false` dismisses it with no action (`A8`,
    /// `A9`). The actions are evaluated while building and the alert shows the
    /// ones of the frame it was presented in; a later change shows nothing new
    /// until it is presented again (`SV-I` item 4).
    public func alert<A: AlertActions>(_ title: String, isPresented: Binding<Bool>,
                                       @AlertActionsBuilder actions: () -> A) -> PresentationScope<Self> {
        let declared = actions()._alertButtons().declared
        return alertScope(isPresented) { AlertContent(title: title, message: nil, buttons: AlertButtons.resolve(declared)) }
    }

    /// `alert(_:isPresented:actions:)` with a message under the title (SwiftUI's
    /// `alert(_:isPresented:actions:message:)`).
    public func alert<A: AlertActions>(_ title: String, isPresented: Binding<Bool>,
                                       @AlertActionsBuilder actions: () -> A,
                                       message: () -> Text) -> PresentationScope<Self> {
        let declared = actions()._alertButtons().declared
        let text = message().string
        return alertScope(isPresented) { AlertContent(title: title, message: text, buttons: AlertButtons.resolve(declared)) }
    }

    /// An alert over `data` — SwiftUI's `alert(_:isPresented:presenting:actions:)`
    /// (ruling `SV-Y`). Presented whenever `isPresented` is `true`: with data,
    /// `actions` is called with it at presentation; with `nil`, the title and
    /// one "OK" show and `actions` is not called (`R1`, `R4`). Data changing
    /// while it is up changes nothing shown (`R2`, `R3`).
    public func alert<A: AlertActions, T>(_ title: String, isPresented: Binding<Bool>, presenting data: T?,
                                          @AlertActionsBuilder actions: @escaping (T) -> A)
        -> PresentationScope<Self> {
        alertScope(isPresented) {
            let declared = data.map { actions($0)._alertButtons().declared } ?? []
            return AlertContent(title: title, message: nil, buttons: AlertButtons.resolve(declared))
        }
    }

    /// `alert(_:isPresented:presenting:actions:)` with a message from the data —
    /// not called, and no message shown, for `nil` data (`SV-Y`).
    public func alert<A: AlertActions, T>(_ title: String, isPresented: Binding<Bool>, presenting data: T?,
                                          @AlertActionsBuilder actions: @escaping (T) -> A,
                                          message: @escaping (T) -> Text) -> PresentationScope<Self> {
        alertScope(isPresented) {
            guard let data else {
                return AlertContent(title: title, message: nil, buttons: AlertButtons.resolve([]))
            }
            return AlertContent(title: title, message: message(data).string,
                                buttons: AlertButtons.resolve(actions(data)._alertButtons().declared))
        }
    }

    /// A confirmation dialog — SwiftUI's `confirmationDialog(_:isPresented:actions:)`,
    /// presented exactly as `alert(_:isPresented:actions:)` is (`C1` = `A1`, an
    /// `NSAlert` sheet). `titleVisibility:` is not offered (only `.visible` was
    /// measured).
    public func confirmationDialog<A: AlertActions>(_ title: String, isPresented: Binding<Bool>,
                                                    @AlertActionsBuilder actions: () -> A) -> PresentationScope<Self> {
        alert(title, isPresented: isPresented, actions: actions)
    }

    /// `confirmationDialog(_:isPresented:actions:)` with a message (SwiftUI's
    /// `confirmationDialog(_:isPresented:actions:message:)`).
    public func confirmationDialog<A: AlertActions>(_ title: String, isPresented: Binding<Bool>,
                                                    @AlertActionsBuilder actions: () -> A,
                                                    message: () -> Text) -> PresentationScope<Self> {
        alert(title, isPresented: isPresented, actions: actions, message: message)
    }

    private func alertScope(_ isPresented: Binding<Bool>,
                            _ make: @escaping @MainActor () -> AlertContent) -> PresentationScope<Self> {
        PresentationScope(content: self, isPresented: isPresented, request: .alert(make))
    }
}

import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform

// File dialogs and alerts presented from the tree (rulings `SV-C`, `SV-I`,
// `SV-K`; spec `docs/superpowers/specs/2026-10-04-platform-services-design.md`
// §2, §4.2). One transparent scope, `PresentationScope` — `LifecycleScope`'s
// shape (`LC-B`): it notes a record in layout (reads only) and the window
// reconciles the records after the frame, outside every phase (`LC-E`'s
// place): present what turned `true`, dismiss what turned `false` or left.
// The platform shows the dialog or alert and answers with a queued
// `InputEvent`, which the window runs from input under `StateDispatch`.

/// `content` with a file dialog, an alert or a confirmation dialog it presents
/// while a binding is `true` — what `.fileImporter`, `.fileExporter`, `.alert`
/// and `.confirmationDialog` return (rulings `SV-C`, `SV-I`, `SV-K`).
///
/// **Transparent**: no layout node, no identity level, no `Handlers` member —
/// the content keeps the ids it would have without the scope, so adding or
/// removing a presentation moves no `@State`, focus or animation. The record
/// lives in the window's presentation registry, keyed by the position the scope
/// sits at, never in `StateTable` (`SV-K` item 2).
///
/// **Presented after the frame** in which the binding reads `true` (not in a
/// phase), **one at a time per window** — a second waits, its binding still
/// `true`, until the first is answered (`SV-K` item 3). A headless
/// `renderFrame` presents nothing.
///
/// **A `Self`-returning decoration written after this scope does not compile**
/// (`Text("a").alert(…) {}.onClick {}`; divergence 120): write it first.
public struct PresentationScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let isPresented: Binding<Bool>
    let request: PresentationRequest

    init(content: Content, isPresented: Binding<Bool>, request: PresentationRequest) {
        self.content = content
        self.isPresented = isPresented
        self.request = request
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], LifecycleScopeLayout<Content.GroupLayout>) {
        let start = cursor
        let (nodes, layout) = pass.frame.withPresentationScope {
            content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        // A group with no content presents nothing (`LC-P` item 1's footing).
        if !nodes.isEmpty {
            pass.frame.notePresentation(isPresented: isPresented, request: request, under: parent, at: start)
        }
        return (nodes, LifecycleScopeLayout(content: layout))
    }

    public mutating func prepaintGroup(layout: inout LifecycleScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paintGroup(layout: inout LifecycleScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// **The typed entry is a line-for-line copy of the untyped one, pinned on its
/// own** (guard 2.G7's typed arm and the proposal-content tests): a copy of a
/// pinned implementation is unpinned.
extension PresentationScope: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], LifecycleScopeLayout<Content.GroupLayout>) {
        let start = cursor
        let (nodes, layout) = pass.frame.withPresentationScope {
            content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        if !nodes.isEmpty {
            pass.frame.notePresentation(isPresented: isPresented, request: request, under: parent, at: start)
        }
        return (nodes, LifecycleScopeLayout(content: layout))
    }
}

// MARK: - Records

/// How a file dialog ended, as a presentation's completion sees it: the
/// platform's outcome with "could not show one" folded into the failure.
enum FileDialogOutcome {
    case chosen([String])
    case cancelled
    case failed(FileDialogError)
}

/// What a presentation scope asks for (`SV-K` item 2): data and closures, read
/// in layout, run after the frame or from input.
enum PresentationRequest {
    /// A file dialog of `kind` over `types`; `complete` runs after
    /// `isPresented` is written `false` (`SV-C` item 3).
    case fileDialog(kind: PlatformFileDialog.Kind, types: [ContentType], title: String?, prompt: String?,
                    complete: @MainActor (FileDialogOutcome) -> Void)
    /// An alert whose content is evaluated at presentation (`SV-I` item 4).
    case alert(@MainActor () -> AlertContent)
}

/// An alert's evaluated content: what the platform shows and what each
/// resolved button runs (`SV-I` items 3–4).
struct AlertContent {
    let title: String
    let message: String?
    let buttons: [AlertButtons.Resolved]
}

/// One presentation scope's record of the last build (`SV-K` item 2).
struct PresentationRecord {
    struct Key: Hashable {
        let scope: GlobalElementID
        let occurrence: Int
    }
    let key: Key
    /// The scope's position — what an outcome is dispatched to.
    let owner: GlobalElementID
    let isPresented: Binding<Bool>
    /// The binding's value when the scope was laid out.
    let isShown: Bool
    let request: PresentationRequest
}

extension Frame {
    /// Notes a present scope (`SV-K` item 2). The key is
    /// `.named("$presentation<depth>")` under the scope's position
    /// `.child(of: parent, at: cursor)` — a registry key, never a `StateTable`
    /// id (no reserved name, no `noteNamed`, `LC-C`'s footing) — with an
    /// occurrence for one element value placed twice.
    func notePresentation(isPresented: Binding<Bool>, request: PresentationRequest,
                          under parent: GlobalElementID?, at cursor: Int) {
        let owner = GlobalElementID.child(of: parent, at: cursor, name: nil)
        let scope = GlobalElementID.child(of: owner, at: 0, name: ElementID("$presentation\(presentationDepth)"))
        let occurrence = presentationOccurrences[scope, default: 0]
        presentationOccurrences[scope] = occurrence + 1
        presentationRecords.append(PresentationRecord(
            key: PresentationRecord.Key(scope: scope, occurrence: occurrence), owner: owner,
            isPresented: isPresented, isShown: isPresented.wrappedValue, request: request))
    }
}

// MARK: - The window's registry

/// The window's presentations (`SV-K`): the last build's records, the one
/// request in flight and the token counter. Window-owned, never a `StateTable`
/// entry.
@MainActor
final class PresentationRegistry {
    /// What is up in the window — at most one (`SV-K` item 3, `SV-D` item 2).
    enum InFlight {
        /// A scope's dialog or alert; `alert` is the content presented (its
        /// buttons run from it, `SV-I` item 4).
        case scope(key: PresentationRecord.Key, token: Int, record: PresentationRecord, alert: AlertContent?)
        /// A `FileDialogs` call awaiting its answer (`SV-D`).
        case call(token: Int, continuation: CheckedContinuation<FileDialogResultEvent.Outcome, Error>)

        var token: Int {
            switch self {
            case .scope(_, let token, _, _), .call(let token, _): token
            }
        }
    }

    /// The records of the last adopted build, in registration order.
    var records: [PresentationRecord] = []
    var inFlight: InFlight?
    private var lastToken = 0

    init() {}

    /// A token no earlier request of this window used.
    func makeToken() -> Int {
        lastToken += 1
        return lastToken
    }

    /// The latest record for `key`, or `nil` when the last build had none.
    func record(for key: PresentationRecord.Key) -> PresentationRecord? {
        records.first { $0.key == key }
    }

    /// A window that goes away with a call awaiting resumes it (`SV-D` item 2).
    isolated deinit {
        if case .call(_, let continuation)? = inFlight {
            continuation.resume(throwing: FileDialogError.noWindow)
        }
    }
}

/// An alert the platform declined to show natively (`SV-J` item 2): the
/// window's to draw — lane 3's `AlertPanel` — and to answer through
/// `Window.chooseAlertButton(_:)`.
struct DrawnAlert {
    let token: Int
    let title: String
    let message: String?
    let buttons: [AlertButtons.Resolved]
    /// The button the drawn panel's focus ring is on (`SV-J` item 3): the
    /// default (`SV-X`) at presentation, else none until Tab or an arrow.
    var ring: Int?
}

extension Window {
    /// After the frame (`SV-K` item 3; `LC-E`'s place, after the lifecycle's
    /// actions): a scope in flight whose record is gone or reads `false` is
    /// dismissed; with nothing in flight, the first record reading `true` is
    /// presented.
    func reconcilePresentations() {
        if case .scope(let key, let token, _, _)? = presentations.inFlight,
           presentations.record(for: key)?.isShown != true {
            presentations.inFlight = nil
            if drawnAlert?.token == token {
                drawnAlert = nil
                setNeedsRedraw()
            } else {
                dismissPresentationOnPlatform(token: token)
            }
        }
        guard presentations.inFlight == nil,
              let record = presentations.records.first(where: \.isShown) else { return }
        present(record)
    }

    private func present(_ record: PresentationRecord) {
        let token = presentations.makeToken()
        switch record.request {
        case .fileDialog(let kind, let types, let title, let prompt, let complete):
            let dialog = PlatformFileDialog(token: token, kind: kind, allowedTypes: types.map(\.platformFileType),
                                            title: title, prompt: prompt)
            if presentFileDialogOnPlatform(dialog) {
                presentations.inFlight = .scope(key: record.key, token: token, record: record, alert: nil)
            } else {
                // The platform cannot show one (`SV-C` item 3): a failure, now.
                StateDispatch.dispatching(to: record.owner) {
                    record.isPresented.wrappedValue = false
                    complete(.failed(.unavailable))
                }
            }
        case .alert(let make):
            let content = make()
            presentations.inFlight = .scope(key: record.key, token: token, record: record, alert: content)
            let alert = PlatformAlert(token: token, title: content.title, message: content.message,
                                      buttons: content.buttons.map(\.platform))
            if !presentAlertOnPlatform(alert) {
                drawnAlert = DrawnAlert(token: token, title: content.title, message: content.message,
                                        buttons: content.buttons,
                                        ring: content.buttons.firstIndex { $0.platform.isDefault })
                // A menu open when an alert is drawn is dismissed, and a
                // tooltip hidden: the alert is modal (`SV-J` items 2–3).
                dismissInWindowMenu()
                hideTooltip()
                setNeedsRedraw()
            }
        }
    }

    /// A dialog's answer, from input (`SV-C` item 3, `SV-D`): resumes the
    /// awaiting call, or writes the scope's `isPresented = false` and runs its
    /// completion under the scope's dispatch. An answer for a token no longer
    /// in flight (dismissed, cancelled) runs nothing (`SV-G` item 5).
    func handleFileDialogResult(_ result: FileDialogResultEvent) {
        guard let inFlight = presentations.inFlight, inFlight.token == result.token else { return }
        presentations.inFlight = nil
        switch inFlight {
        case .call(_, let continuation):
            continuation.resume(returning: result.outcome)
        case .scope(let key, _, let presented, _):
            let record = presentations.record(for: key) ?? presented
            guard case .fileDialog(_, _, _, _, let complete) = record.request else { return }
            let outcome: FileDialogOutcome = switch result.outcome {
            case .chosen(let paths): .chosen(paths)
            case .cancelled: .cancelled
            case .failed(let message): .failed(.platform(message))
            }
            StateDispatch.dispatching(to: record.owner) {
                record.isPresented.wrappedValue = false
                complete(outcome)
            }
        }
    }

    /// An alert's answer, from input (`SV-I` item 4): `isPresented = false`,
    /// then the pressed button's action from the content presented — a
    /// synthesized button, or `nil` (dismissed), runs nothing.
    func handleAlertResult(_ result: AlertResultEvent) {
        guard case .scope(let key, let token, let presented, let content?)? = presentations.inFlight,
              token == result.token else { return }
        presentations.inFlight = nil
        if drawnAlert?.token == token {
            drawnAlert = nil
            setNeedsRedraw()
        }
        let record = presentations.record(for: key) ?? presented
        let action = result.button.flatMap { index in
            content.buttons.indices.contains(index) ? content.buttons[index].action : nil
        }
        StateDispatch.dispatching(to: record.owner) {
            record.isPresented.wrappedValue = false
            action?()
        }
    }

    /// Answers the drawn alert (`SV-J`, `SV-AC`): `index` into its buttons, or
    /// `nil` to dismiss it with no action — what a native platform's
    /// `.alertResult` does. Lane 3's panel calls it from its input stage and
    /// its accessibility press. Nothing when no drawn alert is up.
    func chooseAlertButton(_ index: Int?) {
        guard let alert = drawnAlert else { return }
        handleAlertResult(AlertResultEvent(token: alert.token, button: index))
    }
}

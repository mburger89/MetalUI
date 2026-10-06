import MetalUI
import Observation
import Foundation

/// The platform services demo (ruling `SV-T`; spec
/// `2026-10-04-platform-services-design.md` §7), reached with
/// `METALUI_SERVICES_DEMO=1 swift run MetalUIDemo` (and `MetalUISDLDemo`):
/// file dialogs (Import through `.fileImporter`, Export through
/// `.fileExporter`, an async open through `@Environment(\.fileDialogs)`), a
/// destructive alert, three hover tiles, `Divider`s in all four stacks and a
/// 300-option menu `Picker`. The window opens at 960 × 640 with a 900 × 600
/// minimum (`openServicesDemoWindow`).
///
/// **The human looks** (`docs/verification/human-checks.md` group U): the open
/// and save panels, the alert sheet (AppKit) or the drawn alert (SDL), the
/// hover highlight, the dividers, the native or drawn menu picker, the minimum.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Each section is its own function, passed as an
/// argument to a generic composing function — the Windows stack rule
/// `demoContent()`'s note records; built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func servicesDemoContent() -> some Element {
    servicesRoot(header: servicesHeader(), dialogs: servicesDialogsSection(), alert: servicesAlertSection(),
                 hover: servicesHoverSection(), dividers: servicesDividerSection(),
                 picker: servicesPickerSection())
}

/// A section built when the window lays it out (a `Component`'s content), so
/// the tree `servicesDemoContent()` returns holds one closure per section and
/// not the section's values. **The Windows stack rule**: built eagerly, the
/// tree was 53 KB and the root's modifier chain copies it several times on a
/// debug stack — `everyProductionTreeBuildsOnAOneMegabyteThread` measured
/// `SIGBUS` below 2 MB (`SV-AK`).
struct ServicesPart<Body: ElementGroup>: Component {
    let make: @MainActor () -> Body
    var content: some ElementGroup { make() }
}

/// The services demo window's minimum size (`SV-T`, `SV-L`).
public let servicesDemoMinimumSize = Size(width: Pixels(900), height: Pixels(600))

/// Opens the services demo in `app` at 960 × 640 with its minimum
/// (`servicesDemoMinimumSize`) — what both demos' `main.swift` call.
@MainActor
public func openServicesDemoWindow(_ app: App, title: String, startsDisplayLink: Bool = true) throws -> Window {
    try app.openWindow(title: title, size: Size(width: Pixels(960), height: Pixels(640)),
                       minSize: servicesDemoMinimumSize, startsDisplayLink: startsDisplayLink,
                       content: servicesDemoContent)
}

/// The demo's state.
@MainActor
@Observable
public final class ServicesDemoModel {
    /// The last dialog outcome, as shown.
    public var outcome = "No file chosen yet."
    /// Whether the importer is shown.
    public var importing = false
    /// Whether the exporter is shown.
    public var exporting = false
    /// Whether the delete alert is shown.
    public var confirmingDelete = false
    /// Whether each hover tile is under the pointer.
    public var hovered = [false, false, false]
    /// How often each hover tile was entered.
    public var hoverEnters = [0, 0, 0]
    /// The menu picker's selection.
    public var key = 42

    /// A fresh model.
    public init() {}

    /// Back to a fresh model's values (tests share the one instance).
    public func reset() {
        outcome = "No file chosen yet."
        importing = false
        exporting = false
        confirmingDelete = false
        hovered = [false, false, false]
        hoverEnters = [0, 0, 0]
        key = 42
    }
}

/// The one model the demo reads.
@MainActor public let servicesDemoModel = ServicesDemoModel()

/// The root: the header, the sections in two columns.
@MainActor
func servicesRoot(header: some ElementGroup, dialogs: some ElementGroup, alert: some ElementGroup,
                  hover: some ElementGroup, dividers: some ElementGroup, picker: some ElementGroup) -> some Element {
    Column(gap: Pixels(20)) {
        header
        Row(gap: Pixels(40)) {
            Column(gap: Pixels(20)) {
                dialogs
                alert
                picker
            }
            .alignItems(.flexStart)
            Column(gap: Pixels(20)) {
                hover
                dividers
            }
            .alignItems(.flexStart)
        }
        .alignItems(.flexStart)
        Text(servicesDemoModel.outcome)
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

@MainActor
func servicesHeader() -> some Element {
    Column(gap: Pixels(4)) {
        Text("Platform services").font(size: 22)
        Text("Open and save panels, an alert, hover, dividers and a menu picker. The window stops at 900 × 600.")
    }
    .alignItems(.flexStart)
}

/// Import and Export through the modifiers, and an async open.
@MainActor
func servicesDialogsSection() -> some ElementGroup { ServicesPart { servicesDialogsSectionBody() } }

@MainActor
func servicesDialogsSectionBody() -> some Element {
    Row(gap: Pixels(12)) {
        Button("Import…") { servicesDemoModel.importing = true }
            .fileImporter(isPresented: Binding(get: { servicesDemoModel.importing },
                                               set: { servicesDemoModel.importing = $0 }),
                          allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): servicesDemoModel.outcome = "Imported \(urls.map(\.lastPathComponent))"
                case .failure(let error): servicesDemoModel.outcome = "Import failed: \(error)"
                }
            }
        Button("Export…") { servicesDemoModel.exporting = true }
            .fileExporter(isPresented: Binding(get: { servicesDemoModel.exporting },
                                               set: { servicesDemoModel.exporting = $0 }),
                          item: Data("{\"keymap\": []}\n".utf8), contentTypes: [.json],
                          defaultFilename: "keymap",
                          onCompletion: { result in
                              switch result {
                              case .success(let url): servicesDemoModel.outcome = "Exported \(url.lastPathComponent)"
                              case .failure(let error): servicesDemoModel.outcome = "Export failed: \(error)"
                              }
                          },
                          onCancellation: { servicesDemoModel.outcome = "Export cancelled" })
        ServicesAsyncOpen()
    }
}

/// A button opening files through `@Environment(\.fileDialogs)` from a task.
private struct ServicesAsyncOpen: Component {
    @Environment(\.fileDialogs) var dialogs

    var content: some ElementGroup {
        let dialogs = dialogs
        return Button("Open… (async)") {
            Task { @MainActor in
                do {
                    let urls = try await dialogs.openFiles(allowedContentTypes: [.json])
                    servicesDemoModel.outcome = urls.isEmpty ? "Open cancelled"
                        : "Opened \(urls.map(\.lastPathComponent))"
                } catch {
                    servicesDemoModel.outcome = "Open failed: \(error)"
                }
            }
        }
    }
}

/// A "Delete…" button and its destructive alert with a message.
@MainActor
func servicesAlertSection() -> some ElementGroup {
    ServicesAlertButton()
}

/// The button carrying the alert. **A `Component`, so the alert's actions
/// are evaluated when the window lays it out, not when the tree is built**:
/// the non-presenting `.alert` forms call their builder closures while
/// building (`SV-AH` item 7), and a main-actor closure called off the main
/// thread traps under Swift 6's dynamic isolation check — which
/// `everyProductionTreeBuildsOnAOneMegabyteThread`, building the tree on a
/// secondary thread, measured as `SIGTRAP` (`SV-AK`).
private struct ServicesAlertButton: Component {
    var content: some ElementGroup {
        Button("Delete…") { servicesDemoModel.confirmingDelete = true }
            .alert("Delete keymap?", isPresented: Binding(get: { servicesDemoModel.confirmingDelete },
                                                          set: { servicesDemoModel.confirmingDelete = $0 })) {
                Button("Delete", role: .destructive) { servicesDemoModel.outcome = "Deleted" }
                Button("Cancel", role: .cancel) { servicesDemoModel.outcome = "Kept" }
            } message: {
                Text("This cannot be undone.")
            }
    }
}

/// Three hover tiles: highlighted under the pointer, each counting its enters
/// as text and as a bar 8 points per enter.
@MainActor
func servicesHoverSection() -> some ElementGroup { ServicesPart { servicesHoverSectionBody() } }

@MainActor
func servicesHoverSectionBody() -> some Element {
    servicesHoverRow(servicesHoverTile(0), servicesHoverTile(1), servicesHoverTile(2))
}

/// The three tiles side by side — a composer of its own, so no one builder
/// closure holds three tiles' temporaries (the Windows stack rule).
@MainActor
func servicesHoverRow(_ first: some Element, _ second: some Element, _ third: some Element) -> some Element {
    Row(gap: Pixels(12)) {
        first
        second
        third
    }
    .alignItems(.flexStart)
}

@MainActor
func servicesHoverTile(_ index: Int) -> some Element {
    Column(gap: Pixels(6)) {
        Text("Tile \(index + 1)")
        Text("Enters: \(servicesDemoModel.hoverEnters[index])")
        Box()
            .frame(width: Pixels(Float(8 * servicesDemoModel.hoverEnters[index])), height: Pixels(8))
            .background(.accent)
    }
    .alignItems(.flexStart)
    .padding(Pixels(10))
    .frame(width: Pixels(110), height: Pixels(90), alignment: .topLeading)
    .background(servicesDemoModel.hovered[index] ? .surface : .surfaceSecondary)
    .cornerRadius(Pixels(8))
    .onHover { inside in
        servicesDemoModel.hovered[index] = inside
        if inside { servicesDemoModel.hoverEnters[index] += 1 }
    }
}

/// `Divider` in a `VStack`, an `HStack`, a `Column` and a `Row`.
@MainActor
func servicesDividerSection() -> some ElementGroup { ServicesPart { servicesDividerSectionBody() } }

@MainActor
func servicesDividerSectionBody() -> some Element {
    Row(gap: Pixels(24)) {
        VStack(alignment: .leading) {
            ProposalText("VStack")
            Divider()
            ProposalText("below")
        }
        .frame(width: Pixels(90))
        HStack {
            ProposalText("HStack")
            Divider()
            ProposalText("right")
        }
        .frame(height: Pixels(40))
        Column(gap: Pixels(6)) {
            Text("Column")
            Divider()
            Text("below")
        }
        .frame(width: Pixels(90))
        Row(gap: Pixels(6)) {
            Text("Row")
            Divider()
            Text("right")
        }
        .frame(height: Pixels(40))
    }
    .alignItems(.flexStart)
}

/// A 300-option menu picker and its value.
@MainActor
func servicesPickerSection() -> some ElementGroup { ServicesPart { servicesPickerSectionBody() } }

@MainActor
func servicesPickerSectionBody() -> some Element {
    Row(gap: Pixels(12)) {
        Picker("Key", selection: Binding(get: { servicesDemoModel.key }, set: { servicesDemoModel.key = $0 })) {
            for index in 0..<300 { Text("Key \(index)").tag(index) }
        }
        .pickerStyle(.menu)
        Text("Selected: \(servicesDemoModel.key)")
    }
}

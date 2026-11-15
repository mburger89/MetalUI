import MetalUI
import Observation

/// The outline performance demo (outline lane 8, `OG-O`, record 318), reached with
/// `METALUI_OUTLINE_DEMO=1 swift run MetalUIDemo`: a content `List` over a synthetic project tree of 100 000 paths (8
/// top-level folders of 25 folders of 500 files, the first folder of the first expanded), in Alloy's shape - `@Observable`
/// node classes, a recursive `Component` row holding a `DisclosureGroup(isExpanded:)` - under a toolbar of three buttons: it
/// renames the first file (a model change), adds a file to the first folder (a row appears) and expands every top-level
/// folder.
///
/// **The human look** (group OG of `docs/verification/human-checks.md`): scrolling the 100 000 paths is smooth, a folder
/// opens at once, a rename shows at the next frame, and the window is idle between them (no CPU while nothing moves).
///
/// Nothing here is in the default demo, so the fourteen offscreen images do not move. The builder is its own function (the
/// Windows 1 MB stack rule), built on a 1 MB thread by `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func outlineDemoContent() -> some Element {
    outlineDemoRoot()
}

@MainActor
private func outlineDemoRoot() -> some Element {
    VStack(alignment: .leading, spacing: Pixels(8)) {
        OutlineDemoBar()
        OutlineDemoList()
    }
    .padding(Edges(all: Pixels(12)))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.background)
}

/// One folder or file of the synthetic tree.
@Observable @MainActor
public final class OutlineDemoNode: Identifiable {
    /// The node's path, unique in the tree.
    public nonisolated let id: String
    /// The name shown.
    public var name: String
    /// Whether the node is a folder.
    public var isFolder: Bool
    /// Whether the folder is open.
    public var isExpanded: Bool
    /// The folder's children.
    public var children: [OutlineDemoNode]

    init(_ id: String, name: String, children: [OutlineDemoNode]? = nil, expanded: Bool = false) {
        self.id = id
        self.name = name
        self.isFolder = children != nil
        self.isExpanded = expanded
        self.children = children ?? []
    }
}

/// The demo's tree: 8 x 25 x 500 = 100 000 files.
@Observable @MainActor
public final class OutlineDemoModel {
    /// The top-level folders.
    public var roots: [OutlineDemoNode]
    /// The selected path.
    public var selection: String?

    /// A model of 100 000 paths.
    public init() {
        roots = (0..<8).map { top in
            OutlineDemoNode("t\(top)", name: "module\(top)", children: (0..<25).map { sub in
                OutlineDemoNode("t\(top)/d\(sub)", name: "dir\(sub)", children: (0..<500).map { file in
                    OutlineDemoNode("t\(top)/d\(sub)/f\(file)", name: "file\(file).swift")
                }, expanded: top == 0 && sub == 0)
            }, expanded: top == 0)
        }
    }

    func renameFirstFile() {
        let file = roots[0].children[0].children[0]
        file.name = file.name.hasPrefix("renamed") ? "file0.swift" : "renamed-file0.swift"
    }

    func addFile() {
        let folder = roots[0].children[0]
        folder.children.insert(OutlineDemoNode("t0/d0/new\(folder.children.count)", name: "new file \(folder.children.count)"), at: 0)
    }

    func expandTopLevel() {
        for root in roots { root.isExpanded = true }
    }
}

/// The model the demo's list and buttons share.
@MainActor public let outlineDemoModel = OutlineDemoModel()

struct OutlineDemoBar: Component {
    var content: some ElementGroup {
        let model = outlineDemoModel
        return HStack(spacing: Pixels(8)) {
            Button("Rename first file") { model.renameFirstFile() }
            Button("Add a file") { model.addFile() }
            Button("Expand top level") { model.expandTopLevel() }
            ProposalText("100 000 paths")
        }
    }
}

struct OutlineDemoList: Component {
    var content: some ElementGroup {
        let model = outlineDemoModel
        let selection = Binding<String?>(get: { model.selection }, set: { model.selection = $0 })
        return List(selection: selection) {
            ForEach(model.roots) { OutlineDemoRow(node: $0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OutlineDemoRow: Component {
    @Bindable var node: OutlineDemoNode

    @ElementBuilder var content: some ElementGroup {
        if node.isFolder {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                ForEach(node.children) { OutlineDemoRow(node: $0) }
            } label: { ProposalText(node.name) }
        } else {
            ProposalText(node.name)
        }
    }
}

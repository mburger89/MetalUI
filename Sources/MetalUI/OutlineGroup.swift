import MetalUICore
import MetalUILayout

/// SwiftUI's `OutlineGroup` (lane 3 of the hierarchical lists, rulings `OG-A`, `OG-B`, `OG-D`, `OG-K`; probe
/// `docs/probes/swiftui-outline.swift`, arms `P-E5`, `P-I1`, `P-L2`): a tree of rows built from a recursive data
/// structure, one `DisclosureGroup` per element that has children.
///
/// ```swift
/// OutlineGroup(files, children: \.children) { file in      // Identifiable elements
///     Text(file.name)
/// }
/// OutlineGroup(root, id: \.path, children: \.children) { node in Text(node.name) }
/// ```
///
/// **Leaf or group.** An element whose `children` key path reads `nil` is a leaf: its row is `content(element)`.
/// An element whose `children` is non-nil, **even empty**, is a group: a disclosure whose label is
/// `content(element)` and whose content is the outline of those children. The key path is read once per visible
/// row (to tell the two apart), and the contents of a **collapsed** group are never read: `.count` and the elements
/// are read only for expanded groups.
///
/// **Expansion is uncontrolled** and collapsed initially: there is no expansion binding, as in SwiftUI. Each group
/// keeps its own state slot at its identity, so **collapsing an ancestor keeps its descendants' expansion**: collapse
/// A, re-expand it, and A/B is still expanded (probe `P-E5`). An element dropped from its parent's `children` loses
/// its expansion (it returns collapsed), and **moving an element to another parent gives it a new identity**
/// (`P-I1`, `OG-B`). **Ids must be unique across the whole tree**: a row's identity, scroll target and index key are
/// its element's id nested under its ancestors', and a duplicate id inside one level realises only its first.
///
/// **In a lazy stack** (`LazyVStack` in a scroller) the outline is lazy: only the rows in the window are built, and
/// the flattened rows live in an `OutlineIndex` that is rebuilt only when an
/// expansion changes or the data no longer matches it, and checked each frame in `O(expanded groups + window)`.
/// Expanding a group of 10 000 children rebuilds once that frame and never again while it stays expanded. In an
/// eager stack (`VStack`) the outline is the nested `DisclosureGroup`s it stands for, every expanded row built.
/// The two forms give the same element ids, so the same tree keeps its `@State` moved between the stacks.
///
/// **Look** (outside a `List`, whose chrome is a later lane): a group row is lane 1's `DisclosureGroup` row (a 24
/// point row, the chevron slot then the label at +12, no indentation of the children); **a leaf is its content as
/// written, with no chevron slot reserved** (`P-L2` measured the reserved slot inside a `List`; an outline in a plain
/// stack was not probed, so this mirrors `DisclosureGroup`, which has no leaf). A row's `content` is one unit in
/// a lazy stack: content of several members is laid out as one unit.
///
/// Not offered: the `Binding` forms (`OutlineGroup(_:children:content:)` over `Binding<Data>`, class `R`) and a
/// `Subgroup` other than `DisclosureGroup<Parent, OutlineSubgroupChildren>`.
public struct OutlineGroup<Data: RandomAccessCollection, ID: Hashable, Parent, Leaf, Subgroup> {
    let roots: OutlineRoots<Data>
    let spec: OutlineSpec<Data, ID, Leaf>

    init(roots: OutlineRoots<Data>, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>,
         content: @escaping (Data.Element) -> Leaf) {
        self.roots = roots
        self.spec = OutlineSpec(id: id, children: children, content: content)
    }
}

extension OutlineGroup where ID == Data.Element.ID, Parent: ElementGroup, Parent == Leaf,
                             Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren>, Data.Element: Identifiable {
    /// An outline of the tree below `root`, its elements identified by their `id`: SwiftUI's
    /// `OutlineGroup(_:children:content:)` over a root element. `root` is the one top row; `children` reads each
    /// element's children, `nil` for a leaf.
    public init<DataElement>(_ root: DataElement, children: KeyPath<DataElement, Data?>,
                             @ElementBuilder content: @escaping (DataElement) -> Leaf)
        where ID == DataElement.ID, DataElement: Identifiable, DataElement == Data.Element {
        self.init(roots: OutlineRoots(root: root), id: \DataElement.id, children: children, content: content)
    }

    /// An outline of the trees in `data`, its elements identified by their `id`: SwiftUI's
    /// `OutlineGroup(_:children:content:)` over a collection of roots.
    public init<DataElement>(_ data: Data, children: KeyPath<DataElement, Data?>,
                             @ElementBuilder content: @escaping (DataElement) -> Leaf)
        where ID == DataElement.ID, DataElement: Identifiable, DataElement == Data.Element {
        self.init(roots: OutlineRoots(collection: data), id: \DataElement.id, children: children, content: content)
    }
}

extension OutlineGroup where Parent: ElementGroup, Parent == Leaf,
                             Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    /// An outline of the tree below `root`, its elements identified by `id`: SwiftUI's
    /// `OutlineGroup(_:id:children:content:)` over a root element.
    public init<DataElement>(_ root: DataElement, id: KeyPath<DataElement, ID>, children: KeyPath<DataElement, Data?>,
                             @ElementBuilder content: @escaping (DataElement) -> Leaf)
        where DataElement == Data.Element {
        self.init(roots: OutlineRoots(root: root), id: id, children: children, content: content)
    }

    /// An outline of the trees in `data`, its elements identified by `id`: SwiftUI's
    /// `OutlineGroup(_:id:children:content:)` over a collection of roots.
    public init<DataElement>(_ data: Data, id: KeyPath<DataElement, ID>, children: KeyPath<DataElement, Data?>,
                             @ElementBuilder content: @escaping (DataElement) -> Leaf)
        where DataElement == Data.Element {
        self.init(roots: OutlineRoots(collection: data), id: id, children: children, content: content)
    }
}

extension OutlineGroup: ElementGroup
    where Parent: ElementGroup, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    @MainActor func makeBody() -> OutlineGroupBody<Data, ID, Leaf> { OutlineGroupBody(roots: roots, spec: spec) }

    public typealias GroupLayout = ComponentLayout<OutlineGroupBody<Data, ID, Leaf>>
    public typealias GroupPrepaint = ComponentPrepaint<OutlineGroupBody<Data, ID, Leaf>>

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], ComponentLayout<OutlineGroupBody<Data, ID, Leaf>>) {
        var body = makeBody()
        return body.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    public mutating func prepaintGroup(layout: inout ComponentLayout<OutlineGroupBody<Data, ID, Leaf>>,
                                       pass: inout PrepaintPass)
        -> ComponentPrepaint<OutlineGroupBody<Data, ID, Leaf>> {
        var body = makeBody()
        return body.prepaintGroup(layout: &layout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout ComponentLayout<OutlineGroupBody<Data, ID, Leaf>>,
                                    prepaint: inout ComponentPrepaint<OutlineGroupBody<Data, ID, Leaf>>,
                                    pass: inout PaintPass) {
        var body = makeBody()
        body.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// The placeholder type SwiftUI's `OutlineGroup` names in its `Subgroup`
/// (`DisclosureGroup<Parent, OutlineSubgroupChildren>`): it draws nothing. MetalUI-only in the sense that SwiftUI's is
/// opaque and never constructed by an app (class `M`); it exists so the generic signature spells as SwiftUI's does.
public struct OutlineSubgroupChildren: Component {
    /// A placeholder; apps never need one.
    public init() {}

    /// Nothing.
    public var content: some ElementGroup { EmptyGroup() }
}

// MARK: internals

/// What an outline reads its tree through: the key paths and the row builder.
struct OutlineSpec<Data: RandomAccessCollection, ID: Hashable, Leaf> {
    let id: KeyPath<Data.Element, ID>
    let children: KeyPath<Data.Element, Data?>
    let content: (Data.Element) -> Leaf
}

/// A level of an outline as a random-access collection of `Int` positions: the roots (a collection, or the one root
/// element) or one group's children, so the index and the eager body read every level the same way.
struct OutlineRoots<Data: RandomAccessCollection>: RandomAccessCollection {
    enum Storage {
        case collection(Data)
        case single(Data.Element)
    }
    let storage: Storage

    init(collection: Data) { storage = .collection(collection) }
    init(root: Data.Element) { storage = .single(root) }

    var startIndex: Int { 0 }
    var endIndex: Int {
        switch storage {
        case .collection(let data): return data.count
        case .single: return 1
        }
    }

    subscript(position: Int) -> Data.Element {
        switch storage {
        case .collection(let data): return data[data.index(data.startIndex, offsetBy: position)]
        case .single(let element): return element
        }
    }
}

/// What `OutlineGroup` builds: its identity level (so its `OutlineIndex` slot lives at the group's id) over one
/// `ForEach` of the roots, each an `OutlineNode`. The eager form of the outline: a lazy stack reads the group's
/// `lazyTreeFlatten` instead (`OG-K`). Internal; `public` only because the group's `GroupLayout` names it.
public struct OutlineGroupBody<Data: RandomAccessCollection, ID: Hashable, Leaf: ElementGroup>: Component {
    let roots: OutlineRoots<Data>
    let spec: OutlineSpec<Data, ID, Leaf>
    /// The index a lazy stack keeps here between frames; unused by the eager form.
    @State private var storedIndex = OutlineIndex<Data, ID>()

    init(roots: OutlineRoots<Data>, spec: OutlineSpec<Data, ID, Leaf>) {
        self.roots = roots
        self.spec = spec
    }

    var index: OutlineIndex<Data, ID> { storedIndex }

    /// The outline: a `ForEach` of the roots, under the group's own id.
    @ElementBuilder public var content: some ElementGroup {
        ForEach(roots, id: spec.id) { OutlineNode(element: $0, spec: spec) }
    }
}

/// One element: a leaf's content, or a `DisclosureGroup` over its children. Its structure is what the lazy path
/// reproduces without evaluating it (`OutlineScopes`): a `Component` level, an `if`/`else`, and for a group the
/// disclosure's own levels.
struct OutlineNode<Data: RandomAccessCollection, ID: Hashable, Leaf: ElementGroup>: Component {
    let element: Data.Element
    let spec: OutlineSpec<Data, ID, Leaf>

    @ElementBuilder var content: some ElementGroup {
        if let kids = element[keyPath: spec.children] {
            subgroup(kids)
        } else {
            spec.content(element)
        }
    }

    /// The group row, its descendants keeping their expansion while it is collapsed (`OG-D`).
    private func subgroup(_ kids: Data) -> DisclosureGroup<Leaf, ForEach<Data, ID, OutlineNode<Data, ID, Leaf>>> {
        let spec = self.spec
        var group = DisclosureGroup(expansion: nil, label: spec.content(element), content: {
            ForEach(kids, id: spec.id) { OutlineNode(element: $0, spec: spec) }
        })
        group.inner.keepsHiddenState = true
        return group
    }
}

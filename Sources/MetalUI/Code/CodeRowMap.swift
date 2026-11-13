import MetalUICodeBuffer

// The row map of a `CodeView` (`CV-S`): the one place a display row becomes a buffer row or a read-only
// virtual line. A treap over *gaps*: a node is a group of virtual lines anchored before a buffer row; the
// subtree sums the buffer rows between gaps (`extent`) and the virtual lines (`height`), so
// display-row <-> buffer-row and a shift by an edit are O(log n) in the number of groups, never an array
// move. Same shape and same counter as `RunTree` (`RunTreeStats.nodesVisited`).

/// One line of a virtual group, ready to shape and paint.
struct VirtualLine {
    let text: String
    let bytes: [UInt8]
    /// `codeHash(bytes)`, computed once.
    let hash: UInt64
    /// The foreground partition and the run backgrounds (offsets from the line's start).
    let styling: CodeDecorations.LineStyling
    let marker: CodeGutterMarker?
}

/// A group of read-only lines between two buffer rows (`CodeVirtualRow`, resolved).
final class VirtualGroup {
    let lines: [VirtualLine]
    let gutterBar: Color?
    let background: Color?
    /// The app's tag (`CodeVirtualRow.tag`).
    let tag: UInt64?
    /// Whether the group was given `.after(line:)`: its anchor line is the buffer row above the gap, not below it.
    let anchoredAfter: Bool
    /// The owner that gave the group (`CodeDecorations`' owner table; 0 is the default owner) and its priority then
    /// (`CV-AO`): groups at one gap sit in ascending priority.
    let owner: UInt16
    let priority: Int
    init(lines: [VirtualLine], gutterBar: Color?, background: Color?, tag: UInt64? = nil, anchoredAfter: Bool = false,
         owner: UInt16 = 0, priority: Int = 0) {
        self.owner = owner
        self.priority = priority
        self.lines = lines
        self.gutterBar = gutterBar
        self.background = background
        self.tag = tag
        self.anchoredAfter = anchoredAfter
    }
}

final class RowMapNode {
    var left: RowMapNode?
    var right: RowMapNode?
    let priority: UInt32
    /// Buffer rows between the previous gap and this one.
    var extent: Int
    let group: VirtualGroup
    let height: Int
    var totalExtent: Int
    var totalHeight: Int
    var count = 1

    init(extent: Int, group: VirtualGroup, priority: UInt32) {
        self.extent = extent
        self.group = group
        self.height = group.lines.count
        self.priority = priority
        self.totalExtent = extent
        self.totalHeight = group.lines.count
    }

    func update() {
        totalExtent = extent + (left?.totalExtent ?? 0) + (right?.totalExtent ?? 0)
        totalHeight = height + (left?.totalHeight ?? 0) + (right?.totalHeight ?? 0)
        count = 1 + (left?.count ?? 0) + (right?.count ?? 0)
    }
}

/// Display rows in order: every buffer row, and the virtual lines of each gap before the buffer row it is
/// anchored to. A gap at position `p` sits before buffer row `p` (`p == rowCount`: after the last row).
final class CodeRowMap {
    enum Row {
        case buffer(Int)
        /// Line `line` of `group`; `gap` is the buffer row the group sits before.
        case virtual(group: VirtualGroup, line: Int, gap: Int)
    }

    private var root: RowMapNode?
    private var seed: UInt32 = 0x85EB_CA6B
    /// The buffer rows.
    private(set) var rowCount: Int

    init(rowCount: Int) { self.rowCount = rowCount }

    /// The virtual lines in all.
    var virtualCount: Int { root?.totalHeight ?? 0 }
    /// Display rows: buffer rows and virtual lines.
    var displayRowCount: Int { rowCount + virtualCount }
    /// The groups.
    var groupCount: Int { root?.count ?? 0 }

    private func nextPriority() -> UInt32 {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return seed
    }

    // MARK: Queries

    /// The display row of buffer row `row`: the row plus every virtual line in a gap at or before it.
    func displayRow(ofBufferRow row: Int) -> Int {
        var node = root
        var base = 0, heights = 0
        while let n = node {
            RunTreeStats.nodesVisited += 1
            let position = base + (n.left?.totalExtent ?? 0) + n.extent
            if position <= row {
                heights += (n.left?.totalHeight ?? 0) + n.height
                base = position
                node = n.right
            } else {
                node = n.left
            }
        }
        return row + heights
    }

    /// What display row `display` shows.
    func row(atDisplay display: Int) -> Row {
        var node = root
        var base = 0, baseHeight = 0
        while let n = node {
            RunTreeStats.nodesVisited += 1
            let leftExtent = n.left?.totalExtent ?? 0, leftHeight = n.left?.totalHeight ?? 0
            let position = base + leftExtent + n.extent
            let before = baseHeight + leftHeight           // virtual lines in the gaps before this one
            let virtualStart = position + before
            if display < base + leftExtent + before {      // inside the left subtree's span
                node = n.left
                continue
            }
            if display < virtualStart { return .buffer(display - before) }
            if display < virtualStart + n.height {
                return .virtual(group: n.group, line: display - virtualStart, gap: position)
            }
            baseHeight = before + n.height
            base = position
            node = n.right
        }
        return .buffer(display - baseHeight)
    }

    // MARK: Building and following edits

    /// Replaces everything with `groups` (each at a gap position, in order) over `rowCount` rows.
    func build(rowCount: Int, groups: [(position: Int, group: VirtualGroup)]) {
        self.rowCount = rowCount
        root = nil
        var previous = 0
        // O(groups), not O(groups log): a Cartesian tree over the random priorities by one pass with a stack (`CV-AO`).
        var stack: [RowMapNode] = []
        for entry in groups where !entry.group.lines.isEmpty {
            let position = min(max(entry.position, previous), rowCount)
            RunTreeStats.nodesVisited += 1
            let node = RowMapNode(extent: position - previous, group: entry.group, priority: nextPriority())
            var popped: RowMapNode?
            while let top = stack.last, top.priority < node.priority { popped = stack.removeLast() }
            node.left = popped
            stack.last?.right = node
            stack.append(node)
            previous = position
        }
        func fix(_ node: RowMapNode?) {
            guard let node else { return }
            fix(node.left)
            fix(node.right)
            node.update()
        }
        root = stack.first
        fix(root)
    }

    /// Every group with its gap position, in display order: O(groups).
    func allGroups() -> [(position: Int, group: VirtualGroup)] {
        var out: [(position: Int, group: VirtualGroup)] = []
        func visit(_ node: RowMapNode?, base: Int) {
            guard let n = node else { return }
            RunTreeStats.nodesVisited += 1
            visit(n.left, base: base)
            let position = base + (n.left?.totalExtent ?? 0) + n.extent
            out.append((position, n.group))
            visit(n.right, base: position)
        }
        visit(root, base: 0)
        return out
    }

    /// No groups over `rowCount` rows.
    func reset(rowCount: Int) {
        self.rowCount = rowCount
        root = nil
    }

    /// An edit replaced `removing` buffer rows after `position - 1` with `inserting` new ones (rows
    /// `position..<position + removing` go). A gap at `position` or before stays; a gap strictly inside the
    /// removed rows is dropped with them; later gaps move by the difference.
    func splice(at position: Int, removing removed: Int, inserting added: Int) {
        guard removed > 0 || added > 0 else { return }
        let (left, rest) = split(root, base: 0, at: position)
        var right = rest
        if removed > 0 {
            let leftExtent = left?.totalExtent ?? 0
            let (middle, tail) = split(rest, base: leftExtent, at: position + removed - 1)
            right = tail
            if let tail = right { bump(tail, by: (middle?.totalExtent ?? 0) - removed) }
            rowCount -= removed
        }
        if added > 0 {
            if let first = right { bump(first, by: added) }
            rowCount += added
        }
        root = merge(left, right)
    }

    // MARK: Treap

    /// The nodes whose gap position is at most `position`, and the rest.
    private func split(_ node: RowMapNode?, base: Int, at position: Int) -> (RowMapNode?, RowMapNode?) {
        guard let n = node else { return (nil, nil) }
        RunTreeStats.nodesVisited += 1
        let here = base + (n.left?.totalExtent ?? 0) + n.extent
        if here <= position {
            let (a, b) = split(n.right, base: here, at: position)
            n.right = a
            n.update()
            return (n, b)
        }
        let (a, b) = split(n.left, base: base, at: position)
        n.left = b
        n.update()
        return (a, n)
    }

    private func merge(_ a: RowMapNode?, _ b: RowMapNode?) -> RowMapNode? {
        guard let a else { return b }
        guard let b else { return a }
        RunTreeStats.nodesVisited += 1
        if a.priority >= b.priority {
            a.right = merge(a.right, b)
            a.update()
            return a
        }
        b.left = merge(a, b.left)
        b.update()
        return b
    }

    /// Adds `delta` to the extent of the first node of the subtree.
    private func bump(_ node: RowMapNode, by delta: Int) {
        RunTreeStats.nodesVisited += 1
        if let left = node.left { bump(left, by: delta) } else { node.extent += delta }
        node.update()
    }
}

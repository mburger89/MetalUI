// A sequence of runs addressed by position in O(log n) (`CV-K`): the store under
// `CodeDecorations`' highlight layers (positions are UTF-8 bytes) and line decorations
// (positions are rows). Every run has an extent and a payload; the runs tile `0..<total`
// with no gaps. A treap keyed implicitly by the running extent, so a splice at one
// position costs O(log n) in the number of runs, never an array move.

/// Node-visit counter for the decoration pins (`CV-K`): one increment per node an operation
/// enters. A plain counter; only meaningful in a single-threaded test.
package enum RunTreeStats {
    nonisolated(unsafe) package static var nodesVisited = 0
}

final class RunNode<Payload> {
    var left: RunNode?
    var right: RunNode?
    let priority: UInt32
    var extent: Int
    var payload: Payload
    /// The extent of this subtree.
    var total: Int
    /// The runs in this subtree.
    var count = 1

    init(extent: Int, payload: Payload, priority: UInt32) {
        self.extent = extent
        self.payload = payload
        self.priority = priority
        self.total = extent
    }

    func update() {
        total = extent + (left?.total ?? 0) + (right?.total ?? 0)
        count = 1 + (left?.count ?? 0) + (right?.count ?? 0)
    }
}

/// A tiling of `0..<total` by runs. A reference type owned by one decorations object.
final class RunTree<Payload> {
    private var root: RunNode<Payload>?
    private var seed: UInt32 = 0x9E37_79B9

    init(total: Int, payload: Payload) {
        if total > 0 { root = RunNode(extent: total, payload: payload, priority: nextPriority()) }
    }

    /// A tree of exactly `runs` (zero extents skipped, equal neighbours not joined), built in O(runs) with no
    /// split or merge (`CV-AO`): a Cartesian tree over the random priorities, by one pass with a stack.
    init(tiling runs: [(extent: Int, payload: Payload)]) {
        var stack: [RunNode<Payload>] = []
        for run in runs where run.extent > 0 {
            RunTreeStats.nodesVisited += 1
            let node = RunNode(extent: run.extent, payload: run.payload, priority: nextPriority())
            var popped: RunNode<Payload>?
            while let top = stack.last, top.priority < node.priority { popped = stack.removeLast() }
            node.left = popped
            stack.last?.right = node
            stack.append(node)
        }
        func fix(_ node: RunNode<Payload>?) {
            guard let node else { return }
            fix(node.left)
            fix(node.right)
            node.update()
        }
        root = stack.first
        fix(root)
    }

    /// The total extent.
    var total: Int { root?.total ?? 0 }
    /// The number of runs.
    var runCount: Int { root?.count ?? 0 }

    private func nextPriority() -> UInt32 {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return seed
    }

    // MARK: Split and merge

    /// Splits `node` into the runs before `position` and the runs from it; a run that straddles is cut.
    private func split(_ node: RunNode<Payload>?, at position: Int) -> (RunNode<Payload>?, RunNode<Payload>?) {
        guard let node else { return (nil, nil) }
        RunTreeStats.nodesVisited += 1
        let leftTotal = node.left?.total ?? 0
        if position <= leftTotal {
            let (a, b) = split(node.left, at: position)
            node.left = b
            node.update()
            return (a, node)
        }
        if position >= leftTotal + node.extent {
            let (a, b) = split(node.right, at: position - leftTotal - node.extent)
            node.right = a
            node.update()
            return (node, b)
        }
        // The cut falls inside this run: it becomes two.
        let inside = position - leftTotal
        let tail = RunNode(extent: node.extent - inside, payload: node.payload, priority: nextPriority())
        tail.right = node.right
        tail.update()
        node.extent = inside
        node.right = nil
        node.update()
        return (node, tail)
    }

    private func merge(_ a: RunNode<Payload>?, _ b: RunNode<Payload>?) -> RunNode<Payload>? {
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

    // MARK: Editing

    /// Replaces `range` with one run of `extent` and `payload` (none when `extent` is 0). The positions
    /// after the range move by `extent - range.count`.
    func replace(_ range: Range<Int>, withExtent extent: Int, payload: Payload) {
        precondition(range.lowerBound >= 0 && range.upperBound <= total, "RunTree: range out of bounds")
        let (left, rest) = split(root, at: range.lowerBound)
        let (_, right) = split(rest, at: range.count)
        var middle: RunNode<Payload>?
        if extent > 0 { middle = RunNode(extent: extent, payload: payload, priority: nextPriority()) }
        root = merge(merge(left, middle), right)
    }

    /// Sets the payload of `range` (the extent is unchanged).
    func set(_ range: Range<Int>, to payload: Payload) {
        guard !range.isEmpty else { return }
        replace(range, withExtent: range.count, payload: payload)
    }

    /// Grows (or shrinks) at `position`: `removed` positions are cut and `added` inserted, the inserted
    /// extent taking the payload of the run it lands in (an insertion takes the run before it, `CV-K`).
    func splice(at position: Int, removing removed: Int, inserting added: Int, empty: Payload) {
        guard removed > 0 || added > 0 else { return }
        let source = removed == 0 && position > 0 ? position - 1 : position
        let payload = self.payload(at: source) ?? self.payload(at: total - 1) ?? empty
        replace(position..<(position + removed), withExtent: added, payload: payload)
    }

    /// Replaces everything with one run.
    func reset(total: Int, payload: Payload) {
        root = total > 0 ? RunNode(extent: total, payload: payload, priority: nextPriority()) : nil
    }

    // MARK: Reading

    /// The payload of the run holding `position`, `nil` outside `0..<total`.
    func payload(at position: Int) -> Payload? {
        var node = root
        var p = position
        guard p >= 0, p < total else { return nil }
        while let current = node {
            RunTreeStats.nodesVisited += 1
            let leftTotal = current.left?.total ?? 0
            if p < leftTotal {
                node = current.left
            } else if p < leftTotal + current.extent {
                return current.payload
            } else {
                p -= leftTotal + current.extent
                node = current.right
            }
        }
        return nil
    }

    /// The runs intersecting `range`, clipped to it, in order.
    func runs(in range: Range<Int>) -> [(range: Range<Int>, payload: Payload)] {
        var result: [(range: Range<Int>, payload: Payload)] = []
        guard !range.isEmpty else { return result }
        func visit(_ node: RunNode<Payload>?, base: Int) {
            guard let node else { return }
            RunTreeStats.nodesVisited += 1
            if base >= range.upperBound || base + node.total <= range.lowerBound { return }
            let leftTotal = node.left?.total ?? 0
            visit(node.left, base: base)
            let start = base + leftTotal, end = start + node.extent
            let lo = max(start, range.lowerBound), hi = min(end, range.upperBound)
            if lo < hi { result.append((lo..<hi, node.payload)) }
            visit(node.right, base: end)
        }
        visit(root, base: 0)
        return result
    }

    /// Every run, in order.
    var allRuns: [(range: Range<Int>, payload: Payload)] { runs(in: 0..<total) }
}

@inline(__always) func isContinuation(_ b: UInt8) -> Bool { b & 0xC0 == 0x80 }

/// A B-tree node. A leaf (`height == 0`) holds chunks, an inner node holds children of the height below.
///
/// A node reachable from a snapshot is never mutated: every mutation goes through `Rope.unique(_:)`,
/// which copies a shared node first (`CV-B`). That makes the class safe to hand to another thread.
final class Node: @unchecked Sendable {
    let height: Int
    var chunks: ContiguousArray<Chunk>
    var children: ContiguousArray<Node>
    var summary = Summary.zero

    init(chunks: ContiguousArray<Chunk>) {
        height = 0
        self.chunks = chunks
        children = []
        recompute()
    }

    init(height: Int, children: ContiguousArray<Node>) {
        self.height = height
        chunks = []
        self.children = children
        recompute()
    }

    var count: Int { height == 0 ? chunks.count : children.count }

    func recompute() {
        var s = Summary.zero
        if height == 0 { for c in chunks { s.append(c.summary) } } else { for c in children { s.append(c.summary) } }
        summary = s
    }

    func shallowCopy() -> Node {
        height == 0 ? Node(chunks: chunks) : Node(height: height, children: children)
    }
}

/// A persistent B-tree over UTF-8 chunks (`CV-B`). A `Rope` is a value: copying one is O(1) and the copy
/// is unaffected by later edits of the original, because a mutation copies the nodes it would change
/// while another value still references them.
struct Rope: Sendable {
    /// No chunk is longer than this; one is split before it grows past it.
    static let maxChunk = 768
    /// A built or split chunk aims at this many bytes.
    static let targetChunk = 512
    /// Two neighbouring chunks that fit in this many bytes are merged after a deletion.
    static let mergeLimit = 512
    /// A node holds at most this many entries; one that grows past it splits.
    static let maxEntries = 16
    /// A split or a build fills nodes to about this many entries.
    static let fillEntries = 12

    var root: Node

    init() { root = Node(chunks: []) }

    /// Builds a rope from bytes in one pass: O(n), no per-line objects.
    init(bytes: UnsafeBufferPointer<UInt8>) {
        let chunks = Rope.chunkify(bytes)
        if chunks.isEmpty { root = Node(chunks: []); return }
        var level: [Node] = Rope.distribute(chunks.count).map { Node(chunks: ContiguousArray(chunks[$0])) }
        var created = level.count
        while level.count > 1 { level = Rope.groupParents(level); created += level.count }
        RopeStats.nodesVisited += created
        root = level[0]
    }

    var summary: Summary { root.summary }
    var height: Int { root.height }

    // MARK: Chunking

    /// Cuts bytes into chunks: one when they fit, otherwise about `targetChunk` each, never inside a
    /// scalar and never between the `\r` and `\n` of a CRLF.
    static func chunkify(_ p: UnsafeBufferPointer<UInt8>) -> [Chunk] {
        let n = p.count
        if n == 0 { return [] }
        if n <= maxChunk { return [Chunk(ContiguousArray(p))] }
        let k = (n + targetChunk - 1) / targetChunk
        var cuts = [0]
        for i in 1..<k {
            var b = n * i / k
            while b < n && (isContinuation(p[b]) || (p[b] == 0x0A && b > 0 && p[b - 1] == 0x0D)) { b += 1 }
            if b > cuts[cuts.count - 1] && b < n { cuts.append(b) }
        }
        cuts.append(n)
        return (0..<cuts.count - 1).map { Chunk(ContiguousArray(UnsafeBufferPointer(rebasing: p[cuts[$0]..<cuts[$0 + 1]]))) }
    }

    /// Index ranges that split `n` entries into groups of about `fillEntries`.
    static func distribute(_ n: Int) -> [Range<Int>] {
        let g = (n + fillEntries - 1) / fillEntries
        return (0..<g).map { (n * $0 / g)..<(n * ($0 + 1) / g) }
    }

    static func groupParents(_ nodes: [Node]) -> [Node] {
        distribute(nodes.count).map { Node(height: nodes[0].height + 1, children: ContiguousArray(nodes[$0])) }
    }

    @inline(__always) static func unique(_ node: inout Node) {
        if !isKnownUniquelyReferenced(&node) { node = node.shallowCopy() }
    }

    // MARK: Queries

    /// The summary of the first `p` bytes. `p` must be on a scalar boundary.
    func prefix(utf8 p: Int) -> Summary {
        if p <= 0 { return .zero }
        var node = root
        var acc = Summary.zero
        var rem = p
        while true {
            RopeStats.visit()
            if node.height == 0 {
                for ch in node.chunks {
                    if rem >= ch.count {
                        acc.append(ch.summary)
                        rem -= ch.count
                        if rem == 0 { return acc }
                    } else {
                        acc.append(Summary.of(ch.bytes, upTo: rem))
                        return acc
                    }
                }
                return acc
            }
            var next: Node?
            for c in node.children {
                if rem >= c.summary.utf8 {
                    acc.append(c.summary)
                    rem -= c.summary.utf8
                    if rem == 0 { return acc }
                } else { next = c; break }
            }
            guard let n = next else { return acc }
            node = n
        }
    }

    /// The byte offset of the `s`-th scalar (the end of the text when `s` is the scalar count).
    func utf8Offset(ofScalar s: Int) -> Int {
        if s <= 0 { return 0 }
        var node = root
        var acc = 0
        var rem = s
        while true {
            RopeStats.visit()
            if node.height == 0 {
                for ch in node.chunks {
                    if rem >= Int(ch.compact.scalars) {
                        rem -= Int(ch.compact.scalars)
                        acc += ch.count
                    } else {
                        // One pass over the chunk's bytes through a buffer pointer and a `while` loop: the
                        // `for i in 0..<n where …` spelling over `ch.bytes[i]` allocated once per byte (found by
                        // the `CodeView` allocation pin, `CV-Q`: 511 allocations for one `lineStart`).
                        let found: Int? = ch.bytes.withUnsafeBufferPointer { bytes in
                            var seen = 0
                            var i = 0
                            while i < bytes.count {
                                if !isContinuation(bytes[i]) {
                                    if seen == rem { return i }
                                    seen += 1
                                }
                                i += 1
                            }
                            return nil
                        }
                        return acc + (found ?? ch.count)
                    }
                }
                return acc
            }
            var next: Node?
            for c in node.children {
                if rem >= c.summary.scalars { rem -= c.summary.scalars; acc += c.summary.utf8 } else { next = c; break }
            }
            guard let n = next else { return acc }
            node = n
        }
    }

    /// The byte offset of the scalar holding UTF-16 unit `u`; a unit inside a surrogate pair rounds down.
    func utf8Offset(ofUTF16 u: Int) -> Int {
        if u <= 0 { return 0 }
        var node = root
        var acc = 0
        var rem = u
        while true {
            RopeStats.visit()
            if node.height == 0 {
                for ch in node.chunks {
                    if rem >= Int(ch.compact.utf16) {
                        rem -= Int(ch.compact.utf16)
                        acc += ch.count
                    } else {
                        let found: Int? = ch.bytes.withUnsafeBufferPointer { bytes in
                            var seen = 0
                            var i = 0
                            while i < bytes.count {
                                if !isContinuation(bytes[i]) {
                                    let units = bytes[i] >= 0xF0 ? 2 : 1
                                    if seen + units > rem { return i }
                                    seen += units
                                }
                                i += 1
                            }
                            return nil
                        }
                        return acc + (found ?? ch.count)
                    }
                }
                return acc
            }
            var next: Node?
            for c in node.children {
                if rem >= c.summary.utf16 { rem -= c.summary.utf16; acc += c.summary.utf8 } else { next = c; break }
            }
            guard let n = next else { return acc }
            node = n
        }
    }

    /// The byte offset where line `row` starts; the text's end when `row` is past the last line.
    func lineStart(row r: Int) -> Int {
        if r <= 0 { return 0 }
        var node = root
        var acc = 0
        var rem = r
        while true {
            RopeStats.visit()
            if node.height == 0 {
                for ch in node.chunks {
                    if Int(ch.compact.newlines) < rem {
                        rem -= Int(ch.compact.newlines)
                        acc += ch.count
                    } else {
                        let found: Int? = ch.bytes.withUnsafeBufferPointer { bytes in
                            var seen = 0
                            var i = 0
                            while i < bytes.count {
                                if bytes[i] == 0x0A {
                                    seen += 1
                                    if seen == rem { return i + 1 }
                                }
                                i += 1
                            }
                            return nil
                        }
                        if let found { return acc + found }
                    }
                }
                return acc
            }
            var next: Node?
            for c in node.children {
                if c.summary.newlines < rem { rem -= c.summary.newlines; acc += c.summary.utf8 } else { next = c; break }
            }
            guard let n = next else { return acc }
            node = n
        }
    }

    /// The byte at `offset`, which must be below the byte count.
    func byte(at offset: Int) -> UInt8 {
        var node = root
        var rem = offset
        while true {
            RopeStats.visit()
            if node.height == 0 {
                for ch in node.chunks {
                    if rem < ch.count { return ch.bytes[rem] }
                    rem -= ch.count
                }
                preconditionFailure("byte offset out of range")
            }
            var next: Node?
            for c in node.children {
                if rem < c.summary.utf8 { next = c; break }
                rem -= c.summary.utf8
            }
            guard let n = next else { preconditionFailure("byte offset out of range") }
            node = n
        }
    }

    /// Whether some chunk starts exactly at `offset` (which is below the byte count, above 0).
    func isChunkStart(_ offset: Int) -> Bool {
        var node = root
        var rem = offset
        while true {
            RopeStats.visit()
            if node.height == 0 {
                for ch in node.chunks {
                    if rem == 0 { return true }
                    if rem < ch.count { return false }
                    rem -= ch.count
                }
                return false
            }
            var next: Node?
            for c in node.children {
                if rem < c.summary.utf8 { next = c; break }
                rem -= c.summary.utf8
            }
            guard let n = next else { return false }
            node = n
        }
    }

    /// Calls `body` with each stretch of bytes of `lo..<hi`, in order, until it returns `false`.
    func forEachSlice(_ lo: Int, _ hi: Int, _ body: (UnsafeBufferPointer<UInt8>) -> Bool) {
        if lo >= hi { return }
        func walk(_ node: Node, _ lo: Int, _ hi: Int) -> Bool {
            RopeStats.visit()
            var off = 0
            if node.height == 0 {
                for ch in node.chunks {
                    let s = off, e = off + ch.count
                    off = e
                    if e <= lo { continue }
                    if s >= hi { break }
                    let a = max(lo, s) - s, b = min(hi, e) - s
                    let keep = ch.bytes.withUnsafeBufferPointer { body(UnsafeBufferPointer(rebasing: $0[a..<b])) }
                    if !keep { return false }
                }
                return true
            }
            for c in node.children {
                let s = off, e = off + c.summary.utf8
                off = e
                if e <= lo { continue }
                if s >= hi { break }
                if !walk(c, max(lo, s) - s, min(hi, e) - s) { return false }
            }
            return true
        }
        _ = walk(root, lo, hi)
    }

    // MARK: Edits

    /// Replaces `lo..<hi` with `bytes`. Both offsets must be on scalar boundaries.
    mutating func replace(_ lo: Int, _ hi: Int, with bytes: UnsafeBufferPointer<UInt8>) {
        if hi > lo { Rope.delete(&root, lo, hi) }
        normalizeRoot()
        if !bytes.isEmpty {
            let extra = Rope.insert(&root, at: lo, preferNext: false, bytes: bytes)
            if !extra.isEmpty {
                var pieces = [root] + extra
                while pieces.count > 1 { pieces = Rope.groupParents(pieces) }
                root = pieces[0]
            }
            normalizeRoot()
        }
        fixCRLF(at: bytes.isEmpty ? lo : lo + bytes.count)
    }

    mutating func normalizeRoot() {
        if root.summary.utf8 == 0 { root = Node(chunks: []); return }
        while root.height > 0 && root.children.count == 1 { root = root.children[0] }
    }

    /// An edit can leave a `\r` at the end of one chunk and its `\n` at the start of the next; the chunk
    /// invariant forbids that, so the `\r` moves to the front of the second chunk.
    mutating func fixCRLF(at p: Int) {
        guard p > 0, p < root.summary.utf8, isChunkStart(p), byte(at: p) == 0x0A, byte(at: p - 1) == 0x0D else { return }
        Rope.delete(&root, p - 1, p)
        normalizeRoot()
        var cr: UInt8 = 0x0D
        withUnsafePointer(to: &cr) {
            let extra = Rope.insert(&root, at: p - 1, preferNext: true, bytes: UnsafeBufferPointer(start: $0, count: 1))
            if !extra.isEmpty {
                var pieces = [root] + extra
                while pieces.count > 1 { pieces = Rope.groupParents(pieces) }
                root = pieces[0]
            }
        }
        normalizeRoot()
    }

    /// Removes `lo..<hi` (relative to this node) from the subtree. Whole children inside the range are
    /// dropped without being entered, so the work is O(depth) plus the children removed.
    static func delete(_ node: inout Node, _ lo: Int, _ hi: Int) {
        unique(&node)
        RopeStats.visit()
        if node.height == 0 {
            var out = ContiguousArray<Chunk>()
            out.reserveCapacity(node.chunks.count)
            var off = 0
            for ch in node.chunks {
                let len = ch.count
                let s = off, e = off + len
                off = e
                if e <= lo || s >= hi { out.append(ch); continue }
                let a = max(lo, s) - s, b = min(hi, e) - s
                if a == 0 && b == len { continue }
                var nb = ContiguousArray<UInt8>()
                nb.reserveCapacity(len - (b - a))
                nb.append(contentsOf: ch.bytes[0..<a])
                nb.append(contentsOf: ch.bytes[b...])
                out.append(Chunk(nb))
            }
            node.chunks = compact(out)
            node.recompute()
            return
        }
        var i = 0
        var off = 0
        while i < node.children.count {
            let len = node.children[i].summary.utf8
            let s = off, e = off + len
            if e <= lo { off = e; i += 1; continue }
            if s >= hi { break }
            off = e
            let a = max(lo, s) - s, b = min(hi, e) - s
            if a == 0 && b == len { node.children.remove(at: i); continue }
            delete(&node.children[i], a, b)
            if node.children[i].summary.utf8 == 0 { node.children.remove(at: i) } else { i += 1 }
        }
        compactChildren(node)
        node.recompute()
    }

    /// Merges neighbouring chunks that together fit `mergeLimit`.
    static func compact(_ chunks: ContiguousArray<Chunk>) -> ContiguousArray<Chunk> {
        var out = ContiguousArray<Chunk>()
        out.reserveCapacity(chunks.count)
        for ch in chunks {
            if let last = out.last, last.count + ch.count <= mergeLimit {
                var merged = ContiguousArray<UInt8>()
                merged.reserveCapacity(last.count + ch.count)
                merged.append(contentsOf: last.bytes)
                merged.append(contentsOf: ch.bytes)
                out[out.count - 1] = Chunk(merged)
            } else { out.append(ch) }
        }
        return out
    }

    /// Merges neighbouring children whose entries together fit `fillEntries`.
    static func compactChildren(_ node: Node) {
        var i = 0
        while i + 1 < node.children.count {
            if node.children[i].count + node.children[i + 1].count <= fillEntries {
                unique(&node.children[i])
                let next = node.children[i + 1]
                let left = node.children[i]
                if left.height == 0 { left.chunks.append(contentsOf: next.chunks) } else { left.children.append(contentsOf: next.children) }
                left.recompute()
                node.children.remove(at: i + 1)
            } else { i += 1 }
        }
    }

    /// Inserts `bytes` at `p` (relative to this node). Returns the siblings this node split off to its
    /// right, in order; empty when it did not split. `preferNext` picks the chunk that starts at `p`
    /// over the one that ends there.
    static func insert(_ node: inout Node, at p: Int, preferNext: Bool, bytes: UnsafeBufferPointer<UInt8>) -> [Node] {
        unique(&node)
        RopeStats.visit()
        if node.height == 0 {
            if node.chunks.isEmpty {
                node.chunks = ContiguousArray(chunkify(bytes))
            } else {
                var j = 0
                var off = 0
                while j < node.chunks.count - 1 {
                    let end = off + node.chunks[j].count
                    if preferNext ? p < end : p <= end { break }
                    off = end
                    j += 1
                }
                let ch = node.chunks[j]
                let q = p - off
                var combined = ContiguousArray<UInt8>()
                combined.reserveCapacity(ch.count + bytes.count)
                combined.append(contentsOf: ch.bytes[0..<q])
                combined.append(contentsOf: bytes)
                combined.append(contentsOf: ch.bytes[q...])
                let new = combined.withUnsafeBufferPointer { chunkify($0) }
                node.chunks.replaceSubrange(j...j, with: new)
            }
            node.recompute()
            return splitIfNeeded(node)
        }
        var i = 0
        var off = 0
        while i < node.children.count - 1 {
            let end = off + node.children[i].summary.utf8
            if preferNext ? p < end : p <= end { break }
            off = end
            i += 1
        }
        let extra = insert(&node.children[i], at: p - off, preferNext: preferNext, bytes: bytes)
        if !extra.isEmpty { node.children.insert(contentsOf: extra, at: i + 1) }
        node.recompute()
        return splitIfNeeded(node)
    }

    /// Cuts an over-full node into `fillEntries`-sized pieces; returns the pieces after the first, which
    /// the node itself keeps.
    static func splitIfNeeded(_ node: Node) -> [Node] {
        let n = node.count
        if n <= maxEntries { return [] }
        let groups = distribute(n)
        var others: [Node] = []
        for g in groups.dropFirst() {
            others.append(node.height == 0 ? Node(chunks: ContiguousArray(node.chunks[g]))
                                           : Node(height: node.height, children: ContiguousArray(node.children[g])))
        }
        let keep = groups[0].upperBound
        if node.height == 0 { node.chunks.removeSubrange(keep...) } else { node.children.removeSubrange(keep...) }
        node.recompute()
        return others
    }

    // MARK: Storage and invariants

    /// The bytes the tree occupies, by arithmetic over its parts (object headers, array headers, slots,
    /// chunk payloads), not malloc: what the memory ratio is judged on (`CV-B`).
    var storageBytes: Int {
        func size(_ n: Node) -> Int {
            var t = 16 + MemoryLayout<Int>.size + MemoryLayout<Summary>.size + 2 * MemoryLayout<Int>.size
            if n.height == 0 {
                t += 32 + n.chunks.capacity * MemoryLayout<Chunk>.stride
                for ch in n.chunks { t += 32 + ch.count }
            } else {
                t += 32 + n.children.capacity * MemoryLayout<Node>.stride
                for c in n.children { t += size(c) }
            }
            return t
        }
        return size(root)
    }

    /// The number of nodes in the tree.
    var nodeCount: Int {
        func count(_ n: Node) -> Int { 1 + (n.height == 0 ? 0 : n.children.reduce(0) { $0 + count($1) }) }
        return count(root)
    }

    /// The number of chunks in the tree.
    var chunkCount: Int {
        func count(_ n: Node) -> Int { n.height == 0 ? n.chunks.count : n.children.reduce(0) { $0 + count($1) } }
        return count(root)
    }

    /// Every broken invariant, as text; empty when the tree is sound: summaries match their contents,
    /// all leaves share a depth, no node is over-full or empty, and no chunk starts inside a scalar or
    /// between a `\r` and `\n`.
    func problems() -> [String] {
        var out: [String] = []
        var previousLast: UInt8?
        func check(_ n: Node, isRoot: Bool) {
            var s = Summary.zero
            if n.height == 0 {
                for ch in n.chunks {
                    if ch.count == 0 { out.append("empty chunk") }
                    if ch.count > Rope.maxChunk { out.append("chunk of \(ch.count) bytes") }
                    if let first = ch.bytes.first {
                        if isContinuation(first) { out.append("chunk starts inside a scalar") }
                        if let p = previousLast, p == 0x0D, first == 0x0A { out.append("CRLF split across chunks") }
                    }
                    if let last = ch.bytes.last { previousLast = last }
                    let fresh = ch.bytes.withUnsafeBufferPointer { Summary.of($0) }
                    if fresh != ch.summary { out.append("chunk summary is stale") }
                    s.append(ch.summary)
                }
            } else {
                for c in n.children {
                    if c.height != n.height - 1 { out.append("child of height \(c.height) under \(n.height)") }
                    check(c, isRoot: false)
                    s.append(c.summary)
                }
            }
            if n.count > Rope.maxEntries { out.append("node with \(n.count) entries") }
            if n.count == 0 && !isRoot { out.append("empty node") }
            if s != n.summary { out.append("node summary is stale") }
        }
        check(root, isRoot: true)
        return out
    }
}

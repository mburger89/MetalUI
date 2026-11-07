/// The hunks that turn one text into another, for `CodeBuffer.applyExternalReplacement` (`CV-F`).
///
/// The common prefix and suffix are trimmed back to line starts, and a Myers line diff of what is left
/// gives the hunks. A middle that needs more than `maxEditDistance` line edits is one hunk: the diff's
/// memory grows with the square of the distance, and a rewrite that large gains nothing from hunks.
enum ExternalDiff {
    static let maxEditDistance = 1000

    static func hunks(old a: [UInt8], new b: [UInt8]) -> [CodeTextEdit] {
        let m = min(a.count, b.count)
        var p = 0
        while p < m && a[p] == b[p] { p += 1 }
        while p > 0 && a[p - 1] != 0x0A { p -= 1 }
        var s = 0
        while s < m - p && a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        while s > 0 {
            let ia = a.count - s - 1, ib = b.count - s - 1
            if (ia < 0 || a[ia] == 0x0A) && (ib < 0 || b[ib] == 0x0A) { break }
            s -= 1
        }
        let aEnd = a.count - s, bEnd = b.count - s
        if p == aEnd && p == bEnd { return [] }
        func whole() -> [CodeTextEdit] {
            [CodeTextEdit(range: p..<aEnd, text: String(decoding: b[p..<bEnd], as: UTF8.self))]
        }
        if p == aEnd || p == bEnd { return whole() }

        let aLines = lines(a, p, aEnd), bLines = lines(b, p, bEnd)
        var ids: [ArraySlice<UInt8>: Int] = [:]
        func id(_ line: Range<Int>, _ text: [UInt8]) -> Int {
            let key = text[line]
            if let existing = ids[key] { return existing }
            ids[key] = ids.count
            return ids.count - 1
        }
        let A = aLines.map { id($0, a) }, B = bLines.map { id($0, b) }
        guard let (deleted, inserted) = myers(A, B) else { return whole() }

        var out: [CodeTextEdit] = []
        func emit(_ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int) {
            let lo = i0 < aLines.count ? aLines[i0].lowerBound : aEnd
            let hi = i1 < aLines.count ? aLines[i1].lowerBound : aEnd
            let bl = j0 < bLines.count ? bLines[j0].lowerBound : bEnd
            let bh = j1 < bLines.count ? bLines[j1].lowerBound : bEnd
            out.append(CodeTextEdit(range: lo..<hi, text: String(decoding: b[bl..<bh], as: UTF8.self)))
        }
        var i = 0, j = 0
        var start: (Int, Int)?
        while i < A.count || j < B.count {
            let del = i < A.count && deleted[i], ins = j < B.count && inserted[j]
            if del || ins {
                if start == nil { start = (i, j) }
                if del { i += 1 }
                if ins { j += 1 }
            } else {
                if let st = start { emit(st.0, st.1, i, j); start = nil }
                i += 1
                j += 1
            }
        }
        if let st = start { emit(st.0, st.1, i, j) }
        return out
    }

    /// The ranges of the lines of `bytes[lo..<hi]`, each including its `\n`.
    private static func lines(_ bytes: [UInt8], _ lo: Int, _ hi: Int) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = lo
        for i in lo..<hi where bytes[i] == 0x0A {
            out.append(start..<i + 1)
            start = i + 1
        }
        if start < hi { out.append(start..<hi) }
        return out
    }

    /// Myers' O(ND) diff over line ids: which lines of `a` are deleted and which of `b` inserted, or `nil`
    /// when more than `maxEditDistance` edits are needed.
    private static func myers(_ a: [Int], _ b: [Int]) -> (deleted: [Bool], inserted: [Bool])? {
        let n = a.count, m = b.count
        let cap = min(maxEditDistance, n + m)
        let offset = cap + 1
        var v = [Int](repeating: 0, count: 2 * cap + 3)
        var trace: [[Int]] = []
        var finalD = -1
        search: for d in 0...cap {
            trace.append(Array(v[(offset - d - 1)...(offset + d + 1)]))
            for k in stride(from: -d, through: d, by: 2) {
                var x = (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) ? v[offset + k + 1] : v[offset + k - 1] + 1
                var y = x - k
                while x < n && y < m && a[x] == b[y] { x += 1; y += 1 }
                v[offset + k] = x
                if x >= n && y >= m { finalD = d; break search }
            }
        }
        if finalD < 0 { return nil }
        var deleted = [Bool](repeating: false, count: n)
        var inserted = [Bool](repeating: false, count: m)
        var x = n, y = m
        var d = finalD
        while d > 0 {
            let tv: (Int) -> Int = { trace[d][$0 + d + 1] }
            let k = x - y
            let previousK = (k == -d || (k != d && tv(k - 1) < tv(k + 1))) ? k + 1 : k - 1
            let previousX = tv(previousK)
            let previousY = previousX - previousK
            while x > previousX && y > previousY { x -= 1; y -= 1 }
            if x == previousX { inserted[previousY] = true } else { deleted[previousX] = true }
            x = previousX
            y = previousY
            d -= 1
        }
        return (deleted, inserted)
    }
}

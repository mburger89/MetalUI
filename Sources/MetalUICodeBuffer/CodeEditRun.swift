/// A run of edits applied one after another that moves every selection **once** (`CV-BF`).
///
/// The edits are held ascending and non-overlapping in the coordinates of the text before the first of them
/// (`T0`). They were applied either highest first (`descending`: every event's coordinates are also its
/// `T0` ones, as for a multi-selection replace or an external edit) or lowest first (`ascending`: each
/// event's coordinates include the length change of the events below it, as an undo of a descending batch
/// replays them). Moving a selection through the run gives exactly what moving it event by event does, in
/// O(1) amortised per offset: only the edits an offset touches are folded through the per-event rule
/// (`CodeBuffer.mapSelectionOffset`, `mapOtherSelection`); every edit wholly before it is one prefix sum.
struct CodeEditRun {
    var starts: [Int] = []
    var ends: [Int] = []
    var lengths: [Int] = []
    /// `prefix[i]` is the summed length change of edits `0..<i`.
    var prefix: [Int] = [0]
    var descending: Bool

    /// `steps` in application order, each in the coordinates of the text at that moment.
    init(steps: [(range: Range<Int>, newLength: Int)], descending: Bool) {
        self.descending = descending
        starts.reserveCapacity(steps.count); ends.reserveCapacity(steps.count)
        lengths.reserveCapacity(steps.count); prefix.reserveCapacity(steps.count + 1)
        if descending {
            for s in steps.reversed() { starts.append(s.range.lowerBound); ends.append(s.range.upperBound); lengths.append(s.newLength) }
        } else {
            var shift = 0
            for s in steps {
                starts.append(s.range.lowerBound - shift); ends.append(s.range.upperBound - shift); lengths.append(s.newLength)
                shift += s.newLength - s.range.count
            }
        }
        var total = 0
        for i in starts.indices { total += lengths[i] - (ends[i] - starts[i]); prefix.append(total) }
    }

    var count: Int { starts.count }

    /// Whether `steps` (application order) are each wholly below the previous (`true`), each at or after
    /// the previous one's new text (`false`), or neither (`nil`: apply one by one).
    static func order(of steps: [(range: Range<Int>, newLength: Int)]) -> Bool? {
        guard steps.count > 1 else { return true }
        var down = true, up = true
        for i in 1..<steps.count {
            if steps[i].range.upperBound > steps[i - 1].range.lowerBound { down = false }
            if steps[i].range.lowerBound < steps[i - 1].range.lowerBound + steps[i - 1].newLength { up = false }
            if !down && !up { return nil }
        }
        return down
    }

    /// The acting state's (and an external edit's) rule, `CodeBuffer.mapSelectionOffset`, over the run.
    func moveActing(_ sels: [CodeSelection], sticky: Bool) -> [CodeSelection] {
        var pointer = 0
        func map(_ o: Int) -> Int {
            if descending {
                while pointer < count && starts[pointer] <= o { pointer += 1 }
                var cur = o, k = pointer - 1
                while k >= 0 {
                    if ends[k] < cur { return cur + prefix[k + 1] }
                    cur = CodeBuffer.mapSelectionOffset(cur, start: starts[k], end: ends[k], newLength: lengths[k], sticky: sticky)
                    k -= 1
                }
                return cur
            }
            while pointer < count && ends[pointer] < o { pointer += 1 }
            var cur = o + prefix[pointer], k = pointer
            while k < count {
                let s = starts[k] + prefix[k]
                if cur < s { break }
                cur = CodeBuffer.mapSelectionOffset(cur, start: s, end: ends[k] + prefix[k], newLength: lengths[k], sticky: sticky)
                k += 1
            }
            return cur
        }
        var out: [CodeSelection] = []
        out.reserveCapacity(sels.count)
        for s in sels {
            let lo = map(s.range.lowerBound), hi = map(s.range.upperBound)
            out.append(s.head < s.anchor ? CodeSelection(anchor: hi, head: lo) : CodeSelection(anchor: lo, head: hi))
        }
        return out
    }

    /// The rule for a state that did not make the edit, `CodeBuffer.mapOtherSelection`, over the run.
    func moveOther(_ sels: [CodeSelection]) -> [CodeSelection] {
        var pointer = 0
        var out: [CodeSelection] = []
        out.reserveCapacity(sels.count)
        for s in sels {
            var cur = s
            if descending {
                while pointer < count && starts[pointer] <= s.range.upperBound { pointer += 1 }
                var k = pointer - 1
                while k >= 0 {
                    if ends[k] <= cur.range.lowerBound {
                        let d = prefix[k + 1]
                        cur = CodeSelection(anchor: cur.anchor + d, head: cur.head + d)
                        break
                    }
                    cur = CodeBuffer.mapOtherSelection(cur, start: starts[k], end: ends[k], newLength: lengths[k])
                    k -= 1
                }
            } else {
                while pointer < count && ends[pointer] <= s.range.lowerBound { pointer += 1 }
                let d = prefix[pointer]
                cur = CodeSelection(anchor: s.anchor + d, head: s.head + d)
                var k = pointer
                while k < count {
                    let st = starts[k] + prefix[k]
                    if st > cur.range.upperBound { break }
                    cur = CodeBuffer.mapOtherSelection(cur, start: st, end: ends[k] + prefix[k], newLength: lengths[k])
                    k += 1
                }
            }
            out.append(cur)
        }
        return out
    }
}

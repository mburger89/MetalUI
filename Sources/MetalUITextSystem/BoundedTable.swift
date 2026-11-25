// The bounded, generation-stamped tables both text systems keep their shapes in, and the one budget they share (`TS-F`, record 411).

/// A cached value stamped with the generation it was last touched in, and the `cost` it weighs toward the shared budget.
package struct StampedEntry<Value> {
    package var value: Value
    package var generation: Int
    package var cost: Int

    package init(value: Value, generation: Int, cost: Int) {
        self.value = value
        self.generation = generation
        self.cost = cost
    }
}

/// What the text caches may hold in total, across all of one system's tables (`TS-F`).
package enum TextCacheBudget {
    /// The most entries one system's tables hold together after a frame. Measured live sets (record 411): a 1M-row, ten-column
    /// table's visible cells 430 entries, a 200-message transcript with its composer and a streaming paragraph 205, a 5k-line
    /// code view 8; so 1024 is 2.4 times the largest.
    package static let entries = 1024

    /// The most weight (source UTF-8 bytes plus ``overhead`` per entry) they hold together after a frame. The transcript's live
    /// set is 59 KB of source (65 KB weighed), the table's 2.5 KB (16 KB weighed); 192 KiB is 3 times the larger, about 9 MiB of
    /// heap at the measured 50 bytes per weight unit, and 11 MiB inside a frame.
    package static let cost = 192 * 1024

    /// Inside a frame the bound is this much over `entries` and `cost` before an eviction runs (a quarter).
    package static func inFrameLimit(_ limit: Int) -> Int { limit + limit / 4 }

    /// The order entries go in. After a frame (`current` is `nil`) it is the generation: oldest first. Inside frame
    /// `current` it is stale entries first, then the ones this frame has already used, and last the previous frame's that this
    /// one has not reached yet: those are the hits still to come, so a live set over the budget re-shapes its overage and not
    /// the entries an eviction in the middle of the frame took from in front of the loop
    /// (`aWorkingSetOverTheBudgetReShapesTheOverageAndNoMore`).
    package static func rank(_ generation: Int, inFrame current: Int?) -> Int {
        guard let current else { return generation }
        if generation < current - 1 { return generation }
        return generation == current ? current : current + 1
    }

    /// A string's weight before its text: a shaped entry costs about 1.6 KiB of heap whatever its length, about 32 source bytes'
    /// worth at the measured 50 bytes of heap per source byte.
    package static let overhead = 32

    /// The weight of an entry for `string`.
    package static func weight(of string: String) -> Int { string.utf8.count + overhead }

    /// Splits `allowance` evictions among tables holding `counts` entries of the last generation, in proportion, so that a live
    /// set over the budget loses a share of each table and not all of the first (a table emptied is a table that re-shapes
    /// every frame). The shares sum to `allowance`.
    package static func shares(of allowance: Int, among counts: [Int]) -> [Int] {
        let total = counts.reduce(0, +)
        guard total > 0 else { return counts.map { _ in 0 } }
        var out = counts.map { allowance * $0 / total }
        var rest = allowance - out.reduce(0, +)
        for i in out.indices where rest > 0 && out[i] < counts[i] { out[i] += 1; rest -= 1 }
        return out
    }

    /// The oldest generation that must be dropped, and how many of its entries, to bring `count` entries and `cost` weight
    /// under the limits, given every entry's stamp; `nil` when they already are. Oldest generation first, and within the last
    /// one dropped, any: a live set over the limit is one generation, so dropping its overage keeps the rest, where a strict
    /// least-recently-used loop would drop all of it (`aWorkingSetOverTheBudgetReShapesTheOverageAndNoMore`).
    package static func cut(_ stamps: inout [(generation: Int, cost: Int)], entries limitEntries: Int,
                            cost limitCost: Int) -> (generation: Int, allowance: Int)? {
        var count = stamps.count
        var total = 0
        for stamp in stamps { total += stamp.cost }
        guard count > limitEntries || total > limitCost else { return nil }
        stamps.sort { $0.generation < $1.generation }
        var last = Int.min, fromLast = 0
        for stamp in stamps where count > limitEntries || total > limitCost {
            count -= 1
            total -= stamp.cost
            if stamp.generation != last { last = stamp.generation; fromLast = 0 }
            fromLast += 1
        }
        return (last, fromLast)
    }
}

/// A dictionary of stamped entries and the running sum of their cost.
package struct BoundedTable<Key: Hashable, Value> {
    package var dict: [Key: StampedEntry<Value>] = [:]
    package private(set) var cost = 0

    package init() {}

    package var count: Int { dict.count }

    package mutating func insert(_ key: Key, _ value: Value, generation: Int, cost entryCost: Int) {
        if let old = dict.updateValue(StampedEntry(value: value, generation: generation, cost: entryCost), forKey: key) {
            cost -= old.cost
        }
        cost += entryCost
    }

    /// Drops every entry last touched before `cutoff`.
    package mutating func removeOlder(than cutoff: Int) {
        var keys: [Key] = []
        for (key, entry) in dict where entry.generation < cutoff { keys.append(key) }
        for key in keys { cost -= dict.removeValue(forKey: key)?.cost ?? 0 }
    }

    /// How many entries have `rank` (``TextCacheBudget/rank(_:inFrame:)``).
    package func count(atRank rank: Int, inFrame current: Int?) -> Int {
        var n = 0
        for entry in dict.values where TextCacheBudget.rank(entry.generation, inFrame: current) == rank { n += 1 }
        return n
    }

    /// Adds this table's stamps to `stamps`.
    package func appendStamps(to stamps: inout [(generation: Int, cost: Int)], inFrame current: Int?) {
        for entry in dict.values { stamps.append((TextCacheBudget.rank(entry.generation, inFrame: current), entry.cost)) }
    }

    /// Applies `cut`: every entry older than its generation goes, and up to `allowance` entries of that generation (this
    /// table's ``TextCacheBudget/shares(of:among:)`` of the cut's allowance).
    package mutating func evict(olderThan rank: Int, inFrame current: Int?, andUpTo allowance: Int) {
        var left = allowance
        var keys: [Key] = []
        for (key, entry) in dict {
            let entryRank = TextCacheBudget.rank(entry.generation, inFrame: current)
            if entryRank < rank {
                keys.append(key)
            } else if entryRank == rank, left > 0 {
                keys.append(key)
                left -= 1
            }
        }
        for key in keys { cost -= dict.removeValue(forKey: key)?.cost ?? 0 }
    }

    /// The entries and weight last touched in `generation`.
    package func live(in generation: Int) -> (entries: Int, cost: Int) {
        var entries = 0, weight = 0
        for entry in dict.values where entry.generation == generation { entries += 1; weight += entry.cost }
        return (entries, weight)
    }
}

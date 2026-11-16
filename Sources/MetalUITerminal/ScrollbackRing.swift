/// The rows that have scrolled off the top of the screen: a fixed-capacity ring of compacted rows. The oldest
/// row is dropped when a new one arrives at capacity.
struct ScrollbackRing {
    private(set) var storage: [TerminalRow] = []
    private var head = 0
    let capacity: Int

    init(capacity: Int) { self.capacity = max(0, capacity) }

    var count: Int { storage.count }

    /// Appends `row` (already compacted), evicting the oldest at capacity. Returns whether one was evicted.
    @discardableResult
    mutating func append(_ row: TerminalRow) -> Bool {
        guard capacity > 0 else { return true }
        if storage.count < capacity {
            if storage.count == storage.capacity { storage.reserveCapacity(min(capacity, max(64, storage.count * 2))) }
            storage.append(row)
            return false
        }
        storage[head] = row
        head = (head + 1) % capacity
        return true
    }

    /// The `index`th oldest retained row.
    subscript(index: Int) -> TerminalRow { storage[(head + index) % storage.count] }

    /// Bytes held: the ring's own array plus every row's two arrays. The census the 4 MB budget is proved on.
    var byteCensus: Int {
        let ring = storage.capacity == 0 ? 0 : 32 + storage.capacity * MemoryLayout<TerminalRow>.stride
        return ring + storage.reduce(0) { $0 + $1.heapByteCount }
    }
}

extension ScrollbackRing {
    /// Drops every retained row (ED 3).
    mutating func removeAll() {
        self = ScrollbackRing(capacity: capacity)
    }
}

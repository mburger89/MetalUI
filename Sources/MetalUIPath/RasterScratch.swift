/// Reusable working buffers for `CoverageRasterizer.rasterize` and `BoxBlur.blur` (P4 lane 2, rulings
/// `OS-H`, `OS-L`): the winding cells (`Double`) and the blur's two `Int32` planes and column sums, which a
/// rasterization used to allocate and zero per call. A value type, so it is `Sendable` and bit-identical on
/// every platform (`GX-B`); this target still imports nothing.
///
/// **Borrow rule (`OS-L`).** A scratch is passed `inout` into one call and is not held across a closure or a
/// nested leaf. Each buffer is *taken out* of the scratch (the slot is left empty) and *returned* after use,
/// so even a re-entrant caller sees an empty slot and allocates its own: it can never alias a live buffer.
/// **Zero-filled on every take**: a stale cell would change bytes. **Capped**: a returned buffer longer than
/// `capacityLimit` elements is dropped, so one huge raster does not pin memory.
package struct RasterScratch: Sendable {
    /// The largest buffer (in elements) the scratch keeps.
    package static let capacityLimit = 1 << 22

    /// The three `Int32` buffers of a blur.
    package enum Slot: Int, CaseIterable, Sendable { case a, b, sums }

    private var cells: [Double] = []
    private var ints: [[Int32]] = [[], [], []]

    package init() {}

    /// Elements currently held across all slots (a read-back for tests).
    package var heldElements: Int { cells.count + ints.reduce(0) { $0 + $1.count } }

    /// `count` zeros, reusing the held buffer's storage when it has any.
    package mutating func takeCells(count: Int) -> [Double] {
        var buffer = cells
        cells = []
        buffer.removeAll(keepingCapacity: true)
        buffer.append(contentsOf: repeatElement(0, count: count))
        return buffer
    }

    /// Hands `buffer` back; it is dropped when longer than `capacityLimit`.
    package mutating func returnCells(_ buffer: [Double]) {
        cells = buffer.count <= RasterScratch.capacityLimit ? buffer : []
    }

    /// `count` zeros for `slot`.
    package mutating func takeInts(_ slot: Slot, count: Int) -> [Int32] {
        var buffer = ints[slot.rawValue]
        ints[slot.rawValue] = []
        buffer.removeAll(keepingCapacity: true)
        buffer.append(contentsOf: repeatElement(0, count: count))
        return buffer
    }

    /// Hands `buffer` back to `slot`; it is dropped when longer than `capacityLimit`.
    package mutating func returnInts(_ slot: Slot, _ buffer: [Int32]) {
        ints[slot.rawValue] = buffer.count <= RasterScratch.capacityLimit ? buffer : []
    }
}

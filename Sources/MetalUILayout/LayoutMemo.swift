/// A window-owned memo of layout answers, keyed by a **structural signature**
/// and never by a node id (C14, rulings `IV-E`, `IV-N`).
///
/// `NativeLayoutRun`'s cache is keyed `(LayoutNodeID, ProposedSize)` and dies with
/// its call, which is what keeps ruling C-3 (ids are per frame) honest. This memo
/// is the other thing a later frame can reuse: a subtree whose **shape and
/// parameters** are equal to one measured before answers the same proposal the
/// same way, wherever its nodes sit in the new tree. It holds values only
/// (`LayoutMeasurement`, `LayoutRect`) and **no `LayoutNodeID`**
/// (`theMemoHoldsNoNodeID`).
///
/// Two uses, both consulted by `LayoutTree` (`LayoutTree.swift`):
///
/// - **(M)** `measureNative` asks `(signature, proposal)` after the run's own
///   cache misses; a hit returns the stored answer without descending.
/// - **(P)** a root run whose `(root signature, proposal, bounds)` equal an
///   earlier run's copies that run's unrounded rects and skips placement.
///
/// **Entries live two frames** (`endFrame()`, the `ShapingCache` rule), so memory is
/// bounded by two frames' distinct keyed subtrees.
///
/// **A signature is `nil` for any subtree holding an unkeyed leaf**
/// (`signature(of:)`): unmatchable, never wrongly matched. Only a leaf registered
/// with a key opts in, and its key must cover everything its measure closure reads
/// (`IV-E`).
///
/// **`package`**: a plain import cannot reach it (guard 1.13).
package final class LayoutMemo {
    /// Whether the memo is consulted at all. A test switch; on by default.
    package var isEnabled = true

    /// Whether every hit is **recomputed fresh and compared**, trapping on a
    /// difference (`IV-J`). Off in production; the suite is run once with it on.
    package var verifies: Bool

    package init(verifies: Bool = false) { self.verifies = verifies }

    struct MeasureKey: Hashable {
        let signature: LayoutSignature
        let proposal: ProposedSize

        /// The signature's words are already mixed (`SignatureBuilder`): fold them with the proposal into one
        /// word (`PA-K`); `==` stays the synthesized, complete one.
        func hash(into hasher: inout Hasher) {
            hasher.combine(signature.a ^ (signature.b << 21 | signature.b >> 43) ^ proposal.foldedHashWord)
        }
    }

    struct PlacementKey: Hashable {
        let signature: LayoutSignature
        let proposal: ProposedSize
        let x: UInt64, y: UInt64, width: UInt64, height: UInt64

        init(signature: LayoutSignature, proposal: ProposedSize, bounds: LayoutRect) {
            self.signature = signature
            self.proposal = proposal
            x = bounds.x.bitPattern; y = bounds.y.bitPattern
            width = bounds.width.bitPattern; height = bounds.height.bitPattern
        }
    }

    private var measurements: [MeasureKey: LayoutMeasurement] = [:]
    private var previousMeasurements: [MeasureKey: LayoutMeasurement] = [:]
    private var placements: [PlacementKey: Placed] = [:]
    private var previousPlacements: [PlacementKey: Placed] = [:]

    /// The memo keys a placement's recording looked up, stored or restored below its root (`CF-E`): what a later
    /// restore of that placement stands for. A restore places nothing and so looks nothing up; without this the
    /// entries below it age out of both generations while it keeps hitting, and the first frame that must measure
    /// or place the subtree for itself (a graft, a changed bound) pays for all of them at once.
    struct Footprint {
        var measures: [MeasureKey] = []
        var placements: [PlacementKey] = []
        var isEmpty: Bool { measures.isEmpty && placements.isEmpty }
    }

    /// One stored placement: the unrounded rects and the footprint of the recording that made them.
    struct Placed {
        var rects: [LayoutRect]
        var footprint: Footprint
    }

    /// The signature of each node of the current run, by node index. Scratch:
    /// only the indices the run's pre-order visited are meaningful, and a run
    /// never overlaps another on one tree (`isLayingOut`).
    var signatures: [LayoutSignature?] = []

    /// How many entries the memo holds (both generations): a test observable.
    package var entryCount: Int {
        measurements.count + previousMeasurements.count + placements.count + previousPlacements.count
    }

    func lookup(_ signature: LayoutSignature, _ proposal: ProposedSize) -> LayoutMeasurement? {
        let key = MeasureKey(signature: signature, proposal: proposal)
        if let hit = measurements[key] { return hit }
        if let hit = previousMeasurements[key] {
            measurements[key] = hit   // alive another frame
            return hit
        }
        return nil
    }

    func store(_ signature: LayoutSignature, _ proposal: ProposedSize, _ measurement: LayoutMeasurement) {
        measurements[MeasureKey(signature: signature, proposal: proposal)] = measurement
    }

    func lookupPlacement(_ key: PlacementKey) -> Placed? {
        if let hit = placements[key] { return hit }
        if let hit = previousPlacements[key] {
            placements[key] = hit
            return hit
        }
        return nil
    }

    func storePlacement(_ key: PlacementKey, _ rects: [LayoutRect], footprint: Footprint = Footprint()) {
        placements[key] = Placed(rects: rects, footprint: footprint)
    }

    /// Keeps alive what a restored placement stands for (`CF-E`): every entry of `footprint` still in the previous
    /// generation moves into this frame's, exactly as a lookup of it would have. A key in neither generation is left
    /// alone, and nothing is counted: the work counters read lookups, and a touch is not one.
    func touch(_ footprint: Footprint) {
        for key in footprint.measures where measurements[key] == nil {
            if let hit = previousMeasurements[key] { measurements[key] = hit }
        }
        for key in footprint.placements where placements[key] == nil {
            if let hit = previousPlacements[key] { placements[key] = hit }
        }
    }

    /// Closes a frame: what was not used or stored this frame and was not used
    /// last frame is dropped.
    package func endFrame() {
        previousMeasurements = measurements
        measurements = [:]
        previousPlacements = placements
        placements = [:]
    }

    /// Drops everything.
    package func removeAll() {
        measurements = [:]; previousMeasurements = [:]
        placements = [:]; previousPlacements = [:]
    }
}

/// A 128-bit structural hash of a layout subtree (`IV-E`): two independent
/// 64-bit mixers over one canonical stream, because a collision is a silently
/// wrong layout and 64 bits is not enough.
package struct LayoutSignature: Hashable, Sendable {
    package var a: UInt64
    package var b: UInt64
}

/// Accumulates a ``LayoutSignature``. Order-sensitive.
struct SignatureBuilder {
    private var a: UInt64 = 0x243F_6A88_85A3_08D3
    private var b: UInt64 = 0x1319_8A2E_0370_7344

    @inline(__always)
    private static func finalize(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func mix(_ value: UInt64) {
        a = Self.finalize((a &+ value) &* 0x9E37_79B9_7F4A_7C15)
        b = Self.finalize(b ^ (value &* 0xC2B2_AE3D_27D4_EB4F) ^ (b >> 7)) &+ 0x2545_F491_4F6C_DD1D
    }

    mutating func mix(_ value: Int) { mix(UInt64(bitPattern: Int64(value))) }
    mutating func mix(_ value: Bool) { mix(value ? 1 : 0) }
    mutating func mix(_ value: Double) { mix(value.bitPattern) }
    mutating func mix(_ value: Double?) {
        if let value { mix(1 as UInt64); mix(value.bitPattern) } else { mix(0 as UInt64) }
    }

    /// A `Hashable` value, through the standard library's per-process seeded
    /// hasher twice with different prefixes (stable within a process, which is
    /// the memo's lifetime).
    mutating func mixHashable<H: Hashable>(_ value: H) {
        var first = Hasher()
        first.combine(value)
        var second = Hasher()
        second.combine(0x5EED_0002 as UInt64)
        second.combine(value)
        mix(UInt64(bitPattern: Int64(first.finalize())))
        mix(UInt64(bitPattern: Int64(second.finalize())))
    }

    mutating func mix(_ signature: LayoutSignature) { mix(signature.a); mix(signature.b) }

    var signature: LayoutSignature { LayoutSignature(a: a, b: b) }
}

/// A leaf key's signature words, computed once where the key is registered (`PA-D`): the key (kept for
/// `structureDigest`), the type's identity and the two hasher words `SignatureBuilder.mixHashable` derives, so
/// mixing them in `mix(into:)` yields **exactly** the signature the direct route (`mix(1)`, the type, `mixHashable`)
/// yields, and a run or a graft opens no `AnyHashable` box.
struct LeafKey {
    let key: AnyHashable
    let typeID: UInt64
    let h1: UInt64
    let h2: UInt64

    init(_ key: AnyHashable) {
        self.key = key
        typeID = UInt64(UInt(bitPattern: ObjectIdentifier(type(of: key.base))))
        var first = Hasher()
        first.combine(key)
        var second = Hasher()
        second.combine(0x5EED_0002 as UInt64)
        second.combine(key)
        h1 = UInt64(bitPattern: Int64(first.finalize()))
        h2 = UInt64(bitPattern: Int64(second.finalize()))
    }

    @inline(__always)
    func mix(into h: inout SignatureBuilder) {
        h.mix(1)
        h.mix(typeID)
        h.mix(h1)
        h.mix(h2)
    }
}

/// How many cells a scalar covers. Phase 1.3 owns the full conformance table; this is the width the storage and the
/// printer already need: 0 for combining and format scalars (they join the previous cell), 2 for East Asian wide
/// and fullwidth ranges and the emoji blocks, 1 for everything else.
enum CharacterWidth {
    static func of(_ scalar: Unicode.Scalar) -> Int {
        let v = scalar.value
        if v < 0x300 { return 1 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format:
            return v == 0x200B || v == 0x200C || v == 0x200D || v == 0xFE0F || v >= 0x300 ? 0 : 1
        default:
            break
        }
        switch v {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }
}

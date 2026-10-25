/// What a run-time compute shader blob is checked against before SDL sees it (rulings `RC-E`, `RC-F`).
///
/// Pure functions over plain values, `package`: `MetalUISDLGPU` wraps them.
package enum ComputeBlobFormat: Equatable, Sendable { case spirv, msl, dxil }

/// The stage of a blob; run-time compile is compute only (`RC-G`).
package enum ComputeBlobStage: Equatable, Sendable { case vertex, fragment, compute }

/// A refusal, naming the field. Lane B maps these onto its public error.
package enum ComputeValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidInput(String)
    case malformedReflection(String)
    case unsupportedTarget(String)
    /// The library was not found; one `path: reason` line per place tried.
    case libraryMissing([String])

    package var description: String {
        switch self {
        case .invalidInput(let text), .malformedReflection(let text), .unsupportedTarget(let text): return text
        case .libraryMissing(let lines): return "shader compiler library not found; tried:\n" + lines.joined(separator: "\n")
        }
    }
}

/// The compute pipeline counts SDL needs and the thread group, as reflection reports them.
package struct ComputeReflection: Equatable, Sendable {
    package var samplers: Int
    package var readOnlyStorageTextures: Int
    package var readOnlyStorageBuffers: Int
    package var readWriteStorageTextures: Int
    package var readWriteStorageBuffers: Int
    package var uniformBuffers: Int
    package var threadCount: (x: Int, y: Int, z: Int)

    package init(samplers: Int = 0, readOnlyStorageTextures: Int = 0, readOnlyStorageBuffers: Int = 0,
                 readWriteStorageTextures: Int = 0, readWriteStorageBuffers: Int = 0, uniformBuffers: Int = 0,
                 threadCount: (x: Int, y: Int, z: Int)) {
        self.samplers = samplers
        self.readOnlyStorageTextures = readOnlyStorageTextures
        self.readOnlyStorageBuffers = readOnlyStorageBuffers
        self.readWriteStorageTextures = readWriteStorageTextures
        self.readWriteStorageBuffers = readWriteStorageBuffers
        self.uniformBuffers = uniformBuffers
        self.threadCount = threadCount
    }

    package static func == (a: Self, b: Self) -> Bool {
        a.samplers == b.samplers && a.readOnlyStorageTextures == b.readOnlyStorageTextures
            && a.readOnlyStorageBuffers == b.readOnlyStorageBuffers
            && a.readWriteStorageTextures == b.readWriteStorageTextures
            && a.readWriteStorageBuffers == b.readWriteStorageBuffers && a.uniformBuffers == b.uniformBuffers
            && a.threadCount == b.threadCount
    }
}

package enum ComputeBlobValidation {
    /// The sanity bound on every count (not SDL's limit, which is undocumented; `RC-E`).
    package static let countLimit = 64
    /// D3D12's limit on `x * y * z`, the tightest of the three backends.
    package static let invocationLimit = 1024

    /// Checks a blob's bytes, entry point, stage and reflection; throws the first problem.
    package static func validate(bytes: [UInt8], format: ComputeBlobFormat, entryPoint: String,
                                 stage: ComputeBlobStage, reflection: ComputeReflection) throws {
        guard stage == .compute else {
            throw ComputeValidationError.invalidInput("stage must be compute: run-time compile is compute only")
        }
        guard !bytes.isEmpty else { throw ComputeValidationError.invalidInput("bytes is empty") }
        guard !entryPoint.isEmpty else { throw ComputeValidationError.invalidInput("entryPoint is empty") }
        try validateBytes(bytes, format: format, entryPoint: entryPoint)
        try validate(reflection)
    }

    /// The format-specific byte check.
    package static func validateBytes(_ bytes: [UInt8], format: ComputeBlobFormat, entryPoint: String) throws {
        switch format {
        case .spirv:
            guard bytes.count % 4 == 0 else {
                throw ComputeValidationError.invalidInput("SPIR-V bytes must be whole 32-bit words (\(bytes.count) bytes)")
            }
            guard bytes.count >= 4, Array(bytes[0..<4]) == [0x03, 0x02, 0x23, 0x07] else {
                throw ComputeValidationError.invalidInput("SPIR-V bytes must begin with the little-endian magic 0x07230203")
            }
        case .dxil:
            guard bytes.count >= 4, Array(bytes[0..<4]) == [0x44, 0x58, 0x42, 0x43] else {
                throw ComputeValidationError.invalidInput("DXIL bytes must be a DXBC container (magic \"DXBC\")")
            }
        case .msl:
            let text = String(decoding: bytes, as: UTF8.self)
            guard !bytes.contains(0), Array(text.utf8) == bytes else {
                throw ComputeValidationError.invalidInput("MSL bytes must be UTF-8 text without a NUL")
            }
            guard text.contains(entryPoint) else {
                throw ComputeValidationError.invalidInput("MSL source does not contain the entry point \"\(entryPoint)\"")
            }
        }
    }

    /// Counts in `0...64`, every thread axis at least 1, `x * y * z <= 1024`; names the field.
    package static func validate(_ reflection: ComputeReflection) throws {
        let counts: [(String, Int)] = [
            ("samplers", reflection.samplers), ("readOnlyStorageTextures", reflection.readOnlyStorageTextures),
            ("readOnlyStorageBuffers", reflection.readOnlyStorageBuffers),
            ("readWriteStorageTextures", reflection.readWriteStorageTextures),
            ("readWriteStorageBuffers", reflection.readWriteStorageBuffers), ("uniformBuffers", reflection.uniformBuffers)]
        for (name, value) in counts where value < 0 || value > countLimit {
            throw ComputeValidationError.malformedReflection("\(name) is \(value); it must be in 0...\(countLimit)")
        }
        let axes: [(String, Int)] = [("threadCount.x", reflection.threadCount.x), ("threadCount.y", reflection.threadCount.y),
                                     ("threadCount.z", reflection.threadCount.z)]
        for (name, value) in axes where value < 1 {
            throw ComputeValidationError.malformedReflection("\(name) is \(value); a thread group axis must be at least 1")
        }
        let (xy, o1) = reflection.threadCount.x.multipliedReportingOverflow(by: reflection.threadCount.y)
        let (xyz, o2) = xy.multipliedReportingOverflow(by: reflection.threadCount.z)
        if o1 || o2 || xyz > invocationLimit {
            throw ComputeValidationError.malformedReflection(
                "threadCount \(reflection.threadCount.x)x\(reflection.threadCount.y)x\(reflection.threadCount.z) exceeds \(invocationLimit) invocations")
        }
    }

    /// An identifier: ASCII letter or underscore, then letters, digits, underscores.
    package static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.utf8.first, first == 0x5F || isLetter(first) else { return false }
        return text.utf8.allSatisfy { $0 == 0x5F || isLetter($0) || ($0 >= 0x30 && $0 <= 0x39) }
    }

    /// An entry point is a non-empty identifier.
    package static func validateEntryPoint(_ name: String) throws {
        guard !name.isEmpty else { throw ComputeValidationError.invalidInput("entryPoint is empty") }
        guard isIdentifier(name) else { throw ComputeValidationError.invalidInput("entryPoint \"\(name)\" is not an identifier") }
    }

    /// HLSL source is non-empty and holds no NUL.
    package static func validateSource(_ hlsl: String) throws {
        guard !hlsl.isEmpty else { throw ComputeValidationError.invalidInput("hlsl is empty") }
        guard !hlsl.utf8.contains(0) else { throw ComputeValidationError.invalidInput("hlsl holds a NUL byte") }
    }

    /// One define: the name an identifier, no NUL anywhere.
    package static func validateDefine(name: String, value: String?) throws {
        guard isIdentifier(name) else { throw ComputeValidationError.invalidInput("define name \"\(name)\" is not an identifier") }
        if let value, value.utf8.contains(0) {
            throw ComputeValidationError.invalidInput("define \(name) has a value holding a NUL byte")
        }
    }

    /// Every define valid and no name twice.
    package static func validateDefines(_ defines: [(name: String, value: String?)]) throws {
        var seen = Set<String>()
        for define in defines {
            try validateDefine(name: define.name, value: define.value)
            guard seen.insert(define.name).inserted else {
                throw ComputeValidationError.invalidInput("define \(define.name) is given twice")
            }
        }
    }

    /// The format a driver compiles to: `vulkan` SPIR-V, `metal` MSL, `direct3d12` DXIL;
    /// any other driver is unsupported and named (`RC-F`).
    package static func target(forDriver driver: String) throws -> ComputeBlobFormat {
        switch driver {
        case "vulkan": return .spirv
        case "metal": return .msl
        case "direct3d12": return .dxil
        default:
            throw ComputeValidationError.unsupportedTarget(
                "SDL GPU driver \"\(driver)\" has no run-time compile format (vulkan, metal and direct3d12 have)")
        }
    }

    private static func isLetter(_ byte: UInt8) -> Bool { (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) }
}

import Testing
@testable import MetalUIShaderCompile

// Run-time compute blob and reflection validation (item XP-G25, rulings RC-E, RC-F, spec 5 tests 7-12).

private typealias Validation = ComputeBlobValidation

private func reflection(threads: (Int, Int, Int) = (64, 1, 1)) -> ComputeReflection {
    ComputeReflection(readOnlyStorageBuffers: 1, readWriteStorageBuffers: 1, uniformBuffers: 1,
                      threadCount: (threads.0, threads.1, threads.2))
}
private let spirv: [UInt8] = [0x03, 0x02, 0x23, 0x07, 0, 0, 1, 0]

private func refusal(_ body: () throws -> Void) -> String? {
    do { try body(); return nil } catch { return "\(error)" }
}

/// **Test 7a** (`RC-E`). Mutation: accept a zero axis.
@Test func aZeroThreadAxisIsRefusedByName() {
    for (name, threads) in [("threadCount.x", (0, 1, 1)), ("threadCount.y", (1, 0, 1)), ("threadCount.z", (1, 1, 0))] {
        let text = refusal { try Validation.validate(reflection(threads: threads)) }
        #expect(text?.contains(name) == true, "\(name): \(String(describing: text))")
    }
    #expect(refusal { try Validation.validate(reflection(threads: (-1, 1, 1))) } != nil)
}

/// **Test 7b** (`RC-E`). Mutation: compare `> 1025`.
@Test func aThreadGroupOf1025InvocationsIsRefused() {
    for threads in [(1025, 1, 1), (1, 1025, 1), (1, 1, 1025), (33, 32, 1), (32, 32, 2), (Int.max, 2, 1)] {
        #expect(refusal { try Validation.validate(reflection(threads: threads)) } != nil, "\(threads)")
    }
}

/// **Test 7c** (`RC-E`).
@Test func aThreadGroupOf1024InvocationsIsAccepted() throws {
    for threads in [(1024, 1, 1), (32, 32, 1), (16, 8, 8), (8, 8, 16), (1, 1, 1), (64, 1, 1)] {
        try Validation.validate(reflection(threads: threads))
    }
}

/// **Test 8** (`RC-E`). One arm per field. Mutation: skip the uniform-buffer arm.
@Test func everyCountOverItsLimitIsRefusedNamingTheField() throws {
    let fields: [(String, WritableKeyPath<ComputeReflection, Int>)] = [
        ("samplers", \.samplers), ("readOnlyStorageTextures", \.readOnlyStorageTextures),
        ("readOnlyStorageBuffers", \.readOnlyStorageBuffers), ("readWriteStorageTextures", \.readWriteStorageTextures),
        ("readWriteStorageBuffers", \.readWriteStorageBuffers), ("uniformBuffers", \.uniformBuffers)]
    try #require(fields.count == 6)
    for (name, path) in fields {
        var over = reflection()
        over[keyPath: path] = 65
        #expect(refusal { try Validation.validate(over) }?.contains(name) == true, "\(name)")
        var negative = reflection()
        negative[keyPath: path] = -1
        #expect(refusal { try Validation.validate(negative) }?.contains(name) == true, "\(name) negative")
        var edge = reflection()
        edge[keyPath: path] = 64
        try Validation.validate(edge)
    }
}

/// **Test 9** (`RC-E`, `RC-G`). Mutation: accept empty bytes.
@Test func emptyBytesAnEmptyEntryPointAndAGraphicsStageAreRefused() throws {
    try Validation.validate(bytes: spirv, format: .spirv, entryPoint: "main", stage: .compute, reflection: reflection())
    #expect(refusal { try Validation.validate(bytes: [], format: .spirv, entryPoint: "main", stage: .compute, reflection: reflection()) }?
        .contains("bytes is empty") == true)
    #expect(refusal { try Validation.validate(bytes: spirv, format: .spirv, entryPoint: "", stage: .compute, reflection: reflection()) }?
        .contains("entryPoint") == true)
    for stage in [ComputeBlobStage.vertex, .fragment] {
        #expect(refusal { try Validation.validate(bytes: spirv, format: .spirv, entryPoint: "main", stage: stage, reflection: reflection()) }?
            .contains("compute") == true)
    }
    // a bad reflection is refused through the whole check too
    #expect(refusal { try Validation.validate(bytes: spirv, format: .spirv, entryPoint: "main", stage: .compute,
                                              reflection: reflection(threads: (0, 1, 1))) } != nil)
}

/// **Test 10a** (`RC-E`). Mutation: test the wrong magic byte order.
@Test func spirvMustHaveItsMagicAndWholeWords() throws {
    try Validation.validateBytes(spirv, format: .spirv, entryPoint: "main")
    #expect(refusal { try Validation.validateBytes([0x07, 0x23, 0x02, 0x03, 0, 0, 0, 0], format: .spirv, entryPoint: "main") } != nil,
            "big-endian magic")
    #expect(refusal { try Validation.validateBytes(spirv + [0], format: .spirv, entryPoint: "main") }?.contains("words") == true)
    #expect(refusal { try Validation.validateBytes([0x03, 0x02, 0x23], format: .spirv, entryPoint: "main") } != nil)
    #expect(refusal { try Validation.validateBytes([1, 2, 3, 4], format: .spirv, entryPoint: "main") } != nil)
}

/// **Test 10b** (`RC-E`). Mutation: accept any four bytes.
@Test func dxilMustBeADXBCContainer() throws {
    try Validation.validateBytes(Array("DXBC".utf8) + [0, 0, 0, 0], format: .dxil, entryPoint: "main")
    #expect(refusal { try Validation.validateBytes(Array("dxbc".utf8), format: .dxil, entryPoint: "main") } != nil)
    #expect(refusal { try Validation.validateBytes(spirv, format: .dxil, entryPoint: "main") } != nil)
    #expect(refusal { try Validation.validateBytes(Array("DXB".utf8), format: .dxil, entryPoint: "main") } != nil)
}

/// **Test 10c** (`RC-E`). Mutation: skip the entry-point search.
@Test func mslMustContainItsEntryPoint() throws {
    let source = Array("kernel void main0(uint i [[thread_position_in_grid]]) {}".utf8)
    try Validation.validateBytes(source, format: .msl, entryPoint: "main0")
    #expect(refusal { try Validation.validateBytes(source, format: .msl, entryPoint: "other") }?.contains("other") == true)
    #expect(refusal { try Validation.validateBytes([0xFF, 0xFE, 0xFD], format: .msl, entryPoint: "main0") } != nil, "not UTF-8")
    #expect(refusal { try Validation.validateBytes(source + [0], format: .msl, entryPoint: "main0") } != nil, "NUL")
}

/// **Test 11a** (`RC-E`). Mutation: accept any define name.
@Test func aDefineNameMustBeAnIdentifierAndNoValueMayHoldANUL() throws {
    try Validation.validateDefine(name: "K", value: "3")
    try Validation.validateDefine(name: "_a1", value: nil)
    try Validation.validateDefine(name: "FLAG", value: "")
    for name in ["", "1K", "a b", "a-b", "a=b", "é", "a\0b"] {
        #expect(refusal { try Validation.validateDefine(name: name, value: nil) } != nil, "\(name.debugDescription)")
    }
    #expect(refusal { try Validation.validateDefine(name: "K", value: "3\u{0}4") }?.contains("NUL") == true)
    // entry point and source share the identifier and NUL rules
    try Validation.validateEntryPoint("main0")
    #expect(refusal { try Validation.validateEntryPoint("a b") } != nil)
    #expect(refusal { try Validation.validateEntryPoint("") } != nil)
    try Validation.validateSource("[numthreads(1,1,1)] void main() {}")
    #expect(refusal { try Validation.validateSource("") } != nil)
    #expect(refusal { try Validation.validateSource("a\0b") } != nil)
}

/// **Test 11b** (`RC-E`). Mutation: drop the duplicate check.
@Test func twoDefinesWithOneNameAreRefused() throws {
    try Validation.validateDefines([("A", "1"), ("B", nil)])
    #expect(refusal { try Validation.validateDefines([("A", "1"), ("A", "2")]) }?.contains("A") == true)
    #expect(refusal { try Validation.validateDefines([("A", nil), ("A", nil)]) } != nil)
}

/// **Test 12** (`RC-F`). Mutation: map `metal` to spirv.
@Test func aDriverMapsToItsFormatAndAnyOtherIsUnsupportedNamingIt() throws {
    #expect(try Validation.target(forDriver: "vulkan") == .spirv)
    #expect(try Validation.target(forDriver: "metal") == .msl)
    #expect(try Validation.target(forDriver: "direct3d12") == .dxil)
    for driver in ["gpu", "private", "", "Vulkan"] {
        do {
            _ = try Validation.target(forDriver: driver)
            Issue.record("\(driver) must be unsupported")
        } catch let error as ComputeValidationError {
            guard case .unsupportedTarget(let text) = error else { Issue.record("wrong case \(error)"); continue }
            #expect(text.contains("\"\(driver)\""))
        }
    }
}

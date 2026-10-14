import Foundation
import Testing
import MetalUISDLGPU
@testable import MetalUISDLGPU

// The app shader path (ruling GA-F; spec §6 C5-C7). Portable and GPU-free: no
// SDL call, no device, so these run on every machine.

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("metalui-app-shaders-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func markAsShaderDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("sha  k.comp.hlsl\n".utf8).write(to: directory.appendingPathComponent("SOURCE.sha256"))
}

@Suite struct SDLGPUShaderLibraryTests {
    /// **C5.** Reflection fills every count of the pipeline description, so an
    /// app never counts by hand, and each driver gets its own blob and entry.
    /// Mutation: the parser reads `readonly_storage_buffers` from the
    /// `readwrite_storage_buffers` key and the reverse.
    @Test func reflectionFillsEveryPipelineCount() throws {
        let library = try SDLGPUShaderLibrary(directory: GPUTestSupport.compiledShaders)
        let blob = try library.compute("append", driver: "vulkan")
        #expect(blob.samplers == 0)
        #expect(blob.readOnlyStorageTextures == 0)
        #expect(blob.readOnlyStorageBuffers == 0)
        #expect(blob.readWriteStorageTextures == 0)
        #expect(blob.readWriteStorageBuffers == 1)
        #expect(blob.uniformBuffers == 1)
        #expect(blob.threadCount.x == 64 && blob.threadCount.y == 1 && blob.threadCount.z == 1)
        #expect(blob.entryPoint == "main")
        #expect(blob.bytes == [UInt8](try Data(contentsOf: GPUTestSupport.compiledShaders.appendingPathComponent("append.comp.spv"))))
        let metal = try library.compute("append", driver: "metal")
        #expect(metal.entryPoint == "main0")
        #expect(metal.bytes == [UInt8](try Data(contentsOf: GPUTestSupport.compiledShaders.appendingPathComponent("append.comp.msl"))))
        let d3d = try library.compute("append", driver: "direct3d12")
        #expect(d3d.bytes == [UInt8](try Data(contentsOf: GPUTestSupport.compiledShaders.appendingPathComponent("append.comp.dxil"))))
    }

    /// A stage that is not there, or a driver SDL_GPU has no blob format for, is
    /// an error naming it, not a crash.
    @Test func aMissingStageOrDriverIsNamed() throws {
        let library = try SDLGPUShaderLibrary(directory: GPUTestSupport.compiledShaders)
        do { _ = try library.compute("nothing", driver: "vulkan"); Issue.record("found a missing kernel") }
        catch { #expect(String(describing: error).contains("nothing.comp.spv"), "\(error)") }
        do { _ = try library.compute("append", driver: "opengl"); Issue.record("accepted a driver") }
        catch { #expect(String(describing: error).contains("opengl"), "\(error)") }
    }

    /// **C6.** `MetalUIAppShaders` beside the executable wins, then the source
    /// tree the app passes; none is an error naming every directory tried and
    /// `SOURCE.sha256` (the `PX-P` order and shape). Mutation: swap the order.
    @Test func theShaderLibraryLooksBesideTheExecutableThenTheSourceTree() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let adjacent = root.appendingPathComponent("bin/MetalUIAppShaders")
        let tree = root.appendingPathComponent("tree/compiled")
        let candidates = SDLGPUShaderLibrary.candidates(
            directoryName: "MetalUIAppShaders", sourceTree: tree,
            executableDirectory: root.appendingPathComponent("bin"))
        #expect(candidates.map(\.path) == [adjacent.path, tree.path])
        try markAsShaderDirectory(adjacent)
        try markAsShaderDirectory(tree)
        #expect(try SDLGPUShaderLibrary.locate(from: candidates).directory.path == adjacent.path)
        try FileManager.default.removeItem(at: adjacent)
        #expect(try SDLGPUShaderLibrary.locate(from: candidates).directory.path == tree.path)
        // A directory without SOURCE.sha256 does not count.
        try FileManager.default.createDirectory(at: adjacent, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: tree.appendingPathComponent("SOURCE.sha256"))
        do {
            _ = try SDLGPUShaderLibrary.locate(from: candidates)
            Issue.record("found a directory with no SOURCE.sha256")
        } catch {
            let description = String(describing: error)
            #expect(description.contains(adjacent.path) && description.contains(tree.path), "\(description)")
            #expect(description.contains("SOURCE.sha256"), "\(description)")
        }
    }

    /// **C7.** The checked-in blobs belong to their source: every source's
    /// SHA-256 equals its `SOURCE.sha256` line, so a source edit without a
    /// rebuild is red on any machine (no shadercross needed). Mutation: add one
    /// byte to `append.comp.hlsl`.
    @Test func aCheckedInAppShaderBlobMatchesItsSource() throws {
        let listing = try String(contentsOf: GPUTestSupport.compiledShaders.appendingPathComponent("SOURCE.sha256"),
                                 encoding: .utf8)
        let lines = listing.split(whereSeparator: \.isNewline).map(String.init)
        try #require(!lines.isEmpty)
        for line in lines {
            let parts = line.components(separatedBy: "  ")
            try #require(parts.count == 2, "\(line)")
            let source = try Data(contentsOf: GPUTestSupport.sources.appendingPathComponent(parts[1]))
            #expect(SHA256Digest.hex(of: [UInt8](source)) == parts[0], "\(parts[1]) changed without a rebuild")
        }
        let sources = try FileManager.default.contentsOfDirectory(atPath: GPUTestSupport.sources.path)
            .filter { $0.hasSuffix(".hlsl") }
        #expect(Set(sources) == Set(lines.map { $0.components(separatedBy: "  ")[1] }), "every source is listed")
    }
}

/// SHA-256 (FIPS 180-4), for C7: Foundation has none off Apple platforms.
enum SHA256Digest {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

    static func hex(of message: [UInt8]) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var padded = message + [0x80]
        while padded.count % 64 != 56 { padded.append(0) }
        let bitLength = UInt64(message.count) * 8
        padded += (0..<8).reversed().map { UInt8(truncatingIfNeeded: bitLength >> UInt64($0 * 8)) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        for chunk in stride(from: 0, to: padded.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let o = chunk + i * 4
                w[i] = UInt32(padded[o]) << 24 | UInt32(padded[o + 1]) << 16 | UInt32(padded[o + 2]) << 8 | UInt32(padded[o + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var v = h
            for i in 0..<64 {
                let s1 = rotr(v[4], 6) ^ rotr(v[4], 11) ^ rotr(v[4], 25)
                let ch = (v[4] & v[5]) ^ (~v[4] & v[6])
                let t1 = v[7] &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(v[0], 2) ^ rotr(v[0], 13) ^ rotr(v[0], 22)
                let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2])
                let t2 = s0 &+ maj
                v = [t1 &+ t2, v[0], v[1], v[2], v[3] &+ t1, v[4], v[5], v[6]]
            }
            for i in 0..<8 { h[i] = h[i] &+ v[i] }
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    /// FIPS 180-4's own vectors, so a wrong digest is the finding, not the file.
    static var selfTest: Bool {
        hex(of: Array("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            && hex(of: []) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
}

@Test func theSHA256UsedByTheHashCheckMatchesTheStandardVectors() {
    #expect(SHA256Digest.selfTest)
}

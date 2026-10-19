import Testing
import MetalUICore
@testable import MetalUILayout

// P2 lane 1, tests 4 and 5 (`PA-D`): a leaf key's signature is computed at registration, with the same value.

nonisolated(unsafe) private var hashCalls = 0

private struct CountingKey: Hashable {
    let value: Int
    func hash(into hasher: inout Hasher) { hashCalls += 1; hasher.combine(value) }
}

private func leaf(_ tree: LayoutTree, _ key: AnyHashable) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }
}

/// Mutation: hash `key` again in `nodeSignature`.
@Test @MainActor func aLeafKeyIsHashedOncePerRegistrationNotOncePerRun() throws {
    hashCalls = 0
    let tree = LayoutTree(generation: 1)
    let a = leaf(tree, CountingKey(value: 7))
    let b = leaf(tree, CountingKey(value: 8))
    let root = tree.newNativeLinearStack(children: [a, b], axis: .vertical)
    let atRegistration = hashCalls
    #expect(atRegistration > 0, "the key is hashed where it is registered")
    var signatures: [LayoutSignature?] = []
    for _ in 0..<5 { signatures.append(tree.structuralSignature(of: root)) }
    #expect(signatures.allSatisfy { $0 != nil && $0 == signatures[0] })
    #expect(hashCalls == atRegistration, "five runs must not hash again; \(hashCalls) against \(atRegistration)")
    let captured = tree.captureSegment(from: 0, tops: [root])
    let segment = try #require(captured.segment)
    let other = LayoutTree(generation: 2)
    let grafted = other.graft(segment)
    #expect(other.structuralSignature(of: grafted[0]) == signatures[0])
    #expect(hashCalls == atRegistration, "a graft and its signature must not hash; \(hashCalls) against \(atRegistration)")
}

private struct Pair: Hashable { var a: Int; var b: String }

/// Mutation: swap `h1` and `h2` in `LeafKey.mix(into:)`.
@Test @MainActor func aCachedLeafKeySignatureEqualsTheDirectOne() throws {
    let keys: [AnyHashable] = [AnyHashable(3), AnyHashable("title"), AnyHashable(Pair(a: 1, b: "x")),
                               AnyHashable([1, 2] as [Int]), AnyHashable(CountingKey(value: 4))]
    for key in keys {
        var direct = SignatureBuilder()
        direct.mix(1)
        direct.mix(UInt64(UInt(bitPattern: ObjectIdentifier(type(of: key.base)))))
        direct.mixHashable(key)
        var cached = SignatureBuilder()
        LeafKey(key).mix(into: &cached)
        #expect(cached.signature == direct.signature, "\(key)")
        let tree = LayoutTree(generation: 1)
        let id = leaf(tree, key)
        #expect(tree.structuralSignature(of: id) == direct.signature, "\(key) through the tree")
    }
}

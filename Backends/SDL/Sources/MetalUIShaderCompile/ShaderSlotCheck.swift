import Foundation

/// A shader whose declared resource registers are not the set the compiler kept (ruling `UB-A`..`UB-H`,
/// XP-G36).
///
/// SDL_GPU binds uniform buffers, samplers and storage resources **by count from slot 0**
/// (`SDL_GPUShaderCreateInfo.num_*`, `SDL_PushGPU*UniformData(slot)`): the compiler drops a resource the
/// shader never reads, the reflected count falls below what the source declared, and every later slot
/// lands one position off, silently. The reflection gives counts only (shadercross's metadata has no
/// per-resource slot), so the information that detects the drop is the HLSL source's `register(...)` set
/// beside the reflected counts; this type compares the two. Pure functions over text, `package`.
package enum ShaderSlotCheck {
    /// The HLSL register class letter.
    package enum RegisterClass: Character, Sendable {
        /// `b`: a constant buffer, SDL_GPU's uniform buffer.
        case constantBuffer = "b"
        /// `t`: a sampled texture, read-only storage texture or read-only storage buffer.
        case texture = "t"
        /// `s`: a sampler.
        case sampler = "s"
        /// `u`: a read-write storage texture or buffer (compute only).
        case readWrite = "u"
    }

    /// One `register(bN, spaceM)` found in the source.
    package struct Declaration: Equatable, Sendable {
        package var registerClass: RegisterClass
        package var slot: Int
        package var space: Int
        /// The identifier before the colon (`Draw` in `cbuffer Draw : register(b0, space3)`), when there is one.
        package var name: String?
        /// Inside an `#if`/`#ifdef`/`#ifndef` region: whether it exists depends on defines this scan does not evaluate.
        package var conditional: Bool
        package var line: Int
    }

    /// The counts a reflection reports, in the reflection JSON's vocabulary (`SDLGPUShaderLibrary`).
    package struct Counts: Equatable, Sendable {
        package var samplers = 0, readOnlyStorageTextures = 0, readOnlyStorageBuffers = 0
        package var readWriteStorageTextures = 0, readWriteStorageBuffers = 0, uniformBuffers = 0

        package init(samplers: Int = 0, readOnlyStorageTextures: Int = 0, readOnlyStorageBuffers: Int = 0,
                     readWriteStorageTextures: Int = 0, readWriteStorageBuffers: Int = 0, uniformBuffers: Int = 0) {
            self.samplers = samplers
            self.readOnlyStorageTextures = readOnlyStorageTextures
            self.readOnlyStorageBuffers = readOnlyStorageBuffers
            self.readWriteStorageTextures = readWriteStorageTextures
            self.readWriteStorageBuffers = readWriteStorageBuffers
            self.uniformBuffers = uniformBuffers
        }

        /// Reads shadercross's JSON (`readonly_storage_*` or the graphics spelling `storage_*`); `nil` when it is not a JSON object.
        package init?(json: String) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
            func count(_ keys: String...) -> Int {
                for key in keys { if let value = object[key] as? Int { return value } }
                return 0
            }
            self.init(samplers: count("samplers"),
                      readOnlyStorageTextures: count("readonly_storage_textures", "storage_textures"),
                      readOnlyStorageBuffers: count("readonly_storage_buffers", "storage_buffers"),
                      readWriteStorageTextures: count("readwrite_storage_textures"),
                      readWriteStorageBuffers: count("readwrite_storage_buffers"),
                      uniformBuffers: count("uniform_buffers"))
        }
    }

    /// A source containing this text opts out (a register set the scan cannot read, UB-F).
    package static let optOut = "metalui-allow-register-mismatch"

    /// SDL_GPU's HLSL register spaces (SDL_gpu.h, `SDL_CreateGPUShader`): resources, read-write resources, uniforms.
    package static func spaces(for stage: ShaderStage) -> (resources: Int, readWrite: Int?, uniforms: Int) {
        switch stage {
        case .vertex: (0, nil, 1)
        case .fragment: (2, nil, 3)
        case .compute: (0, 1, 2)
        }
    }

    // MARK: Scanning

    /// `source` with `//` and `/* */` comments blanked (newlines kept, so line numbers hold).
    package static func strippingComments(_ source: String) -> String {
        var out = String.UnicodeScalarView()
        let scalars = Array(source.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "/" {
                while index < scalars.count, scalars[index] != "\n" { index += 1 }
            } else if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "*" {
                index += 2
                while index < scalars.count, !(scalars[index] == "*" && index + 1 < scalars.count && scalars[index + 1] == "/") {
                    if scalars[index] == "\n" { out.append("\n") }
                    index += 1
                }
                index += 2
                out.append(" ")
            } else {
                out.append(scalar)
                index += 1
            }
        }
        return String(out)
    }

    private static let registerPattern = try! NSRegularExpression(
        pattern: #"(?:(\w+)\s*:\s*)?register\s*\(\s*([bstu])(\d+)\s*(?:,\s*space(\d+)\s*)?\)"#)

    /// Every `register(<b|t|s|u>N[, spaceM])` in `source` outside comments, in source order.
    package static func declarations(in source: String) -> [Declaration] {
        let text = strippingComments(source)
        var found: [Declaration] = []
        var depth = 0
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let directive = line.drop(while: { $0 == " " || $0 == "\t" })
            if directive.hasPrefix("#") {
                let word = directive.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
                if word.hasPrefix("ifdef") || word.hasPrefix("ifndef") || word.hasPrefix("if") { depth += 1 }
                else if word.hasPrefix("endif") { depth = max(0, depth - 1) }
            }
            let ns = line as NSString
            for match in registerPattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                guard let letter = ns.substring(with: match.range(at: 2)).first, let kind = RegisterClass(rawValue: letter),
                      let slot = Int(ns.substring(with: match.range(at: 3))) else { continue }
                let space = match.range(at: 4).location == NSNotFound ? 0 : Int(ns.substring(with: match.range(at: 4))) ?? 0
                let name = match.range(at: 1).location == NSNotFound ? nil : ns.substring(with: match.range(at: 1))
                found.append(Declaration(registerClass: kind, slot: slot, space: space, name: name,
                                         conditional: depth > 0, line: offset + 1))
            }
        }
        return found
    }

    // MARK: Checking

    /// The problems with `source` (named `name`, of `stage`) against `counts`, one text each; empty when the
    /// declared registers are the contiguous set the reflection kept (or only exceed it where this scan is blind:
    /// an `#include`d header's registers are not read, so a reflected count above the declared one is not a finding).
    package static func problems(name: String, stage: ShaderStage, source: String, counts: Counts) -> [String] {
        if source.contains(optOut) { return [] }
        let all = declarations(in: source)
        let anyConditional = all.contains { $0.conditional }
        let spaces = spaces(for: stage)
        var problems: [String] = []

        func check(_ kind: RegisterClass, space: Int, noun: String, reflected: Int, reflectedWhat: String) {
            let declared = all.filter { $0.registerClass == kind && $0.space == space }
            let certain = declared.filter { !$0.conditional }
            let slots = Set(declared.map(\.slot)).sorted()
            let letter = String(kind.rawValue)
            let list = declared.map { "\(letter)\($0.slot)" + ($0.name.map { " `\($0)`" } ?? "") }.joined(separator: ", ")
            let hint = "SDL_GPU binds \(noun)s by count from slot 0, so the compiler dropping one that the shader never reads "
                + "shifts every later slot by one: values pushed or bound at those slots reach the wrong resource, with no error. "
                + "Read every declared \(noun) in the shader (or delete the unread one) and keep the registers contiguous from \(letter)0."
            if !anyConditional, !slots.isEmpty, slots != Array(0..<slots.count) {
                problems.append("\(name): declares \(noun) registers \(slots.map { "\(letter)\($0)" }.joined(separator: ", ")) in space\(space) "
                    + "with a gap; SDL_GPU numbers them from slot 0 without gaps. Renumber them to "
                    + "\(Array(0..<slots.count).map { "\(letter)\($0)" }.joined(separator: ", ")).")
            }
            let sure = Set(certain.map(\.slot)).count
            if sure > reflected {
                problems.append("\(name): the source declares \(sure) \(noun)(s) in space\(space) (\(list)) but the compiled shader "
                    + "reflects \(reflected) (\(reflectedWhat)); \(sure - reflected) was dropped as unused. \(hint)")
            }
        }
        check(.constantBuffer, space: spaces.uniforms, noun: "uniform buffer", reflected: counts.uniformBuffers,
              reflectedWhat: "uniform_buffers")
        check(.sampler, space: spaces.resources, noun: "sampler", reflected: counts.samplers, reflectedWhat: "samplers")
        check(.texture, space: spaces.resources, noun: "sampled texture or read-only storage resource",
              reflected: counts.samplers + counts.readOnlyStorageTextures + counts.readOnlyStorageBuffers,
              reflectedWhat: "samplers + read-only storage textures + read-only storage buffers")
        if let readWrite = spaces.readWrite {
            check(.readWrite, space: readWrite, noun: "read-write storage resource",
                  reflected: counts.readWriteStorageTextures + counts.readWriteStorageBuffers,
                  reflectedWhat: "read-write storage textures + read-write storage buffers")
        }
        return problems
    }
}

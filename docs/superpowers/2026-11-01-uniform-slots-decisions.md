# Dropped register slots (XP-G36) - decisions

Rulings for item `XP-G36` (MetalCreator 2026-11-01, logged there as its "XP-G28"; MetalUI's XP-G28 is precise scroll). Prefix `UB-`.
**Next unused: `UB-I`.** Record: `../record/182-uniform-slots.md`. Branch `fix/uniform-slot-gaps` from master `294a099b`.
Divergence labels 965-974 reserved: **none taken** (`UB-A`). Nothing is published (`BS-H`).

Sources of truth. SwiftUI has no shader registers: no SwiftUI claim, no probe. SDL_GPU's own rule is the authority: `SDL_GPUShaderCreateInfo`
takes `num_samplers`, `num_storage_textures`, `num_storage_buffers`, `num_uniform_buffers`, and `SDL_PushGPU*UniformData(slot)` addresses a
buffer by position, so resources are bound **by count from slot 0** in the HLSL spaces SDL_gpu.h documents (vertex: resources space0, uniforms
space1; fragment: space2, space3; compute: read-only space0, read-write space1, uniforms space2).

## UB-A - class M, no divergence, no census row

**Ruling.** MetalUI-only tooling (class `M`): no public Swift declaration is added (`ShaderSlotCheck` is `package` in `MetalUIShaderCompile`; the
run-time path reuses the existing `compileFailed` case), so no census row and none of 965-974 is taken. **Cost if wrong.** A map row.

## UB-B - what reflection gives, and so where the check lives

**Ruling.** shadercross's metadata (`SDL_ShaderCross_GraphicsShaderMetadata` / `ComputePipelineMetadata`, the JSON beside each blob, the
`MuiRSCReflection` mirror in `CShaderCross.c`) is **counts only**: `samplers`, `storage_textures`/`storage_buffers` (graphics JSON) or
`readonly_*`/`readwrite_*` (compute), `uniform_buffers`. There is no per-resource slot, so which register was dropped cannot be read from the
reflection. The information that detects the drop is the HLSL source's `register(<b|t|s|u>N[, spaceM])` set beside those counts, and it exists
where the source and the counts meet: the tool after it writes the JSON, the build plugin's copy arm (the checked-in blobs' sources are in the
package), and the run-time compute compile. **Measurement caveat.** No shadercross binary was available to this change, so the counts above are
read from the mirror structs and from every checked-in `.json` (`Backends/SDL/Tests/AppShaders/compiled`), not from a fresh shadercross run; the
`t`-register relation (UB-C) was verified against those checked-in pairs (test `everyCheckedInAppShaderPassesItsOwnReflection`).
**Cost if wrong.** A false refusal, which the opt-out (`UB-F`) lifts.

## UB-C - the comparison

**Ruling.** `ShaderSlotCheck.problems(name:stage:source:counts:)` is a pure function. Per class, in the stage's space: `b` against
`uniform_buffers`; `s` against `samplers`; `t` against `samplers + read-only storage textures + read-only storage buffers` (SDL numbers sampled
textures first, then storage); `u` (compute) against read-write textures plus buffers. Two findings: (1) **dropped** - more distinct unconditional
declared slots than reflected; (2) **gap** - the declared slots are not `0..<n`. **One-sided:** a reflected count *above* the declared one is
not a finding, because a header's registers are not read (`#include` is not followed). **Cost if wrong.** A missed drop for a register declared
only in a header.

## UB-D - where it fails

**Ruling.** (1) `ShaderCompiler.run` (the `compile-shaders` command and the plugin's compile arm) throws a `ShaderCompileError` after the JSON is
written, one `error:` line per finding. (2) `runOnBuild`'s copy arm (no shadercross) checks each source against its checked-in `.json` before
copying. (3) `RuntimeShaderCompiler.compileCompute` throws `RuntimeShaderCompileError.compileFailed(stage: "register slot check", ...)` (and so
`SDLGPUShaderCompileError.compileFailed`), no new case, and nothing is returned for a dropped slot. **Cost if wrong.** An exhaustive-switch break
if a case had been added; none was.

## UB-E - the blob format is unchanged; the pipeline calls do not check

**Ruling.** `compileGraphicsPipeline`/`compileShader` take a blob (bytes plus counts) and **cannot** know the declared slots, so they do not
check, and the `.json` gains no field: adding one would break the byte-for-byte oracle (`BS-B`) against checked-in blobs that could not be
regenerated here. A bad blob never reaches them from the tool or the plugin (UB-D). `GB-G` is untouched: nothing new is read on another thread.
**Carried.** A `declared_registers` key written by the tool, so a library-loaded blob can be checked at `makeGraphicsPipeline`; do it with the
next regeneration of the checked-in blobs.

## UB-F - what the scan does not count, and the opt-out

**Ruling.** Comments are blanked. A register inside `#if`/`#ifdef`/`#ifndef` is conditional: it neither makes a gap nor counts as certainly
declared. Macro-built registers are not matched. A source containing the text `metalui-allow-register-mismatch` (in a comment) is skipped
entirely, for a shader the scan misreads. **Cost if wrong.** A drop under `#if` is missed.

## UB-G - the message

**Ruling.** Names the shader file, the count declared and reflected, every declared register with its identifier, why it matters, and the fix:
"zebra_mesh.frag.hlsl: the source declares 4 uniform buffer(s) in space3 (b0 `Draw`, b1 `Shade`, b2 `Clip`, b3 `Zebra`) but the compiled shader
reflects 3 (uniform_buffers); 1 was dropped as unused. SDL_GPU binds uniform buffers by count from slot 0, ... Read every declared uniform buffer
in the shader (or delete the unread one) and keep the registers contiguous from b0." A gap reads "declares uniform buffer registers b0, b2 in
space3 with a gap; ... Renumber them to b0, b1." `docs/packaging.md` 4a repeats the rule.

## UB-H - tests and the unmeasured

**Ruling.** `ShaderSlotCheckTests` (root, portable, no shadercross; `Tests/MetalUIShaderCompileTests`) pins the report's b0..b3 fixture, its
contiguous control, the gap, samplers/textures/storage, comments, conditionals, the opt-out, both JSON spellings, the tool's compile and copy
arms through a stub runner, and the checked-in corpus. The run-time arm has a gated test (`METALUI_SHADERCROSS_LIB`) that **was not run**: no
shadercross here. Unmeasured: a fresh shadercross's counts for the report's shader on Metal, Vulkan and D3D12 (the report says 3 on Metal),
the compile arm against a real shadercross, Windows.

# 182 - dropped register slots (`UB-A`..`UB-H`)

2026-11-01, branch `fix/uniform-slot-gaps` from master `294a099b`; item XP-G36 (MetalCreator's own "XP-G28", renamed: MetalUI's XP-G28 is precise
scroll). Rulings: `docs/superpowers/2026-11-01-uniform-slots-decisions.md`.

## 1. The report

SDL_GPU binds uniform buffers (and samplers, storage) by count from slot 0. MetalCreator's `zebra_mesh.frag.hlsl` declared `Draw b0`, `Shade b1`,
`Clip b2`, `Zebra b3` (space3) and never read `Draw`; the compiler dropped b0, the reflected count became 3, and every push landed one slot off:
stripes rendered as plain shading, no error.

## 2. What reflection gives (UB-B)

Counts only (no per-resource slot): the JSON keys, the `SDL_ShaderCross_*Metadata` structs mirrored in `Sources/CShaderCross/CShaderCross.c`.
No shadercross binary was present on this machine (`which shadercross`, a disk search for `libSDL3_shadercross*`), so nothing was re-measured; the
counts relation was calibrated against the 10 checked-in app-shader source/JSON pairs, which all pass.

## 3. Design

`ShaderSlotCheck` (`MetalUIShaderCompile`, pure): HLSL `register(...)` scan (comments blanked, `#if` regions marked conditional) against the
counts in the stage's SDL_GPU spaces; findings are a dropped slot (declared above reflected) and a source gap. Wired into the tool's compile arm
(`ShaderCompiler.run` via `checkSlots`), the plugin's copy arm, and `RuntimeShaderCompiler.compileCompute` (`compileFailed(stage: "register slot
check")`). The blob JSON is unchanged (UB-E), so `makeGraphicsPipeline` cannot check; carried.

## 4. Tests and counts

`ShaderSlotCheckTests` (9 tests): UB-1..UB-9 in the file. Before the fix the fixture compiled through `run` with 3 reflected buffers without
complaint (mutation 1 reproduces that); after, it throws. Root, `swift build --build-system native --build-tests` then
`swift test --build-system native --no-parallel`: **4702 tests in 12 suites passed**, `FR-J no-argument frame: succeeded=true` printed. Under
`Backends/SDL`, `--filter 'SDLGPU|SDLShaderDirectory'`: 104 tests in 12 suites, one failure outside this change
(`thePublicLocateDoesNotEvaluateItsBundleWhenTheExecutableCandidateOpens` writes beside the test runner inside the Xcode toolchain, permission
denied); the new gated run-time test `aKernelWhoseDeclaredUniformBufferIsDroppedIsRefused` was skipped (no shadercross).

## 5. Mutations (`swift test --no-parallel --filter MetalUIShaderCompileTests`)

| Mutation | Reddened |
|---|---|
| `run` without the `checkSlots` call | `theCompileRunFailsOnADroppedSlotAndPassesTheControl` |
| copy arm without the check | `theCopyArmChecksCheckedInBlobsAgainstTheirSources` |
| `sure > reflected` to `>=` | `aDroppedUniformBufferIsNamedWithItsRegisters`, `aContiguousFullyReadSetPassesAndTheSpaceSelectsTheStage`, `aGapInTheDeclaredSetIsRefused`, `commentsConditionalsHeadersAndTheOptOutAreNotFindings` |
| `t` compared with `samplers` only | `droppedSamplersTexturesAndStorageAreNamedToo`, `everyCheckedInAppShaderPassesItsOwnReflection` |
| conditional registers counted as certain | `commentsConditionalsHeadersAndTheOptOutAreNotFindings` |
| comments not stripped | `commentsConditionalsHeadersAndTheOptOutAreNotFindings` |
| vertex uniform space 1 to 3 | `aContiguousFullyReadSetPassesAndTheSpaceSelectsTheStage` |

Not mutated (needs shadercross): the run-time arm.

## 6. Unmeasured

A fresh shadercross's counts for the report's shader on Metal, Vulkan and D3D12; the compile arm against a real shadercross; Windows.

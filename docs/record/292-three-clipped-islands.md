# 292. Three clipped islands (`CT-D`)

Branch `fix/three-clipped-islands` from master `eb8d4b8c`. Alloy report: `.clipShape(RoundedRectangle(cornerRadius:))` on all three lower islands of one `HSplitView` crashed the first frame (`EXC_BAD_ACCESS` in `swift_retain`); extracting the row into a component hid it. Class M, no divergence.

## Task 1: the crash did not reproduce

Alloy `feat/islands` ebe228d copied to scratch (the row inlined back into `AlloyScreen`, all three islands clipped), built against this branch:

- debug, release (`-c release -enable-testing`) and Address Sanitizer: `IslandsTests` (10 tests) and a first-frames probe pass; the window renders through the Metal renderer (`snapshot()`) at 1x and 2x; no crash.
- Address Sanitizer reports one finding in a Metal frame of the rich window, a benign over-read: `Renderer.blur`'s `setFragmentBytes(&constants, length: stride)` reads 32 bytes of a 24-byte `BackdropBlurPass` (the struct's tail padding). Not the reported crash. **Fixed in this branch:** the bytes now go through a zeroed 32-byte buffer (the shader's struct layout is unchanged; no SDL or HLSL counterpart exists, and `GroupTintPass` is 32 bytes whole). Red before: `BackdropRenderTests`, `GroupFilterRenderTests` and `GlassRenderTests` under `--sanitize=address` reported the stack-buffer-overflow at that call; after: those suites and `BackdropBlurReferenceTests` pass with Address Sanitizer clean.
- Stack: the first frame peaks at about 650 KB of the 8 MB main stack in debug (empty workspace) and about 1.3 MB for a window with a file open, chat and Metal snapshot; `ulimit -s` shows 1 MB too small and 1.5 MB enough. A synthetic `Component`+`VStack`+`clipShape` nest costs about 22 KB per level in debug (8 levels 209 KB, 16 levels 384 KB, 32 levels 736 KB; the 64-level run exited with a signal and was not investigated). Work is on the main thread (`@MainActor`).
- Alloy's follow-up reports the same crash with no clip and with the row extracted, in a value-witness copy of `IslandBackdrop` (`AppearanceStyle` gained fields), which points at a stale incremental build (being verified with a clean build on their side). No MetalUI change.
- `ThreeClippedIslandsTests` keeps the Alloy-shaped window (`HSplitView`, hidden divider, three clipped panes of rows, a `CodeView`, a `TextField`, glass and material backgrounds, scale 2) as a first-frames guard.

## Task 2: what a rounded island clip costs

- The island clip itself is per primitive (a rounded rect's own mask); it builds no group. A flush nested rounded clip (smaller radius, same box) is exact too (`CM-B`'s containment cases): 0 groups.
- A masked group appears only where an inner **clip** genuinely crosses the island's: in Alloy's rich window, 1 group (a 1062 x 455 device-pixel box, the chat's code block) and one mask pass.
- GPU time (Metal command buffer `gpuEndTime - gpuStartTime`, median of 30 offscreen encodes of the headless frame at 2x, 2400 x 1600, with material backgrounds): rich Alloy window 3.73 ms with the island clips (1 group) against 3.53 ms without (0 groups). A synthetic worst case (three islands each holding a 6-pt rounded clip pushed 4 pt over the island's edge, 60 rows and 200 code lines): 2481 groups and 2481 masks, 103 ms against 3.19 ms with no crossing clip. A crossing makes **one masked group per leaf of the clipped scope** (a group the leaf's size, a mask scratch of the same size, content, mask and composite passes), not one per island.
- What would avoid it (not implemented): `Frame.clipsCross` decides at the clip's push, from the whole scope's box. Deciding per leaf, with the leaf's box against the two clips' corner cuts (`boxReachesACornerCut`), would leave every leaf clear of the cuts under its own per-primitive mask and group only those that reach a corner.

## Task 3: `TestWindow.allRects`, `allImages` (`CT-D`)

See `docs/superpowers/2026-11-13-clip-theme-key-glyphs-decisions.md`. `AllRectsTests`; inventory row extended.

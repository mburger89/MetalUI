# SDL GPU scene replay experiment

An isolated feasibility probe, outside the production package. It consumes the
existing `Scene`, shader structs, and CPU `GlyphAtlas` through their public APIs.
No production source or root package dependency is changed.

## Run on macOS

Requires the repository's Swift 6.3 toolchain, a Metal-capable Mac, and SDL3
available through `pkg-config` (`brew install sdl3 pkg-config` if needed).

From this directory:

```sh
swift run --build-system native Replay
swift run --build-system native Replay --show
```

`--show` displays the final SDL render in a resizable window for up to 30 seconds.
Closing it ends presentation early. Resizing scales the captured scene; it does
not run MetalUI layout. `REPLAY_OUTPUT=/absolute/path` chooses the artifact folder
(default: `output` relative to the working directory). Do not run alongside a
performance measurement: the probe compiles shaders and waits for GPU readback.

## What the probe measures

- The production Metal renderer and SDL GPU receive the same finalized scene,
  primitive bytes, atlas bytes, projection and non-sRGB BGRA target format.
- Four frames exercise fractional edges, rounded borders, rounded clipping,
  translucent overlap, interleaved rect/glyph runs, new glyphs after frame zero,
  two target sizes, and a non-identity projection.
- Every BGRA channel is compared. The pass threshold permits at most one UNORM
  step of rounding. The log reports differing pixels and maximum channel delta;
  PNGs retain both outputs.
- A deliberate SDL-only ordering mutation paints all rectangles before all text.
  The probe requires more than 100 changed pixels and a channel difference over
  16. This proves the comparison sees a broken backend, rather than merely
  comparing two blank or identical reference images.

## Deliberate limits

This is **SDL's Metal backend**, explicitly selected, not a Vulkan or Direct3D 12
implementation. It adapts the existing MSL shader resource bindings and changes
its atlas sampling to an explicit normalized sampler. The shader math remains
shared, so this does not independently validate the math or prove shader
translation to SPIR-V/DXIL.

Text still uses MetalUI's CoreText implementation. The portable-looking C bridge
is not a claim that the Swift package builds outside macOS. No `App`, `Window`,
platform input or accessibility integration exists here.

Each diagnostic frame allocates/uploads resources, waits for a GPU fence, and
reads pixels back. The SDL device and pipelines persist; primitive buffers and
atlas textures do not. Thus repeated frames test refreshed atlas contents and
resource cleanup, **not** asynchronous atlas updates, frames in flight, sustained
throughput, or buffer pooling. This is not a performance benchmark.

The C entry points are a private trusted-fixture interface: callers supply valid
primitive bytes and draw-run ranges from a finalized `Scene`. They are not a
validated public renderer API.

## Next experiments

1. Author a shared portable shader source and compile to SPIR-V and DXIL using
   SDL shader tooling. Verify struct layout, bindings, sample coordinates and
   the same readback corpus on native Windows/Linux hardware.
2. Extract the scene/atlas transport into a module without Metal/CoreText imports,
   then replay a serialized fixture without building the Apple UI stack.
3. Add asynchronous resource lifetime and atlas-update stress cases before
   benchmarking or integrating with `Window`.
4. Introduce a renderer protocol only after the two implementations establish
   what the boundary needs. Keep layout/state/identity out of this interface.
5. Pursue native text, platform windows/input, and accessibility separately.

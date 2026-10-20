# raster-overscan probes (P4, record 124)

Prof scenarios for shadow, blur and full-gradient rasters. Dated measurements, never pins (a pin counts work).

- `shadow-pan`: a 6 x 4 grid of shadowed, blurred and radial-gradient cards in a 420 x 260 `.clipped()` region at scale 2,
  panned by whole points (whole device pixels) each frame.
- `shadow-drag`: the same grid, static, with one card changing width each frame.
- `counters.sh <checkout>`: 88 steps, total rasterized, blurred and tinted pixels and textures made (debug build with
  `-enable-testing`, any checkout). `ab.sh <baseline> <head> [rounds] [secs]`: alternated release ms/frame and the main-thread
  allocations of 400 frames. Baseline: `git archive 4d91f27f | tar -x -C <dir>`.

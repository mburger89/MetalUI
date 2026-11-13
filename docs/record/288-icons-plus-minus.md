# 288. `plus` and `minus` for Linux and Windows (`SYM-R`)

Branch `feat/icons-plus-minus`. MetalCreator gap ICON-a: `Image(systemName: "plus")` drew nothing on SDL. Class M, no new divergence (230 covers the Lucide stand-in look).

- **Mapping.** `plus` -> Lucide `plus`, `minus` -> Lucide `minus`, through `BundledSymbols.table`; `scripts/vendor-lucide.py` `ICONS` gains the two names and `LucideData.swift` is regenerated from the same pinned 1.70.0 tarball (sha256 `3d1f09df...120f16a`, re-verified): 53 icons, 787 opcodes, 2966 coordinates. Both are on the Feather list in `LICENSE` (MIT portion), recorded in `VENDORED.md` and `THIRD-PARTY-NOTICES.md`.
- **Not added.** `plus.circle` / `minus.circle` (Lucide has `circle-plus` / `circle-minus`, a two-row change if requested). No accessibility labels: the label table is a probe's reading and holds no SwiftUI label for either name, so none is invented.
- **Tests** (`PortableIconTests`): `alloyNames` is 53; the vendored count is 53; new `plusAndMinusResolveAndDrawOnTheBundledRoute`.
- **Mutation** (`swift test --filter PortableIcon`, restored): **M288a** the `minus` row dropped: the new test and `everyAlloyNameIsABundledIconInsideItsViewBox` redden.

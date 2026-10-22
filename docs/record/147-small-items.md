# 147 — Small items: IH-K, SN-L, P3c measured and carried

Branch `feat/small-items` from `1c53976d`. **Not a plan task**: round 2 item 9 of the gpui-gap list (user request 2026-10-21). Spec
`docs/superpowers/specs/2026-10-22-small-items-design.md`; rulings `SM-A`…`SM-E` in `docs/superpowers/2026-10-22-small-items-decisions.md`
(next unused `SM-F`); probes `docs/probes/stb-callback-eof.c`, `stb-phase-split.c`, `sdl-activation-token.sh`. Divergence labels 765-774: none taken.

## §1 Design phase

Each item was measured before any code.
- **IH-K.** stb's callback reader on a 2048² PNG/JPEG: PNG yields `NULL` on any early EOF, JPEG yields a **full-size zero-filled image** after the
  header; a cancel saves nothing on PNG (IDAT is read before inflating) but about two thirds of a JPEG decode on an early cancel (checker's re-measurement; the
  first reading, 2.7 % / 0.8 %, timed `fread`, not the callback). Carried (`SM-A`), now resting on PNG, the partial JPEG image and no caller.
- **SN-L.** SDL 3.4.16: `Wayland_RaiseWindow` requests a fresh token; `XDG_ACTIVATION_TOKEN` is read only at a new window's first show and at
  export/`SDL_OpenURL`. A forwarded token has no consumer. Carried (`SM-B`); `SN-H`'s "its own environment only" is refined. D-Bus carried (`SM-C`).
- **P3c.** Record §118's 6 % tint share stands; no `shadercross`/`dxc` on the machine, so `replay.hlsl` blobs cannot be regenerated. Carried (`SM-D`).

No source, shader, test, public declaration, census row or divergence changed; counts unmoved (4307 tests in 3 suites at `1c53976d`, not re-taken).
The Implement phase has nothing to build; the Record phase owes CLAUDE.md a rule of one or two sentences (the three carried items with their ids)
and `docs/record/README.md` a row.

# MetalUI

A GPU-accelerated UI framework for Swift, modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui), written as
idiomatic Swift, with SwiftUI as the design authority. **Supported: macOS
(AppKit + Metal, the default), Linux and Windows** (`Backends/SDL`,
`App(platform:textSystem:)`, the portable text system; `XP-A`/`XP-B`,
`docs/superpowers/plans/2026-09-23-cross-platform-roadmap.md`). **iOS, iPadOS, tvOS, watchOS
and visionOS are an explicit product boundary** (`PB-A`, record §65): no UIKit
conformer, no touch, no safe areas, none planned.

**This file is rules only.** The full 2026-10-01 version (177 KB: every
milestone summary, count history, renumbering note, guard-by-guard tally and
per-stage narrative) is frozen verbatim at
`docs/record/69-claude-md-full-2026-10-01.md`; older snapshots are record §19
(2026-09-21) and §67 (counts history). Reasoning and history live in
`docs/record/` (`README.md` indexes it, one row per milestone). Citations in
the record were not all re-checked after later refactors — verify a test name
or grep before relying on it. **New milestones append their record to
`docs/record/` and add only the rule to its area's shard in `docs/rules/`** —
one or two sentences, not a summary.

`AGENTS.md` is a byte-identical copy for Codex (the shards are shared): edit `CLAUDE.md`, then
`cp CLAUDE.md AGENTS.md`; `cmp CLAUDE.md AGENTS.md` before committing.

## Where things are

- **Design spec (binding):** `docs/superpowers/specs/2026-08-24-metalui-design.md`;
  per-milestone specs and plans in `docs/superpowers/specs/` and `plans/`.
  SwiftUI-alignment plan: `docs/superpowers/plans/2026-09-12-swiftui-alignment.md` (tasks 1–15;
  12 and 15 wait on human checks). **The source is the authority** over the
  2026-09-12 kernel/modifier specs.
- **Decisions docs:** `docs/superpowers/<date>-<milestone>-decisions.md`, or a
  milestone's own spec for prefixes without one. Read their "Carried…"
  sections before new work. Ruling ids are namespaced by prefix; **the prefix →
  document → next-id list is `docs/rules/decision-prefixes.md`** (a new prefix adds
  its row there). **To find the next unused id, read the file's last `## <PREFIX>-`
  heading, not its header** — headers have lagged. A decisions doc's "next unused"
  line moves in the commit that appends the ruling. A numbered citation of a
  lettered prefix (`LR-3`, `DN-3`, `AI-3`) is a typo.
- **Record:** `docs/record/NN-*.md`, one per milestone. When two lines publish
  the same number, the later merge renumbers and says so in its header.
- **SwiftUI probes:** `docs/probes/`; headers carry recorded output and how to
  run them (`SA-O`). Window captures: `docs/probes/window-capture/capture.sh`.
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests.
- **Public documents:** `docs/api-overview.md`, `docs/divergences.md` (every
  live SwiftUI difference — **220 live, next label 241** (232–234 and 237–240 used by `VT` (235 and 236 are the gesture rows), 230–231 used by `SYM-I`/`SYM-J`, 227–229 used by `SYM-C`/`SYM-H`, 226 used by `DSA-A`, 224 used by `CM-H`, 225 used, 91 and 92 retired by `CM-A` and `CM-B`, 109 retired by `TZ-B`, 217 used by `FC-G`, 218 by `LI-G`, 219 by `VF-D`, 220 by `VF-E`, 221 (retired by `GF-A`) and 222 by `GO-H`, 223 by `GF-H`, 1066 retired by `GF-A`; 1075–1084 reserved by AD: 1075, 1076, 1078 and 1079 used and 1077 and 1080–1084 unused; 1065–1074 reserved by PJ: 1065–1069 used (1066 retired) and 1070–1074 unused; 1055–1064 reserved by DE: 1055, 1056 used and 1057–1064 unused; 1045–1054 reserved by LD: 1045 used, 1046–1054 unused; 1035–1044 reserved by AE: 1035, 1036 used and 1037–1044 unused; 1025–1034 reserved by LB: 1025 and 1026 used, 1027–1034 unused; 1015–1024 reserved by PH: unused; 995–1004 reserved by TM: none used; 985–994 reserved by GL: unused; 975–984 reserved by SS: 975–977 used and 978–984 unused; 945–947 used and 948–954 unused by PG; 915–916 used and 917–924 unused by SP; 925 used and 926–934 unused by GE; 935 used and 936–944 unused by SV-AO; 895–898 used and 899–904 unused by MG; 885–894 reserved by BY: 885 (retired) and 886 used, 887–894 unused; 207 never published and unused; 209 used by `SV-AM`; 210 retired by `ER-A`, 211 and 212 used by `ER-C`; 120 and 255 retired and 745–754 unused by LH; 735–737 used and 738–744 unused by BG; 705–714 unused by DT; 625–634 unused by C14-i; 635–638 used and 639–644 unused by L1; 645, 646 used and 647–654 unused by G1; 655–664 unused by E1; 665–674 unused by S11; 675–684 unused by S12; 685–694 unused by XP-G21; 695–704 reserved by C14-j; 715–717 used and 718–724 unused by CP; 455, 456 used by S3; 465 used and 466–474 unused by S4+S8; 425, 426 used and 427–434 unused by S1; 435 used and 436–444 unused by S2; 345–354 reserved by C14: 346 used, 345 refuted, 347–354 unused; 196–204 unused by C12, 213 and 214 used by `DS-I`, 215 and 216 used by `VA-F`, item 8's reservation (215–224, never published) released from 217 on, 226–234 unused by C15, 241–244 unused by C16, 256–264 unused by C20, 250–254 unused by C21, 267–274 unused by C25, 278–284 unused by C22, 285–294 unused by C24, 295–296 used and 297–304 unused by C23, 305–314 unused by C26, 315 used and 316–324 unused by C27, 325–326 used and 327–334 unused by C28, 189–194 unused by C9); retired labels are
  never reused), `docs/migration.md`, `THIRD-PARTY-NOTICES.md` (licences of the vendored C code, the bundled Lucide icons and SDL3/AccessKit, per product), `docs/verification/human-checks.md`
  (groups A–Y, CC, EC, EL, BG, VL, RT, WS, AS, CL, KF, PF, SG, HT, OV, IF, BB, WD, SL, GC, GT, RF, MT, IM, GD, IV, GA, SB, HP, IB, CW, CB, IC, RK, SI, RO, FS, RG, AT, RL, AP, EX, GB, GS, BS, LZ, RZ, DT, CP, BG, LG, TL, TP, HX, BT, WA, FO, BY, MG, DX, GE, SP, PG, WI, SS, GL, TM, SD, PH, LB, AE, LD, DE, PJ, AD, SR, LS, DS, XF, VA, LI, VF, CM, TG, CV, SYM (SYM1-SYM7), BM (BM1-BM5), TBS (TBS1-TBS6), HL (HL1-HL5), MIP (MIP1-MIP3) and TBH (TBH1-TBH7), **not run — an agent cannot**), `docs/verification/voiceover-script.md`.
- **Public-API inventory:** `docs/probes/closeout-public-api.sh` censuses every
  public declaration; `closeout-inventory-map.tsv` classifies each (A
  SwiftUI-aligned / D divergence / M MetalUI-only / X deprecated / R absent).
  **A new public declaration owes a map row and a doc comment**:
  `zsh docs/probes/closeout-inventory-check.sh` and
  `zsh docs/probes/closeout-undocumented.sh` both print nothing when complete.

## Build and test

```bash
swift build
swift test --no-parallel
swift build --build-system native --build-tests && swift test --build-system native --no-parallel  # guards run
swift run MetalUIDemo            # and -c release
METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo   # value exactly "1"
# also METALUI_TEXT_INPUT_DEMO=1, METALUI_CONTROLS_DEMO=1, METALUI_DND_DEMO=1, METALUI_LOOKS_DEMO=1, METALUI_METALVIEW_DEMO=1, METALUI_MENUS_DEMO=1, METALUI_SERVICES_DEMO=1, METALUI_LIST_DEMO=1, METALUI_RICH_TEXT_DEMO=1, METALUI_CANVAS_DEMO=1, METALUI_APP_SHELL_DEMO=1, METALUI_SELECTION_DEMO=1, METALUI_INVALIDATION_DEMO=1, METALUI_RETAINED_DEMO=1, METALUI_CHROME_DEMO=1, METALUI_CLIPBOARD_DEMO=1, METALUI_LAZY_DEMO=1, METALUI_CODE_DEMO=1, METALUI_MARKDOWN_DEMO=1, METALUI_TABS_DEMO=1
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
```

- **Counts (2026-11-09, `feat/textfield-offsets-prompt` on master 1b281127 + record 261): root 5805 tests in 26 suites passed (`--build-system native`, unfiltered, `--no-parallel`; 0 failures), 0 goldens; `FR-J no-argument frame: succeeded=true`; guards 21 and 22 ran (`VERTICAL FIELD GUARD 22 positive: succeeded=true`); other guards not re-counted; the portable image not re-run; divergences unchanged (220 live, next label 241).**
  - E24 hard-fails under the root locale; seven `AnimationTests` need a
    display device.

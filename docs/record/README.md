# The long-form project record

**This directory is the pre-2026-09-09 `CLAUDE.md`, moved here verbatim and
split at its top-level headings.** Concatenating `01-…` through `08-…` in
order reproduces that file byte for byte (checked with `diff` when the split
was made, at commit `6591360` on `feat/animation`).

It was moved because the file had grown to 4,172 lines / 307 KB — roughly
75k tokens loaded into every session — and most of it is *record* (task-by-task
test-count climbs, quoted human reports, the history of how each sentence was
corrected) rather than *rules*. The rules are now in the root `CLAUDE.md`,
which points here for the reasoning.

**Every citation into the old file still resolves.** Test names, ruling ids,
divergence labels, greps and the wording of each paragraph are unchanged; only
the location moved. When a sentence here expires, correct it here and, if it
changes a rule, in the root `CLAUDE.md` too — the practices doc's
"correct where it was COPIED TO" mechanism applies across the two files.

| file | what it holds |
|---|---|
| `01-start-here.md` | the decisions-doc index and the per-subsystem essays (identity, `List`, `Deferred`, `Component`, `@State`, `@Observable`, hitboxes, focus, `Text`) |
| `02-practices.md` | the taxonomy's history: shapes 12–16 and record-mechanisms 1–7, with the incidents that produced each |
| `03-verified-on-real-hardware.md` | every milestone's human-verification entry: what was looked at, what was said, what a positive report closes, and the standing scripts |
| `04-divergences.md` | the eleven divergences in full, plus the seven retired labels and why each was retired |
| `05-declared-but-inert.md` | the inert-API table with every row's full mechanism and grep |
| `06-build.md` | test/golden/guard counts milestone by milestone, the summary-line correction, the module-boundary staleness family |
| `07-layout-cost.md` | the per-node layout cost tables, the 100k cold frame, identity path construction |
| `08-when-ci-lands.md` | the three guarantees that lapse silently, and the guard count's six moves |

New milestones should append their record **here** (a new file or a new
section in the matching one) and put only the rule in `CLAUDE.md`.
